import XCTest
@testable import MacPowerToys

// Overlay, ScreenCaptureKit capture and the Vision request need a live session/permissions and are not tested here.
@MainActor
final class TextExtractorModelTests: XCTestCase {
    private let key = "textExtractor.isEnabled"
    private var saved: Any?

    override func setUp() {
        super.setUp()
        saved = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.removeObject(forKey: key)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: key)
        if let saved { UserDefaults.standard.set(saved, forKey: key) }
        super.tearDown()
    }

    private func run(_ text: String, x: CGFloat, y: CGFloat, w: CGFloat = 0.2, h: CGFloat = 0.05) -> RecognizedText {
        RecognizedText(text: text, box: CGRect(x: x, y: y, width: w, height: h))
    }

    // MARK: - Ordering

    func testJoinsTopToBottom() {
        // Vision y grows upward, so the highest y is the top line.
        let result = TextExtractorOCR.join([run("bottom", x: 0.1, y: 0.1), run("top", x: 0.1, y: 0.8), run("middle", x: 0.1, y: 0.45)])
        XCTAssertEqual(result, "top\nmiddle\nbottom")
    }

    func testSameLineRunsGoLeftToRight() {
        let result = TextExtractorOCR.join([run("world", x: 0.5, y: 0.801), run("Hello", x: 0.1, y: 0.8), run("next", x: 0.1, y: 0.5)])
        XCTAssertEqual(result, "Hello world\nnext")
    }

    func testEmptyOrBlankInputIsNil() {
        XCTAssertNil(TextExtractorOCR.join([]))
        XCTAssertNil(TextExtractorOCR.join([run("  \n", x: 0.1, y: 0.1)]))
    }

    // MARK: - Persistence

    func testIsEnabledPersists() {
        let first = TextExtractorModel()
        XCTAssertFalse(first.isEnabled)
        first.isEnabled = true
        XCTAssertTrue(UserDefaults.standard.bool(forKey: key))
        first.stopMonitoring()

        let second = TextExtractorModel()
        XCTAssertTrue(second.isEnabled)
        second.stopMonitoring()
    }
}
