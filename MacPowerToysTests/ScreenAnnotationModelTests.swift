import XCTest
@testable import MacPowerToys

// Drawing via mouse, overlay windows and hotkeys need a live session and are not tested here.
@MainActor
final class ScreenAnnotationModelTests: XCTestCase {
    private let keys = ["screenAnnotation.isEnabled"]
    private var savedValues: [String: Any] = [:]
    private var model: ScreenAnnotationModel!

    override func setUp() {
        super.setUp()
        // Tests run inside the app host, so keep the user's real settings and restore them afterwards.
        savedValues = [:]
        for key in keys {
            if let value = UserDefaults.standard.object(forKey: key) { savedValues[key] = value }
            UserDefaults.standard.removeObject(forKey: key)
        }
        model = ScreenAnnotationModel()
    }

    override func tearDown() {
        model.stopMonitoring()
        model = nil
        for key in keys {
            UserDefaults.standard.removeObject(forKey: key)
            if let value = savedValues[key] { UserDefaults.standard.set(value, forKey: key) }
        }
        super.tearDown()
    }

    private func line(_ x: CGFloat) -> Annotation {
        Annotation(tool: .line, points: [CGPoint(x: x, y: 0), CGPoint(x: x, y: 10)], color: .systemRed, lineWidth: 4, text: nil, isFilled: false)
    }

    // MARK: - Undo

    func testClearAllIsUndoable() {
        model.annotations = [line(1), line(2)]

        model.clearAll()
        XCTAssertTrue(model.annotations.isEmpty)

        model.undo()
        XCTAssertEqual(model.annotations.map { $0.points[0].x }, [1, 2])
    }

    func testDeleteSelectedIsUndoable() {
        model.annotations = [line(1), line(2), line(3)]
        model.selectedAnnotationIndex = 1

        model.deleteSelected()
        XCTAssertEqual(model.annotations.map { $0.points[0].x }, [1, 3])

        model.undo()
        XCTAssertEqual(model.annotations.map { $0.points[0].x }, [1, 2, 3])
    }

    func testUndoRestoresInReverseOrder() {
        model.annotations = [line(1), line(2)]
        model.selectedAnnotationIndex = 0
        model.deleteSelected()
        model.clearAll()

        model.undo()
        XCTAssertEqual(model.annotations.map { $0.points[0].x }, [2])
        model.undo()
        XCTAssertEqual(model.annotations.map { $0.points[0].x }, [1, 2])
    }

    // MARK: - Text note contrast

    func testLightTextGetsDarkBackground() {
        XCTAssertTrue(ScreenAnnotationOverlayView.textNeedsDarkBackground(.white))
        XCTAssertTrue(ScreenAnnotationOverlayView.textNeedsDarkBackground(NSColor(srgbRed: 1, green: 0.9, blue: 0, alpha: 1)))
    }

    func testDarkTextGetsLightBackground() {
        XCTAssertFalse(ScreenAnnotationOverlayView.textNeedsDarkBackground(.black))
        XCTAssertFalse(ScreenAnnotationOverlayView.textNeedsDarkBackground(NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)))
    }
}
