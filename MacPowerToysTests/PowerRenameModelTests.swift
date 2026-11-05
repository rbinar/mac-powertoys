import XCTest
@testable import MacPowerToys

@MainActor
final class PowerRenameModelTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("powerrename-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    // MARK: Helpers

    private func url(_ name: String) -> URL { dir.appendingPathComponent(name) }

    @discardableResult
    private func make(_ name: String, _ content: String = "") -> URL {
        let u = url(name)
        try? content.write(to: u, atomically: true, encoding: .utf8)
        return u
    }

    private func names(_ plan: RenamePlan) -> [String] { plan.rows.map(\.newName) }

    private func plan(_ files: [String], _ options: RenameOptions) -> RenamePlan {
        PowerRenameModel.plan(urls: files.map(url), options: options, exists: { _ in false })
    }

    private func listing() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
    }

    // MARK: Planning

    func testLiteralReplaceIsCaseInsensitiveByDefault() {
        let p = plan(["Foo.txt", "foo.txt"], RenameOptions(search: "foo", replace: "bar"))
        XCTAssertEqual(names(p), ["bar.txt", "bar.txt"])
    }

    func testLiteralSearchTreatsRegexCharsLiterally() {
        let p = plan(["a.b.txt", "axb.txt"], RenameOptions(search: ".", replace: "_"))
        XCTAssertEqual(names(p), ["a_b.txt", "axb.txt"])
        let q = plan(["cost$1.txt"], RenameOptions(search: "cost", replace: "$1"))
        XCTAssertEqual(names(q), ["$1$1.txt"])
    }

    func testCaseSensitivity() {
        let p = plan(["Foo.txt", "foo.txt"], RenameOptions(search: "foo", replace: "x", caseSensitive: true))
        XCTAssertEqual(names(p), ["Foo.txt", "x.txt"])
        XCTAssertEqual(p.rows[0].status, .unchanged)
    }

    func testRegexWithCaptureGroups() {
        let p = plan(["IMG_001.jpg"], RenameOptions(search: "IMG_(\\d+)", replace: "photo-$1", useRegex: true))
        XCTAssertEqual(names(p), ["photo-001.jpg"])
    }

    func testInvalidRegexReportsErrorAndBlocksApply() {
        let p = plan(["a.txt"], RenameOptions(search: "(", replace: "x", useRegex: true))
        XCTAssertNotNil(p.regexError)
        XCTAssertFalse(p.canApply)
    }

    func testNumberingCountsFromOneInListOrder() {
        let p = plan(["a.txt", "b.txt", "c.txt"], RenameOptions(search: "^.*$", replace: "file{n}", useRegex: true, numbering: true))
        XCTAssertEqual(names(p), ["file1.txt", "file2.txt", "file3.txt"])
    }

    func testNumberingOffLeavesPlaceholderLiteral() {
        let p = plan(["a.txt"], RenameOptions(search: "a", replace: "x{n}"))
        XCTAssertEqual(names(p), ["x{n}.txt"])
    }

    func testExtensionIsExcludedUnlessIncluded() {
        let off = plan(["txt.txt"], RenameOptions(search: "txt", replace: "md"))
        XCTAssertEqual(names(off), ["md.txt"])
        let on = plan(["txt.txt"], RenameOptions(search: "txt", replace: "md", includeExtension: true))
        XCTAssertEqual(names(on), ["md.md"])
    }

    func testEmptySearchChangesNothing() {
        let p = plan(["a.txt"], RenameOptions(search: "", replace: "x"))
        XCTAssertEqual(p.changedCount, 0)
        XCTAssertNil(p.regexError)
    }

    // MARK: Conflicts

    func testDuplicateResultsConflictCaseInsensitively() {
        let p = plan(["a1.txt", "a2.txt"], RenameOptions(search: "a\\d", replace: "X", useRegex: true))
        XCTAssertEqual(p.rows[0].status, .conflict("Duplicate name"))
        XCTAssertFalse(p.canApply)
        let q = plan(["a.txt", "b.txt"], RenameOptions(search: "^a$|^b$", replace: "z", useRegex: true))
        XCTAssertTrue(q.hasConflict)
        let r = plan(["a.txt", "B.txt"], RenameOptions(search: "^a$", replace: "b", useRegex: true))
        XCTAssertEqual(r.rows[0].status, .conflict("Duplicate name"))
    }

    func testResultMatchingUnchangedBatchFileConflicts() {
        let p = plan(["a.txt", "b.txt"], RenameOptions(search: "a", replace: "b", caseSensitive: true))
        XCTAssertEqual(p.rows[0].status, .conflict("Duplicate name"))
    }

    func testExistingFileOnDiskConflictsCaseInsensitively() {
        make("a.txt"); make("TARGET.txt")
        let p = PowerRenameModel.plan(urls: [url("a.txt")], options: RenameOptions(search: "a", replace: "target"))
        XCTAssertEqual(p.rows[0].status, .conflict("Already exists"))
        XCTAssertFalse(p.canApply)
    }

    func testExistingFileThatIsPartOfTheBatchIsNotAConflict() {
        make("a.txt"); make("b.txt")
        let p = PowerRenameModel.plan(urls: [url("a.txt"), url("b.txt")],
                                      options: RenameOptions(search: "^(a|b)$", replace: "", useRegex: true))
        XCTAssertTrue(p.hasConflict) // empty stems
        let swap = PowerRenameModel.plan(urls: [url("a.txt"), url("b.txt")],
                                         options: RenameOptions(search: "^a$", replace: "b", useRegex: true))
        XCTAssertEqual(swap.rows[0].status, .conflict("Duplicate name"))
        let chain = PowerRenameModel.plan(urls: [url("a.txt"), url("b.txt")],
                                          options: RenameOptions(search: "^a$|^b$", replace: "c", useRegex: true))
        XCTAssertTrue(chain.hasConflict)
        let ok = PowerRenameModel.plan(urls: [url("a.txt"), url("b.txt")],
                                       options: RenameOptions(search: "^b$", replace: "c", useRegex: true))
        XCTAssertTrue(ok.canApply)
        let into = PowerRenameModel.plan(urls: [url("a.txt"), url("b.txt")],
                                         options: RenameOptions(search: "^a$|^b$", replace: "x", useRegex: true))
        XCTAssertTrue(into.hasConflict)
    }

    func testEmptyNameConflicts() {
        let p = plan(["abc"], RenameOptions(search: "abc", replace: "", includeExtension: true))
        XCTAssertEqual(p.rows[0].status, .conflict("Empty name"))
        let q = plan(["abc.txt"], RenameOptions(search: "abc", replace: ""))
        XCTAssertEqual(q.rows[0].status, .conflict("Empty name"))
    }

    func testSlashInNameConflicts() {
        let p = plan(["a.txt"], RenameOptions(search: "a", replace: "x/y"))
        XCTAssertEqual(p.rows[0].status, .conflict("Name contains /"))
    }

    // MARK: Applying

    func testSwapIsApplied() throws {
        make("a.txt", "A"); make("b.txt", "B")
        try PowerRenameModel.apply([RenameMove(from: url("a.txt"), to: url("b.txt")),
                                    RenameMove(from: url("b.txt"), to: url("a.txt"))])
        XCTAssertEqual(try String(contentsOf: url("a.txt")), "B")
        XCTAssertEqual(try String(contentsOf: url("b.txt")), "A")
        XCTAssertEqual(listing(), ["a.txt", "b.txt"])
    }

    func testChainIsApplied() throws {
        make("a.txt", "A"); make("b.txt", "B")
        try PowerRenameModel.apply([RenameMove(from: url("a.txt"), to: url("b.txt")),
                                    RenameMove(from: url("b.txt"), to: url("c.txt"))])
        XCTAssertEqual(try String(contentsOf: url("b.txt")), "A")
        XCTAssertEqual(try String(contentsOf: url("c.txt")), "B")
        XCTAssertEqual(listing(), ["b.txt", "c.txt"])
    }

    func testCaseOnlyRenameWorks() throws {
        make("a.txt", "A")
        let model = PowerRenameModel()
        model.addFiles([url("a.txt")])
        model.search = "a"; model.replace = "A"; model.caseSensitive = true
        XCTAssertTrue(model.plan.canApply)
        model.applyRename()
        XCTAssertEqual(listing(), ["A.txt"])
    }

    func testRollbackOnFailureRestoresEverything() {
        make("a.txt", "A"); make("b.txt", "B"); make("blocker.txt", "X")
        let moves = [RenameMove(from: url("a.txt"), to: url("c.txt")),
                     RenameMove(from: url("b.txt"), to: url("blocker.txt"))]
        XCTAssertThrowsError(try PowerRenameModel.apply(moves))
        XCTAssertEqual(listing(), ["a.txt", "b.txt", "blocker.txt"])
        XCTAssertEqual(try? String(contentsOf: url("a.txt")), "A")
        XCTAssertEqual(try? String(contentsOf: url("b.txt")), "B")
        XCTAssertEqual(try? String(contentsOf: url("blocker.txt")), "X")
    }

    // MARK: Model flow / undo

    func testApplyThenUndoRestoresNames() {
        make("one.txt"); make("two.txt")
        let model = PowerRenameModel()
        model.addFiles([url("one.txt"), url("two.txt")])
        model.search = "^.*$"; model.useRegex = true; model.replace = "f{n}"; model.numbering = true
        model.applyRename()
        XCTAssertEqual(listing(), ["f1.txt", "f2.txt"])
        XCTAssertFalse(model.lastBatch.isEmpty)
        model.undo()
        XCTAssertEqual(listing(), ["one.txt", "two.txt"])
        XCTAssertTrue(model.lastBatch.isEmpty)
    }

    func testUndoReportsFileThatMovedAndRestoresTheRest() {
        make("one.txt"); make("two.txt")
        let model = PowerRenameModel()
        model.addFiles([url("one.txt"), url("two.txt")])
        model.search = "^.*$"; model.useRegex = true; model.replace = "f{n}"; model.numbering = true
        model.applyRename()
        try? FileManager.default.removeItem(at: url("f1.txt"))
        model.undo()
        XCTAssertEqual(listing(), ["two.txt"])
        XCTAssertTrue(model.message?.contains("1 file(s) had moved") ?? false)
    }

    func testApplyIsBlockedWhileConflicting() {
        make("a1.txt"); make("a2.txt")
        let model = PowerRenameModel()
        model.addFiles([url("a1.txt"), url("a2.txt")])
        model.search = "a\\d"; model.useRegex = true; model.replace = "X"
        model.applyRename()
        XCTAssertEqual(listing(), ["a1.txt", "a2.txt"])
    }
}
