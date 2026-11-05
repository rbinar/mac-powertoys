import XCTest
@testable import MacPowerToys

@MainActor
final class ModuleCatalogTests: XCTestCase {
    private static let expectedModuleIDs: Set<String> = [
        "colorPicker", "findMyMouse", "mouseHighlighter", "crosshairs", "cursorWrap", "screenRuler", "zoomIt",
        "awake", "mouseJiggler", "clipboardManager", "markdownPreview", "screenAnnotation", "speechToText",
        "videoConverter", "pomodoroTimer", "testDataGenerator", "portManager", "systemInfo", "quickLaunch",
        "pdfTools", "screenCapture", "gitHubNotifier", "imageOptimizer",
        "textExtractor", "fileLocksmith", "advancedPaste", "powerRename", "archive",
    ]

    // Reads only AnyModule metadata; no model is created.
    func testCatalogIDsAreUniqueAndMatchTheFeatureSet() {
        let ids = ModuleCatalog.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "module ids must be unique")
        XCTAssertEqual(Set(ids), Self.expectedModuleIDs)
    }

    func testHubOrderMatchesTheLegacyFeatureCards() {
        let titles = HubItem.layout(ModuleCatalog.all).map { item -> String in
            switch item {
            case .module(let id): return ModuleCatalog.all.first { $0.id == id }!.title
            case .group(let group, _): return group.title
            }
        }
        XCTAssertEqual(titles, [
            "Color Picker", "Screen Ruler", "ZoomIt", "Mouse Utilities", "Mouse Jiggler", "Awake", "Pomodoro Timer",
            "Clipboard Manager", "Markdown Preview", "Screen Annotation", "Video Converter", "PDF Tools", "Quick Launch",
            "Test Data Generator", "Speech to Text", "Port Manager", "System Info", "Screen Capture", "Image Optimizer",
            "GitHub Notifier", "Text Extractor", "File Locksmith", "Advanced Paste", "PowerRename", "Archive",
        ])
    }
}
