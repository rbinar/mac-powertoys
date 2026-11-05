import XCTest
@testable import MacPowerToys

// Builds the real catalog (registers real hotkeys, like QuickLaunchModelTests does).
@MainActor
final class PaletteParityTests: XCTestCase {
    private var registry: ModuleRegistry!

    override func setUp() {
        super.setUp()
        registry = ModuleRegistry(catalog: ModuleCatalog.all)
    }

    override func tearDown() {
        registry.stopAll()
        registry = nil
        super.tearDown()
    }

    /// The command ids and order the palette had before the registry existed.
    private static let expectedCommandIDs = [
        "screenRuler.start", "zoomIt.screenZoom", "zoomIt.liveZoom", "screenAnnotation.start", "screenCapture.start",
        "colorPicker.pick", "findMyMouse.spotlight",
        "awake.toggle", "mouseJiggler.toggle", "crosshairs.toggle", "mouseHighlighter.toggle", "cursorWrap.toggle", "pomodoro.toggle",
        "clipboardManager.open", "pdfTools.open", "imageOptimizer.open", "videoConverter.open", "markdownPreview.open",
        "speechToText.open", "portManager.open", "systemInfo.open", "testDataGenerator.open", "gitHubNotifier.open",
        "textExtractor.start", "fileLocksmith.open",
    ]

    func testGeneratedCommandsMatchTheHandWrittenPaletteByIDAndOrder() {
        XCTAssertEqual(registry.paletteCommands.map(\.id), Self.expectedCommandIDs)
    }

    func testEveryCommandHasAScreen() {
        XCTAssertTrue(registry.paletteCommands.allSatisfy { $0.screen != nil })
    }
}
