import XCTest
import SwiftUI
@testable import MacPowerToys

// Window behaviour (panel show/hide, resizing, key handling) is intentionally not tested here.
@MainActor
final class QuickLaunchModelTests: XCTestCase {
    private var model: QuickLaunchModel!
    private var modeState = false
    private var toggleCount = 0

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "quickLaunch.recentCommands")
        modeState = false
        toggleCount = 0
        model = QuickLaunchModel()
        model.indexedApps = []
        model.customEntries = [Self.makeEntry(name: "Zoom Meeting")]
        model.commands = makeCommands()
    }

    override func tearDown() {
        model.stopMonitoring()
        model = nil
        UserDefaults.standard.removeObject(forKey: "quickLaunch.recentCommands")
        super.tearDown()
    }

    private static func makeEntry(name: String) -> LaunchEntry {
        LaunchEntry(
            id: UUID(), name: name, subtitle: "https://example.com",
            action: .url(urlString: "https://example.com"), keywords: [],
            isCustom: true, createdAt: Date(), lastUsedAt: nil, useCount: 0
        )
    }

    private func makeCommands() -> [PaletteCommand] {
        [
            PaletteCommand(id: "t.ruler", title: "Screen Ruler", subtitle: "Start measuring", symbol: "ruler", group: .screenTools),
            PaletteCommand(id: "t.zoom", title: "Screen Zoom", subtitle: "Freeze and magnify the screen", symbol: "plus.magnifyingglass", group: .screenTools),
            PaletteCommand(id: "t.live", title: "Live Zoom", subtitle: "Magnify in real time", symbol: "video", group: .screenTools),
            PaletteCommand(
                id: "t.awake", title: "Awake", subtitle: "Keep the Mac awake", symbol: "cup.and.saucer.fill", group: .modes,
                isOn: { [unowned self] in self.modeState },
                run: { [unowned self] in self.modeState.toggle(); self.toggleCount += 1 }
            ),
            PaletteCommand(id: "t.ports", title: "Port Manager", subtitle: "Listening ports", symbol: "network", group: .tools),
        ]
    }

    private func sectionTitles() -> [String?] { model.sections.map(\.title) }

    private func commandIDs(in section: PaletteSection) -> [String] {
        section.items.compactMap { item in
            if case .command(let command, _) = item { return command.id }
            return nil
        }
    }

    func testEmptySearchListsRecentFirstThenGroupsInOrder() {
        model.runCommand(model.commands.first { $0.id == "t.ruler" }!)
        model.searchText = ""

        XCTAssertEqual(sectionTitles(), ["Recent", "Screen Tools", "Modes", "Tools", "My Shortcuts"])
        XCTAssertEqual(commandIDs(in: model.sections[0]), ["t.ruler"])
    }

    func testActiveModesAreListedAboveRecent() {
        model.runCommand(model.commands.first { $0.id == "t.awake" }!) // turns the mode on
        model.searchText = ""

        XCTAssertEqual(sectionTitles(), ["Active", "Recent", "Screen Tools", "Modes", "Tools", "My Shortcuts"])
        XCTAssertEqual(commandIDs(in: model.sections[0]), ["t.awake"])

        model.runCommand(model.commands.first { $0.id == "t.awake" }!) // turns it off again
        XCTAssertEqual(sectionTitles().first, "Recent")
    }

    func testEmptySearchWithoutRecentsStartsWithScreenTools() {
        model.searchText = ""

        XCTAssertEqual(sectionTitles(), ["Screen Tools", "Modes", "Tools", "My Shortcuts"])
    }

    func testSearchRanksZoomCommandsBeforeCustomEntries() {
        model.searchText = "zoom"

        let items = model.flatItems
        XCTAssertEqual(Set(commandIDs(in: model.sections[0])), ["t.zoom", "t.live"])
        XCTAssertEqual(items.count, 3)
        guard case .entry(let entry) = items[2] else { return XCTFail("custom entry should come after commands") }
        XCTAssertEqual(entry.name, "Zoom Meeting")
    }

    func testRunningModeKeepsPanelVisibleAndRecordsRecent() {
        model.isPanelVisible = true
        let awake = model.commands.first { $0.id == "t.awake" }!

        model.runCommand(awake)

        XCTAssertTrue(model.isPanelVisible)
        XCTAssertEqual(toggleCount, 1)
        XCTAssertTrue(awake.isOn?() ?? false)
        XCTAssertEqual(model.recentCommandIDs, ["t.awake"])
        XCTAssertEqual(UserDefaults.standard.stringArray(forKey: "quickLaunch.recentCommands"), ["t.awake"])
    }

    func testRecentsAreCappedAtFiveMostRecentFirst() {
        let ids = (0..<7).map { "r.\($0)" }
        model.commands = ids.map {
            PaletteCommand(id: $0, title: $0, subtitle: "", symbol: "circle", group: .modes, run: {})
        }

        for command in model.commands { model.runCommand(command) }

        XCTAssertEqual(model.recentCommandIDs, ["r.6", "r.5", "r.4", "r.3", "r.2"])
    }

    func testOpenScreenClosesWhenItsCommandIsRemoved() {
        var ports = model.commands.first { $0.id == "t.ports" }!
        ports.screen = { _ in AnyView(EmptyView()) }
        model.openScreen(of: ports)
        XCTAssertEqual(model.activeScreen?.id, "t.ports")

        model.commands = model.commands.filter { $0.id != "t.zoom" }
        XCTAssertEqual(model.activeScreen?.id, "t.ports", "an unrelated removal keeps the screen")

        model.commands = model.commands.filter { $0.id != "t.ports" }
        XCTAssertNil(model.activeScreen)
    }
}
