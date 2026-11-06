import SwiftUI
import Combine

/// Owns every enabled module's model. Models are created in catalog order and live until turned off or the app quits.
/// Invariant: `stop()` is always called before a model is released (Carbon handlers hold `passUnretained(self)`).
@MainActor
final class ModuleRegistry: ObservableObject {
    /// `[String]` of turned-off module ids. Modules are on by default; unknown ids are ignored.
    static let disabledKey = "modules.disabled"

    let catalog: [AnyModule]
    private(set) var loaded: [LoadedModule] = []
    private(set) var paletteCommands: [PaletteCommand] = []
    private let commandSubject = CurrentValueSubject<[PaletteCommand], Never>([])
    private let paletteRank: [String: Int]
    private let defaults: UserDefaults
    private let context: ModuleContext
    private var disabled: Set<String>

    /// `paletteOrder` lists module ids in palette order; modules not in it follow in catalog order.
    init(catalog: [AnyModule], paletteOrder: [String] = ModuleCatalog.paletteOrder, defaults: UserDefaults = .standard) {
        precondition(Set(catalog.map(\.id)).count == catalog.count, "Duplicate module id")
        self.catalog = catalog
        self.defaults = defaults
        paletteRank = Dictionary(uniqueKeysWithValues: paletteOrder.enumerated().map { ($1, $0) })
        let ids = Set(catalog.map(\.id))
        disabled = Set(defaults.stringArray(forKey: Self.disabledKey) ?? []).intersection(ids)
        // Delivered on the next main-queue turn so QuickLaunch is not mutated during a view update.
        context = ModuleContext(
            paletteCommands: commandSubject.receive(on: DispatchQueue.main).eraseToAnyPublisher())
        loaded = catalog.filter { !disabled.contains($0.id) }.map { $0.load(context) }
        rebuildPaletteCommands()
    }

    func isEnabled(_ id: String) -> Bool { catalog.contains { $0.id == id } && !disabled.contains(id) }

    func setEnabled(_ id: String, _ on: Bool) {
        guard let meta = meta(id), on != isEnabled(id) else { return }
        objectWillChange.send()
        if on { disabled.remove(id) } else { disabled.insert(id) }
        defaults.set(catalog.map(\.id).filter { disabled.contains($0) }, forKey: Self.disabledKey)
        if on {
            NSLog("[Modules] load %@", id)
            loaded = catalog.compactMap { entry in
                loaded.first { $0.id == entry.id } ?? (entry.id == meta.id ? meta.load(context) : nil)
            }
            rebuildPaletteCommands()
        } else {
            NSLog("[Modules] unload %@", id)
            guard let index = loaded.firstIndex(where: { $0.id == id }) else { return }
            let removed = loaded.remove(at: index)
            rebuildPaletteCommands()
            removed.stop() // must run before `removed` is released
        }
    }

    private func rebuildPaletteCommands() {
        paletteCommands = loaded.enumerated()
            .sorted { (paletteRank[$0.element.id] ?? Int.max, $0.offset) < (paletteRank[$1.element.id] ?? Int.max, $1.offset) }
            .flatMap { $0.element.commands() }
        commandSubject.send(paletteCommands)
    }

    /// Stops every loaded module once, in catalog order. Does not release them.
    func stopAll() {
        for module in loaded { module.stop() }
    }

    func module(_ id: String) -> LoadedModule? { loaded.first { $0.id == id } }
    func meta(_ id: String) -> AnyModule? { catalog.first { $0.id == id } }

    /// Hub cards in catalog order, grouped modules collapsed into one group item.
    var hubItems: [HubItem] {
        HubItem.layout(catalog.filter { meta in loaded.contains { $0.id == meta.id } })
    }
}
