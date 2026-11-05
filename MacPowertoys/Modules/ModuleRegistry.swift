import SwiftUI
import Combine

/// Owns every module's model. Models are created in `init`, in catalog order, and live until the app quits.
/// Invariant: `stop()` is always called before a model is released (Carbon handlers hold `passUnretained(self)`).
@MainActor
final class ModuleRegistry: ObservableObject {
    let catalog: [AnyModule]
    private(set) var loaded: [LoadedModule] = []
    private(set) var paletteCommands: [PaletteCommand] = []
    private let commandSubject = CurrentValueSubject<[PaletteCommand], Never>([])

    /// `paletteOrder` lists module ids in palette order; modules not in it follow in catalog order.
    init(catalog: [AnyModule], paletteOrder: [String] = ModuleCatalog.paletteOrder) {
        precondition(Set(catalog.map(\.id)).count == catalog.count, "Duplicate module id")
        self.catalog = catalog
        // Delivered on the next main-queue turn so QuickLaunch is not mutated during a view update.
        let context = ModuleContext(
            paletteCommands: commandSubject.receive(on: DispatchQueue.main).eraseToAnyPublisher())
        loaded = catalog.map { $0.load(context) }
        let rank = Dictionary(uniqueKeysWithValues: paletteOrder.enumerated().map { ($1, $0) })
        paletteCommands = loaded.enumerated()
            .sorted { (rank[$0.element.id] ?? Int.max, $0.offset) < (rank[$1.element.id] ?? Int.max, $1.offset) }
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
