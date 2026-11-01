import XCTest
@testable import MacPowerToys

// Overlay windows, screen capture and hotkeys need a live session/permissions and are not tested here.
@MainActor
final class ScreenRulerModelTests: XCTestCase {
    private let keys = ["screenRuler.isEnabled", "screenRuler.measurementMode"]
    private var savedValues: [String: Any] = [:]
    private var model: ScreenRulerModel?

    override func setUp() {
        super.setUp()
        // Tests run inside the app host, so keep the user's real settings and restore them afterwards.
        savedValues = [:]
        for key in keys {
            if let value = UserDefaults.standard.object(forKey: key) { savedValues[key] = value }
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    override func tearDown() {
        model?.stopMonitoring()
        model = nil
        for key in keys {
            UserDefaults.standard.removeObject(forKey: key)
            if let value = savedValues[key] { UserDefaults.standard.set(value, forKey: key) }
        }
        super.tearDown()
    }

    // MARK: - Pixels

    func testPixelsFromPointsMultipliesByBackingScale() {
        XCTAssertEqual(ScreenRulerUnits.pixels(fromPoints: 100, scale: 2), 200)
        XCTAssertEqual(ScreenRulerUnits.pixels(fromPoints: 100, scale: 1), 100)
        XCTAssertEqual(ScreenRulerUnits.pixels(fromPoints: 10.5, scale: 2), 21)
        XCTAssertEqual(ScreenRulerUnits.pixels(fromPoints: 7, scale: 3), 21)
    }

    // MARK: - Physical DPI

    func testPixelsPerInchFromPixelWidthAndPhysicalWidth() throws {
        // 2540 px across 254 mm (10 in) = 254 px/in
        let ppi = try XCTUnwrap(ScreenRulerUnits.pixelsPerInch(pixelWidth: 2540, physicalWidthMM: 254))
        XCTAssertEqual(ppi, 254, accuracy: 0.0001)
    }

    func testPixelsPerInchIsNilWhenPhysicalSizeUnknown() {
        XCTAssertNil(ScreenRulerUnits.pixelsPerInch(pixelWidth: 2540, physicalWidthMM: 0))
        XCTAssertNil(ScreenRulerUnits.pixelsPerInch(pixelWidth: 0, physicalWidthMM: 254))
    }

    func testPhysicalLabelConvertsPixelsToEachUnit() {
        XCTAssertEqual(ScreenRulerUnits.physicalLabel(pixels: 254, unit: .inches, pixelsPerInch: 254), "1.00 in")
        XCTAssertEqual(ScreenRulerUnits.physicalLabel(pixels: 254, unit: .centimeters, pixelsPerInch: 254), "2.54 cm")
        XCTAssertEqual(ScreenRulerUnits.physicalLabel(pixels: 254, unit: .millimeters, pixelsPerInch: 254), "25.4 mm")
    }

    func testPhysicalLabelIsNilForNoUnitOrUnknownDPI() {
        XCTAssertNil(ScreenRulerUnits.physicalLabel(pixels: 254, unit: .none, pixelsPerInch: 254))
        XCTAssertNil(ScreenRulerUnits.physicalLabel(pixels: 254, unit: .inches, pixelsPerInch: nil))
    }

    // MARK: - Session mode

    func testSetModeDoesNotOverwritePersistedDefaultMode() {
        let model = ScreenRulerModel()
        self.model = model
        model.measurementMode = .spacing

        model.setMode(.bounds)

        XCTAssertEqual(model.measurementMode, .spacing)
        XCTAssertEqual(UserDefaults.standard.string(forKey: "screenRuler.measurementMode"), MeasurementMode.spacing.rawValue)
    }
}
