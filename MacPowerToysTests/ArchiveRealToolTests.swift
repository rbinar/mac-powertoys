import XCTest
@testable import MacPowerToys

/// Runs the real 7zz, because its password behavior can't be stubbed. Skipped when 7zz is not installed.
@MainActor
final class ArchiveRealToolTests: XCTestCase {
    private var dir: URL!
    private let text = "merhaba ğüşıİ\n"

    override func setUpWithError() throws {
        let path = ["/opt/homebrew/bin/7zz", "/usr/local/bin/7zz"].first { FileManager.default.isExecutableFile(atPath: $0) }
        try XCTSkipIf(path == nil, "7zz is not installed")
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("archive-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let dir { try? FileManager.default.removeItem(at: dir) }
        super.tearDown()
    }

    /// `perform` runs twice for encrypted extraction, so require idle to hold for a moment.
    private func finish(_ model: ArchiveModel) async {
        var idle = 0
        let deadline = Date().addingTimeInterval(30)
        while idle < 15, Date() < deadline {
            idle = model.isBusy ? 0 : idle + 1
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private func createArchive(_ format: ArchiveFormat, password: String) async throws -> URL {
        let file = dir.appendingPathComponent("a.txt")
        try text.write(to: file, atomically: true, encoding: .utf8)
        let model = ArchiveModel()
        model.addItems([file])
        model.format = format
        model.compressPassword = password
        model.compress()
        await finish(model)
        XCTAssertNil(model.errorMessage)
        let archive = try XCTUnwrap(model.resultURL)
        try FileManager.default.removeItem(at: file)
        return archive
    }

    func testWrongZipPasswordLeavesNoFilesAndRightOneExtracts() async throws {
        let archive = try await createArchive(.zip, password: "pass word1")
        let model = ArchiveModel()
        model.setArchive(archive)
        await finish(model)
        XCTAssertEqual(model.entries.first?.isEncrypted, true)

        model.extractPassword = "wrong"
        model.extract(toFolder: false)
        await finish(model)
        XCTAssertEqual(model.errorMessage, "Wrong password. Try again.")
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("a.txt").path))

        model.extractPassword = "pass word1"
        model.extract(toFolder: false)
        await finish(model)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent("a.txt"), encoding: .utf8), text)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("a_1.txt").path))
    }

    func testEncryptedNames7zAsksForPasswordAndAcceptsTurkishOne() async throws {
        let password = "p@ss wörd"
        let archive = try await createArchive(.sevenZip, password: password)
        let model = ArchiveModel()
        model.setArchive(archive)
        await finish(model)
        XCTAssertTrue(model.needsPassword)
        XCTAssertTrue(model.entries.isEmpty)

        model.extractPassword = password
        model.loadListing()
        await finish(model)
        XCTAssertFalse(model.needsPassword)
        XCTAssertFalse(model.entries.isEmpty)

        model.extract(toFolder: false)
        await finish(model)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent("a.txt"), encoding: .utf8), text)
    }
}
