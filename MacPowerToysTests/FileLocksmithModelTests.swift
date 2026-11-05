import XCTest
@testable import MacPowerToys

@MainActor
final class FileLocksmithModelTests: XCTestCase {
    func testParsesMultiplePids() {
        let out = "p100\ncSafari\nu501\nLrbinar\np200\ncPreview\nu501\nLrbinar\n"
        let result = FileLocksmithModel.parse(out)
        XCTAssertEqual(result, [
            LockingProcess(pid: 100, name: "Safari", user: "rbinar"),
            LockingProcess(pid: 200, name: "Preview", user: "rbinar"),
        ])
    }

    func testDuplicatePidWithSeveralFilesCollapsesToOne() {
        let out = "p100\ncSafari\nu501\nLrbinar\np100\ncSafari\nu501\nLrbinar\np200\ncPreview\nu501\nLrbinar\n"
        let result = FileLocksmithModel.parse(out)
        XCTAssertEqual(result.map(\.pid), [100, 200])
    }

    func testMissingLoginFallsBackToUid() {
        let result = FileLocksmithModel.parse("p100\ncSafari\nu501\n")
        XCTAssertEqual(result, [LockingProcess(pid: 100, name: "Safari", user: "uid 501")])
    }

    func testEmptyOutputGivesNoProcesses() {
        XCTAssertTrue(FileLocksmithModel.parse("").isEmpty)
    }

    func testPidSafetyGuard() {
        XCTAssertFalse(FileLocksmithModel.isSafeToSignal(pid: 0))
        XCTAssertFalse(FileLocksmithModel.isSafeToSignal(pid: 1))
        XCTAssertFalse(FileLocksmithModel.isSafeToSignal(pid: getpid()))
        XCTAssertTrue(FileLocksmithModel.isSafeToSignal(pid: getpid() + 1))
    }
}
