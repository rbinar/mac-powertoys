import XCTest
import Combine
import SwiftUI
@testable import MacPowerToys

// Uses fake models only, so no hotkeys or monitors are registered.
@MainActor
final class ModuleRegistryTests: XCTestCase {
    private var events: [String] = []
    private var made: [String: Int] = [:]
    private var cancellables = Set<AnyCancellable>()

    override func setUp() {
        super.setUp()
        events = []
        made = [:]
    }

    @MainActor
    final class FakeModel: ModuleModel {
        let name: String
        init(_ name: String) { self.name = name }
        func stopMonitoring() {}
    }

    private func module(_ id: String, commandIDs: [String] = [], attach: ((ModuleContext) -> AnyCancellable?)? = nil) -> AnyModule {
        ModuleDescriptor(
            id: id,
            make: { [unowned self] in made[id, default: 0] += 1; return FakeModel(id) },
            view: { _ in AnyView(EmptyView()) },
            commands: { _ in commandIDs.map { PaletteCommand(id: $0, title: $0, subtitle: "", symbol: "circle", group: .tools) } },
            stop: { [unowned self] _ in events.append("stop \(id)") },
            attach: { _, ctx in attach?(ctx) }
        ).erased()
    }

    func testEachModuleIsMadeExactlyOnce() {
        _ = ModuleRegistry(catalog: [module("a"), module("b")])
        XCTAssertEqual(made, ["a": 1, "b": 1])
    }

    func testStopAllStopsEachLoadedModuleOnceInCatalogOrder() {
        let registry = ModuleRegistry(catalog: [module("a"), module("b"), module("c")])
        registry.stopAll()
        XCTAssertEqual(events, ["stop a", "stop b", "stop c"])
    }

    func testStopAllDoesNotReleaseModels() {
        let registry = ModuleRegistry(catalog: [module("a")])
        weak var model = registry.loaded.first?.model
        registry.stopAll()
        XCTAssertNotNil(model, "stopAll() must stop but not release; release happens only after stop")
    }

    func testPaletteCommandsAreCombinedInCatalogOrderWithScreenFilled() {
        let registry = ModuleRegistry(catalog: [module("a", commandIDs: ["a.1", "a.2"]), module("b"), module("c", commandIDs: ["c.1"])])
        XCTAssertEqual(registry.paletteCommands.map(\.id), ["a.1", "a.2", "c.1"])
        XCTAssertTrue(registry.paletteCommands.allSatisfy { $0.screen != nil })
    }

    func testAttachReceivesCombinedPaletteCommands() {
        let received = expectation(description: "attach gets commands")
        var got: [String] = []
        let attacher = module("q") { ctx in
            ctx.paletteCommands.sink { cmds in
                guard !cmds.isEmpty else { return }
                got = cmds.map(\.id)
                received.fulfill()
            }
        }
        let registry = ModuleRegistry(catalog: [module("a", commandIDs: ["a.1"]), attacher])
        wait(for: [received], timeout: 2)
        XCTAssertEqual(got, ["a.1"])
        withExtendedLifetime(registry) {}
    }
}
