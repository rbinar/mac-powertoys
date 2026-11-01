import XCTest
@testable import MacPowerToys

@MainActor
final class ModuleCatalogTests: XCTestCase {
    private static let expectedModuleIDs: Set<String> = [
        "colorPicker", "findMyMouse", "mouseHighlighter", "crosshairs", "cursorWrap", "screenRuler", "zoomIt",
        "awake", "mouseJiggler", "clipboardManager", "markdownPreview", "screenAnnotation", "speechToText",
        "videoConverter", "pomodoroTimer", "testDataGenerator", "portManager", "systemInfo", "quickLaunch",
        "pdfTools", "screenCapture", "gitHubNotifier", "imageOptimizer",
    ]

    // Reads only AnyModule metadata; no model is created.
    func testCatalogIDsAreUniqueAndMatchTheFeatureSet() {
        let ids = ModuleCatalog.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "module ids must be unique")
        XCTAssertEqual(Set(ids), Self.expectedModuleIDs)
    }
}
