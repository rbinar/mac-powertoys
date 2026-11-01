import XCTest
@testable import MacPowerToys

@MainActor
final class AwakeModelTests: XCTestCase {
    func testFormatRemainingBelowOneHourIsMinutesSeconds() {
        XCTAssertEqual(AwakeModel.formatRemaining(0), "0:00")
        XCTAssertEqual(AwakeModel.formatRemaining(1799), "29:59")
        XCTAssertEqual(AwakeModel.formatRemaining(3599), "59:59")
    }

    func testFormatRemainingFromOneHourIsHoursMinutesSeconds() {
        XCTAssertEqual(AwakeModel.formatRemaining(3600), "1:00:00")
        XCTAssertEqual(AwakeModel.formatRemaining(240 * 60), "4:00:00")
        XCTAssertEqual(AwakeModel.formatRemaining(7325), "2:02:05")
    }
}
