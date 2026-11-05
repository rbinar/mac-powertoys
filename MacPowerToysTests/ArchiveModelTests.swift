import XCTest
@testable import MacPowerToys

// Password behavior and the samples in testRealOutput* were measured with 7zz 26.05. Other samples are hand-written.
// 7zz-dependent paths (running the process, the stdin password) are intentionally not tested.
@MainActor
final class ArchiveModelTests: XCTestCase {
    func testOnlyExitZeroAndOneCountAsSuccess() {
        XCTAssertTrue(ArchiveModel.succeeded(0))
        XCTAssertTrue(ArchiveModel.succeeded(1))
        XCTAssertFalse(ArchiveModel.succeeded(2))
        XCTAssertFalse(ArchiveModel.succeeded(-1)) // 7zz could not be started
    }

    private let listing = """

    7-Zip (z) 24.08 (arm64) : Copyright (c) 1999-2024 Igor Pavlov : 2024-08-11

    Scanning the drive for archives:
    1 file, 1234 bytes (2 KiB)

    Listing archive: a.rar

    --
    Path = a.rar
    Type = Rar5
    Physical Size = 1234
    Solid = -
    Headers Size = 200
    Encrypted = +

    ----------
    Path = docs
    Folder = +
    Size = 0
    Packed Size = 0
    Attributes = D drwxr-xr-x

    Path = docs/readme.txt
    Folder = -
    Size = 1500
    Packed Size = 600
    Encrypted = +
    Attributes = A -rw-r--r--

    Path = -dash.txt
    Folder = -
    Size = 7
    Packed Size = 7
    Attributes = A -rw-r--r--

    """

    func testParseListingReadsEntriesAfterHeader() {
        let e = ArchiveModel.parseListing(listing)
        XCTAssertEqual(e.map(\.path), ["docs", "docs/readme.txt", "-dash.txt"])
        XCTAssertTrue(e[0].isFolder)
        XCTAssertFalse(e[1].isFolder)
        XCTAssertEqual(e[1].size, 1500)
        XCTAssertTrue(e[1].isEncrypted)
        XCTAssertFalse(e[2].isEncrypted)
    }

    func testParseListingEmptyAndHeaderOnly() {
        XCTAssertTrue(ArchiveModel.parseListing("").isEmpty)
        XCTAssertTrue(ArchiveModel.parseListing("--\nPath = a.rar\nType = Rar5\n").isEmpty)
    }

    func testEncryptedHeaderFailureIsAPasswordFailure() {
        let out = "Listing archive: a.rar\n\nERROR: Cannot open encrypted archive. Wrong password?\n\nErrors: 1\n"
        XCTAssertTrue(ArchiveModel.isPasswordFailure(out))
        XCTAssertTrue(ArchiveModel.parseListing(out).isEmpty)
    }

    func testWrongPasswordMessage() {
        XCTAssertTrue(ArchiveModel.isPasswordFailure("ERROR: Wrong password : docs/readme.txt\n"))
        XCTAssertTrue(ArchiveModel.isPasswordFailure("ERROR: Data Error in encrypted file. Wrong password? : x.txt"))
        XCTAssertFalse(ArchiveModel.isPasswordFailure("ERROR: No more files\n"))
        XCTAssertFalse(ArchiveModel.isPasswordFailure("Everything is Ok\n"))
    }

    func testRealOutputPasswordDetection() {
        XCTAssertTrue(ArchiveModel.isPasswordFailure("Listing archive: o.7z\nEnter password:\nBreak signaled\n"))
        XCTAssertTrue(ArchiveModel.isPasswordFailure("Enter password:\nERROR: o.7z : Cannot open encrypted archive. Wrong password?\nErrors: 1\n"))
        XCTAssertTrue(ArchiveModel.isPasswordFailure("Enter password:\nERROR: Wrong password : a.txt\nSub items Errors: 2\n"))
        // Every encrypted run prints the prompt, so other failures must not read as a wrong password.
        XCTAssertFalse(ArchiveModel.isPasswordFailure("Enter password:\nERROR: Unexpected end of archive : a.zip\n"))
    }

    func testRealOutputProgress() {
        XCTAssertEqual(ArchiveModel.parseProgress("\u{8}\u{8} 39% 1 + big.bin\u{8}\u{8}    \u{8}\u{8} 41% 1 + big.bin"), 41)
    }

    func testOnlyZipPasswordsMustBeAscii() {
        XCTAssertFalse(ArchiveModel.canUsePassword("p@ss wörd", format: .zip))
        XCTAssertTrue(ArchiveModel.canUsePassword("pass word1", format: .zip))
        XCTAssertTrue(ArchiveModel.canUsePassword("p@ss wörd", format: .sevenZip))
    }

    func testErrorSummary() {
        XCTAssertEqual(ArchiveModel.errorSummary("foo\nERROR: Unexpected end of archive : a.zip\n", status: 2),
                       "Unexpected end of archive : a.zip")
        XCTAssertEqual(ArchiveModel.errorSummary("nothing", status: 2), "7zz failed (exit 2).")
    }

    func testProgressParsing() {
        XCTAssertEqual(ArchiveModel.parseProgress(" 12%"), 12)
        XCTAssertEqual(ArchiveModel.parseProgress(" 12% 3 - docs/readme.txt\r 45% 4 - docs/b.txt"), 45)
        XCTAssertEqual(ArchiveModel.parseProgress("100%"), 100)
        XCTAssertNil(ArchiveModel.parseProgress("Everything is Ok"))
        XCTAssertNil(ArchiveModel.parseProgress("250%"))
    }

    func testFirstPartResolution() {
        XCTAssertEqual(ArchiveModel.firstPartName("movie.part03.rar"), "movie.part01.rar")
        XCTAssertEqual(ArchiveModel.firstPartName("movie.part01.rar"), "movie.part01.rar")
        XCTAssertEqual(ArchiveModel.firstPartName("movie.part7.rar"), "movie.part1.rar")
        XCTAssertEqual(ArchiveModel.firstPartName("movie.part007.rar"), "movie.part001.rar")
        XCTAssertEqual(ArchiveModel.firstPartName("Movie.PART02.RAR"), "Movie.PART01.RAR")
        XCTAssertEqual(ArchiveModel.firstPartName("data.7z.003"), "data.7z.001")
        XCTAssertEqual(ArchiveModel.firstPartName("data.001"), "data.001")
        XCTAssertEqual(ArchiveModel.firstPartName("plain.rar"), "plain.rar")
        XCTAssertEqual(ArchiveModel.firstPartName("archive.zip"), "archive.zip")
    }

    func testBaseName() {
        XCTAssertEqual(ArchiveModel.archiveBaseName("movie.part01.rar"), "movie")
        XCTAssertEqual(ArchiveModel.archiveBaseName("data.7z.001"), "data")
        XCTAssertEqual(ArchiveModel.archiveBaseName("src.tar.gz"), "src")
        XCTAssertEqual(ArchiveModel.archiveBaseName("a.zip"), "a")
        XCTAssertEqual(ArchiveModel.archiveBaseName("noext"), "noext")
    }

    func testUniqueURL() {
        let base = URL(fileURLWithPath: "/tmp/x/a.zip")
        XCTAssertEqual(ArchiveModel.uniqueURL(base, exists: { _ in false }), base)
        let taken: Set<String> = ["/tmp/x/a.zip", "/tmp/x/a 2.zip"]
        XCTAssertEqual(ArchiveModel.uniqueURL(base, exists: { taken.contains($0.path) }).path, "/tmp/x/a 3.zip")
        let folder = URL(fileURLWithPath: "/tmp/x/a")
        XCTAssertEqual(ArchiveModel.uniqueURL(folder, exists: { $0.path == "/tmp/x/a" }).path, "/tmp/x/a 2")
    }

    func testExtractArgumentsNeverContainPassword() {
        let secret = "s3cret!"
        let args = ArchiveModel.extractArguments(archive: "/t/-evil.rar", outputDir: "/t/out")
        XCTAssertFalse(args.joined(separator: " ").contains(secret))
        XCTAssertFalse(args.contains("-p")) // a bare -p means an empty password when reading
        XCTAssertTrue(args.contains("-aou"))
        XCTAssertTrue(args.contains("-o/t/out"))
        XCTAssertEqual(args.suffix(2), ["--", "/t/-evil.rar"])
    }

    func testListArguments() {
        XCTAssertEqual(ArchiveModel.listArguments(archive: "a.rar"), ["l", "-slt", "--", "a.rar"])
        XCTAssertEqual(ArchiveModel.testArguments(archive: "a.rar"), ["t", "-bsp1", "--", "a.rar"])
    }

    func testCompressArguments() {
        let args = ArchiveModel.compressArguments(output: "/t/out.7z", items: ["-rf.txt", "dir"], format: .sevenZip,
                                                  level: .best, usePassword: true)
        XCTAssertEqual(args, ["a", "-t7z", "-mx=9", "-bsp1", "-p", "-mhe=on", "--", "/t/out.7z", "-rf.txt", "dir"])
        let zip = ArchiveModel.compressArguments(output: "o.zip", items: ["a"], format: .zip, level: .fast, usePassword: false)
        XCTAssertEqual(zip, ["a", "-tzip", "-mx=1", "-bsp1", "--", "o.zip", "a"])
        XCTAssertTrue(ArchiveModel.compressArguments(output: "o.zip", items: ["a"], format: .zip, level: .normal,
                                                     usePassword: true).contains("-mem=AES256"))
        XCTAssertEqual(ArchiveLevel.normal.mx, 5)
    }

    func testPasswordGoesToStdinNotArguments() {
        XCTAssertEqual(String(decoding: ArchiveModel.passwordInput("pw", confirm: false), as: UTF8.self), "pw\n")
        XCTAssertEqual(String(decoding: ArchiveModel.passwordInput("pw", confirm: true), as: UTF8.self), "pw\npw\n")
    }

    func testItemArgument() {
        let base = URL(fileURLWithPath: "/t/dir")
        XCTAssertEqual(ArchiveModel.itemArgument(URL(fileURLWithPath: "/t/dir/a.txt"), base: base), "a.txt")
        XCTAssertEqual(ArchiveModel.itemArgument(URL(fileURLWithPath: "/other/b.txt"), base: base), "/other/b.txt")
    }

    // MARK: - RAR through unar / lsar (strings measured with unar 1.10.7)

    func testIsRAR() {
        for name in ["a.rar", "A.RAR", "movie.part02.rar", "x.r00", "x.r99", "X.R01"] {
            XCTAssertTrue(ArchiveModel.isRAR(name), name)
        }
        for name in ["a.zip", "a.7z", "a.rar.txt", "a.r1", "a.r001", "rar", "a.001"] {
            XCTAssertFalse(ArchiveModel.isRAR(name), name)
        }
    }

    func testOldStyleRarVolumesResolveToFirstPart() {
        XCTAssertEqual(ArchiveModel.firstPartName("x.r01"), "x.rar")
        XCTAssertEqual(ArchiveModel.firstPartName("x.r00"), "x.rar")
        XCTAssertEqual(ArchiveModel.firstPartName("X.R12"), "X.RAR")
        XCTAssertEqual(ArchiveModel.firstPartName("my.data.r05"), "my.data.rar")
    }

    func testUnarAndLsarArguments() {
        XCTAssertEqual(ArchiveModel.lsarArguments(archive: "-a.rar", password: nil), ["-j", "--", "-a.rar"])
        XCTAssertEqual(ArchiveModel.lsarArguments(archive: "a.rar", password: "pw"), ["-j", "-p", "pw", "--", "a.rar"])
        XCTAssertEqual(ArchiveModel.lsarTestArguments(archive: "a.rar", password: ""), ["-t", "--", "a.rar"])
        XCTAssertEqual(ArchiveModel.lsarTestArguments(archive: "a.rar", password: "pw"), ["-t", "-p", "pw", "--", "a.rar"])
        XCTAssertEqual(ArchiveModel.unarArguments(archive: "/t/-a.rar", outputDir: "/t/out", password: nil),
                       ["-q", "-nr", "-r", "-D", "-o", "/t/out", "--", "/t/-a.rar"])
        XCTAssertEqual(ArchiveModel.unarArguments(archive: "a.rar", outputDir: "/o", password: "pw"),
                       ["-q", "-nr", "-r", "-D", "-o", "/o", "-p", "pw", "--", "a.rar"])
    }

    func testParseLsar() throws {
        let json = """
        {"lsarFormatVersion": 2, "lsarContents": [
          {"XADFileName": "sub", "XADIsDirectory": true},
          {"XADFileName": "sub/a.txt", "XADFileSize": 2048, "XADIsEncrypted": true},
          {"XADFileName": "b.txt", "XADFileSize": 6}
        ], "lsarProperties": {"XADIsEncrypted": true}}
        """
        let e = try XCTUnwrap(ArchiveModel.parseLsar(json))
        XCTAssertEqual(e.map(\.path), ["sub", "sub/a.txt", "b.txt"])
        XCTAssertTrue(e[0].isFolder)
        XCTAssertFalse(e[1].isFolder)
        XCTAssertEqual(e[1].size, 2048)
        XCTAssertTrue(e[1].isEncrypted)
        XCTAssertFalse(e[2].isEncrypted)
        XCTAssertEqual(ArchiveModel.parseLsar("{\"lsarContents\": [], \"lsarError\": 15}"), [])
    }

    func testParseLsarReturnsNilForNonJson() {
        XCTAssertNil(ArchiveModel.parseLsar("This archive requires a password to unpack. Use the -p option to provide one.\n{\n  \"lsarFormatVersion\": 2,"))
        XCTAssertNil(ArchiveModel.parseLsar(""))
        XCTAssertNil(ArchiveModel.parseLsar("{\"lsarFormatVersion\": 2, \"lsarError\": 0}"))
    }

    func testClassifyLsarOutput() {
        XCTAssertEqual(ArchiveModel.classifyLsar("a.rar: RAR 5\ns.txt... OK.\n1 passed, 0 failed.\n", status: 0), .ok)
        XCTAssertEqual(ArchiveModel.classifyLsar("a.rar: RAR 5\ns.txt... This archive requires a password to unpack. Use the -p option to provide one.\n", status: 2),
                       .needsPassword)
        XCTAssertEqual(ArchiveModel.classifyLsar("This archive requires a password to unpack. Use the -p option to provide one.\n{\n \"lsarContents\": [", status: 2),
                       .needsPassword)
        XCTAssertEqual(ArchiveModel.classifyLsar("a.rar: RAR 5\ns.txt... Wrong password!\n0 passed, 1 failed.\n", status: 1), .wrongPassword)
        XCTAssertEqual(ArchiveModel.classifyLsar("a.rar: RAR 5\nArchive parsing failed! (Missing or wrong password.)\n0 passed, 0 failed.\n", status: 1),
                       .wrongPassword)
        XCTAssertEqual(ArchiveModel.classifyLsar("{\"lsarContents\": [], \"lsarError\": 15}", status: 1), .wrongPassword)
        XCTAssertEqual(ArchiveModel.classifyLsar("Couldn't recognize the archive format.\n", status: 1), .failed)
        XCTAssertEqual(ArchiveModel.classifyLsar("Couldn't open archive.\n", status: 1), .failed)
        XCTAssertEqual(ArchiveModel.classifyLsar("{\"lsarError\": 11}", status: 1), .failed)
    }

    func testUnarErrorSummary() {
        XCTAssertEqual(ArchiveModel.unarErrorSummary("Couldn't open archive. (Opening file failed.)\n", status: 1),
                       "Couldn't open archive. (Opening file failed.)")
        XCTAssertEqual(ArchiveModel.unarErrorSummary("{\"lsarError\": 11}\n", status: 1), "unar failed (exit 1).")
        XCTAssertEqual(ArchiveModel.unarErrorSummary("", status: 1), "unar failed (exit 1).")
    }

    func testUnsafeSymlinkSelection() {
        let found: [(path: String, target: String)] = [
            ("/t/out/up", "/t"),                       // `up -> ..`
            ("/t/out/abs", "/etc"),
            ("/t/out/sibling", "/t/out2"),             // shares the name prefix, still outside
            ("/t/out/ok", "/t/out/sub/x"),
            ("/t/out/self", "/t/out"),
            ("/t/out/old", "/"),                       // existed before the run
            ("/elsewhere/up", "/"),                    // not under dest
        ]
        let result = ArchiveModel.unsafeSymlinks(dest: "/t/out", preExisting: ["/t/out/old"], found: found)
        XCTAssertEqual(result, ["/t/out/up", "/t/out/abs", "/t/out/sibling"])
        XCTAssertEqual(ArchiveModel.unsafeSymlinks(dest: "/t/out/", preExisting: [], found: [("/t/out/u", "/t")]), ["/t/out/u"])
    }

    func testRemoveUnsafeLinksOnlyTouchesNewOutsideLinks() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("archive-links-\(UUID().uuidString)")
        let dest = base.appendingPathComponent("dest")
        defer { try? fm.removeItem(at: base) }
        try fm.createDirectory(at: dest.appendingPathComponent("oldDir"), withIntermediateDirectories: true)
        let keep = base.appendingPathComponent("keep.txt")
        try "k".write(to: keep, atomically: true, encoding: .utf8)
        try fm.createSymbolicLink(atPath: dest.appendingPathComponent("old").path, withDestinationPath: "..")
        let before = ArchiveModel.snapshotSymlinks(in: dest)
        XCTAssertEqual(before.count, 2)

        // Only new top-level items are scanned; a pre-existing folder is left alone.
        try fm.createSymbolicLink(atPath: dest.appendingPathComponent("oldDir/notScanned").path, withDestinationPath: "../..")
        try fm.createDirectory(at: dest.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try fm.createSymbolicLink(atPath: dest.appendingPathComponent("up").path, withDestinationPath: "..")
        try fm.createSymbolicLink(atPath: dest.appendingPathComponent("sub/abs").path, withDestinationPath: keep.path)
        try fm.createSymbolicLink(atPath: dest.appendingPathComponent("sub/rel").path, withDestinationPath: "../../keep.txt")
        try fm.createSymbolicLink(atPath: dest.appendingPathComponent("fine").path, withDestinationPath: "sub")
        try fm.createSymbolicLink(atPath: dest.appendingPathComponent("dangling-in").path, withDestinationPath: "sub/none")
        try fm.createSymbolicLink(atPath: dest.appendingPathComponent("dangling-out").path, withDestinationPath: "../none")

        XCTAssertEqual(ArchiveModel.removeUnsafeLinks(in: dest, preExisting: before), 4)
        func isLink(_ p: String) -> Bool { (try? fm.destinationOfSymbolicLink(atPath: dest.appendingPathComponent(p).path)) != nil }
        XCTAssertTrue(isLink("old"))
        XCTAssertTrue(isLink("oldDir/notScanned"))
        XCTAssertTrue(isLink("fine"))
        XCTAssertTrue(isLink("dangling-in"))
        XCTAssertFalse(isLink("up"))
        XCTAssertFalse(isLink("sub/abs"))
        XCTAssertFalse(isLink("sub/rel"))
        XCTAssertFalse(isLink("dangling-out"))
        XCTAssertEqual(try String(contentsOf: keep, encoding: .utf8), "k")
        XCTAssertTrue(fm.fileExists(atPath: base.path))
        XCTAssertEqual(ArchiveModel.removeUnsafeLinks(in: dest, preExisting: before), 0)
    }
}
