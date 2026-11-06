import XCTest
import Combine
import SwiftUI
@testable import MacPowerToys

// Turning modules off and on at runtime. Fake models only, so no hotkeys or monitors are registered.
@MainActor
final class ModuleEnableTests: XCTestCase {
    private static let suite = "MacPowerToysTests.ModuleEnable"
    private var defaults: UserDefaults!
    private var events: [String] = []
    private var made: [String: Int] = [:]

    override func setUp() {
        super.setUp()
        UserDefaults().removePersistentDomain(forName: Self.suite)
        defaults = UserDefaults(suiteName: Self.suite)
        events = []
        made = [:]
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: Self.suite)
        defaults = nil
        super.tearDown()
    }

    @MainActor
    final class FakeModel: ModuleModel {
        let name: String
        let onDeinit: (String) -> Void
        init(_ name: String, onDeinit: @escaping (String) -> Void) { self.name = name; self.onDeinit = onDeinit }
        func stopMonitoring() {}
        deinit { onDeinit(name) }
    }

    private func module(_ id: String, group: HubGroup? = nil, commandIDs: [String] = [],
                        attach: ((ModuleContext) -> AnyCancellable?)? = nil) -> AnyModule {
        ModuleDescriptor(
            id: id, title: id, icon: "circle", group: group,
            make: { [unowned self] in
                made[id, default: 0] += 1
                return FakeModel(id) { [weak self] name in
                    MainActor.assumeIsolated { self?.events.append("deinit \(name)") }
                }
            },
            view: { _ in AnyView(EmptyView()) },
            commands: { _ in commandIDs.map { PaletteCommand(id: $0, title: $0, subtitle: "", symbol: "circle", group: .tools) } },
            stop: { [unowned self] _ in events.append("stop \(id)") },
            attach: { _, ctx in attach?(ctx) }
        ).erased()
    }

    private func registry(_ catalog: [AnyModule]) -> ModuleRegistry {
        ModuleRegistry(catalog: catalog, paletteOrder: [], defaults: defaults)
    }

    func testModulesAreOnByDefault() {
        let r = registry([module("a"), module("b")])
        XCTAssertEqual(made, ["a": 1, "b": 1])
        XCTAssertTrue(r.isEnabled("a"))
        XCTAssertTrue(r.isEnabled("b"))
    }

    func testDisabledModuleIsNeverMade() {
        defaults.set(["b"], forKey: ModuleRegistry.disabledKey)
        let r = registry([module("a"), module("b", commandIDs: ["b.1"]), module("c")])
        XCTAssertEqual(made, ["a": 1, "c": 1])
        XCTAssertFalse(r.isEnabled("b"))
        XCTAssertNil(r.module("b"))
        XCTAssertEqual(r.loaded.map(\.id), ["a", "c"])
        XCTAssertTrue(r.paletteCommands.isEmpty)
        XCTAssertEqual(r.hubItems.map(\.id), ["a", "c"])
    }

    func testUnknownDisabledIDsAreIgnored() {
        defaults.set(["removedModule"], forKey: ModuleRegistry.disabledKey)
        let r = registry([module("a")])
        XCTAssertEqual(r.loaded.map(\.id), ["a"])
    }

    func testTurningOffStopsOnceThenReleasesTheModel() {
        let r = registry([module("a"), module("b", commandIDs: ["b.1"])])
        weak var model = r.module("b")?.model
        r.setEnabled("b", false)
        XCTAssertEqual(events, ["stop b", "deinit b"], "stop must run before the model is released")
        XCTAssertNil(model)
        XCTAssertNil(r.module("b"))
        XCTAssertFalse(r.isEnabled("b"))
        XCTAssertEqual(r.hubItems.map(\.id), ["a"])
        XCTAssertTrue(r.paletteCommands.isEmpty)
    }

    func testTurningOffTwiceStopsOnce() {
        let r = registry([module("a")])
        r.setEnabled("a", false)
        r.setEnabled("a", false)
        XCTAssertEqual(events.filter { $0 == "stop a" }.count, 1)
    }

    func testChoiceIsPersistedAcrossLaunches() {
        let r = registry([module("a"), module("b")])
        r.setEnabled("b", false)
        XCTAssertEqual(defaults.stringArray(forKey: ModuleRegistry.disabledKey), ["b"])
        made = [:]
        let next = registry([module("a"), module("b")])
        XCTAssertEqual(made, ["a": 1])
        XCTAssertFalse(next.isEnabled("b"))
    }

    func testTurningBackOnMakesANewModelInCatalogPosition() {
        let r = registry([module("a", commandIDs: ["a.1"]), module("b", commandIDs: ["b.1"]), module("c", commandIDs: ["c.1"])])
        r.setEnabled("b", false)
        r.setEnabled("b", true)
        XCTAssertEqual(made["b"], 2)
        XCTAssertTrue(r.isEnabled("b"))
        XCTAssertEqual(r.loaded.map(\.id), ["a", "b", "c"])
        XCTAssertEqual(r.paletteCommands.map(\.id), ["a.1", "b.1", "c.1"])
        XCTAssertTrue(r.paletteCommands.allSatisfy { $0.screen != nil })
        XCTAssertEqual(defaults.stringArray(forKey: ModuleRegistry.disabledKey) ?? [], [])
    }

    func testTurningOnTwiceMakesOnce() {
        let r = registry([module("a")])
        r.setEnabled("a", true)
        XCTAssertEqual(made["a"], 1)
    }

    func testUnknownIDIsIgnored() {
        let r = registry([module("a")])
        r.setEnabled("nope", false)
        XCTAssertNil(defaults.stringArray(forKey: ModuleRegistry.disabledKey))
        XCTAssertEqual(r.loaded.map(\.id), ["a"])
    }

    func testStopAllSkipsTurnedOffModules() {
        let r = registry([module("a"), module("b"), module("c")])
        r.setEnabled("b", false)
        events = []
        r.stopAll()
        XCTAssertEqual(events, ["stop a", "stop c"])
    }

    func testGroupDisappearsWhenAllChildrenAreOff() {
        let g = HubGroup.mouseUtilities
        let r = registry([module("a"), module("c1", group: g), module("c2", group: g)])
        r.setEnabled("c1", false)
        XCTAssertEqual(r.hubItems.map(\.id), ["a", "group.mouseUtilities"])
        r.setEnabled("c2", false)
        XCTAssertEqual(r.hubItems.map(\.id), ["a"])
    }

    func testRegistryAnnouncesChange() {
        let r = registry([module("a")])
        var changes = 0
        let sub = r.objectWillChange.sink { changes += 1 }
        r.setEnabled("a", false)
        XCTAssertGreaterThan(changes, 0, "views reading the registry must refresh")
        withExtendedLifetime(sub) {}
    }

    func testAttachedModuleReceivesUpdatedCommands() {
        var latest: [String] = []
        var cancellable: AnyCancellable?
        let attacher = module("q") { ctx in
            let c = ctx.paletteCommands.sink { latest = $0.map(\.id) }
            cancellable = c
            return c
        }
        let r = registry([module("a", commandIDs: ["a.1"]), module("b", commandIDs: ["b.1"]), attacher])
        r.setEnabled("a", false)
        let gone = expectation(description: "a.1 removed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { gone.fulfill() }
        wait(for: [gone], timeout: 2)
        XCTAssertEqual(latest, ["b.1"])
        withExtendedLifetime(cancellable) {}
    }
}
