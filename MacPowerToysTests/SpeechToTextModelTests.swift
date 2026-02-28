import XCTest
@testable import MacPowerToys

@MainActor
final class SpeechToTextModelTests: XCTestCase {
    func testHubStatusTextBusy() {
        let model = SpeechToTextModel()
        model.viewState = .processing("Transcribing...")

        XCTAssertEqual(model.hubStatusText, "Busy")
    }

    func testHubStatusTextError() {
        let model = SpeechToTextModel()
        model.viewState = .error("Transcription failed: test")

        XCTAssertEqual(model.hubStatusText, "Error")
    }

    func testHubStatusTextReady() {
        let model = SpeechToTextModel()
        model.viewState = .completed

        XCTAssertEqual(model.hubStatusText, "Ready")
    }

    func testHubStatusTextNotReady() {
        let model = SpeechToTextModel()

        XCTAssertEqual(model.hubStatusText, "Not ready")
    }
}
