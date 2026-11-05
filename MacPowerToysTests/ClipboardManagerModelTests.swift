import XCTest
import AppKit
@testable import MacPowerToys

@MainActor
final class ClipboardManagerModelTests: XCTestCase {
    private var model: ClipboardManagerModel!

    private static let keys = ["clipboardManager.isEnabled", "clipboardManager.maxHistoryCount", "clipboardManager.items"]

    override func setUp() {
        super.setUp()
        Self.keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        model = ClipboardManagerModel()
    }

    override func tearDown() {
        model.stopMonitoring()
        model = nil
        Self.keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        super.tearDown()
    }

    private func text(_ s: String, age: TimeInterval, pinned: Bool = false) -> ClipboardItem {
        ClipboardItem(id: UUID(), type: .text, textContent: s,
                      createdAt: Date(timeIntervalSince1970: 1_000_000 - age), isPinned: pinned)
    }

    func testOrderedPutsPinnedFirstThenNewestFirst() {
        let oldPinned = text("old pinned", age: 300, pinned: true)
        let newPinned = text("new pinned", age: 200, pinned: true)
        let newest = text("newest", age: 10)
        let older = text("older", age: 100)
        let result = ClipboardManagerModel.ordered([older, oldPinned, newest, newPinned], matching: "")
        XCTAssertEqual(result.map(\.textContent), ["new pinned", "old pinned", "newest", "older"])
    }

    func testOrderedFiltersCaseInsensitivelyOnTextOnly() {
        let hello = text("Hello World", age: 10)
        let other = text("goodbye", age: 20)
        let image = ClipboardItem(id: UUID(), type: .image, imageFileName: "x.png", createdAt: Date(), isPinned: false)
        let result = ClipboardManagerModel.ordered([other, image, hello], matching: "hELLo")
        XCTAssertEqual(result.map(\.id), [hello.id])
        XCTAssertEqual(ClipboardManagerModel.ordered([other, image, hello], matching: "").count, 3)
    }

    func testCopyWritesOnlyPlainStringToPasteboard() {
        let pb = NSPasteboard(name: NSPasteboard.Name("com.rbinar.MacPowerToys.tests.\(UUID().uuidString)"))
        defer { pb.releaseGlobally() }
        model.copyItemToPasteboard(text("plain", age: 0), to: pb)
        // AppKit adds the legacy NSStringPboardType alias for .string; nothing richer may be present.
        XCTAssertEqual(Set(pb.types ?? []), [.string, NSPasteboard.PasteboardType("NSStringPboardType")])
        XCTAssertEqual(pb.string(forType: .string), "plain")
        XCTAssertNil(pb.data(forType: .rtf))
        XCTAssertNil(pb.data(forType: .html))
    }

    func testPasteKeyEventsAreCommandV() {
        let events = ClipboardManagerModel.pasteKeyEvents()
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.map(\.type), [.keyDown, .keyUp])
        for event in events {
            XCTAssertEqual(event.getIntegerValueField(.keyboardEventKeycode), 9)
            XCTAssertTrue(event.flags.contains(.maskCommand))
        }
    }
}
