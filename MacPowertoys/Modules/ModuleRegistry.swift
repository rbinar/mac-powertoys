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

    init(catalog: [AnyModule]) {
        precondition(Set(catalog.map(\.id)).count == catalog.count, "Duplicate module id")
        self.catalog = catalog
        // Delivered on the next main-queue turn so QuickLaunch is not mutated during a view update.
        let context = ModuleContext(
            paletteCommands: commandSubject.receive(on: DispatchQueue.main).eraseToAnyPublisher())
        loaded = catalog.map { $0.load(context) }
        paletteCommands = loaded.flatMap { $0.commands() }
        commandSubject.send(paletteCommands)
    }

    /// Stops every loaded module once, in catalog order. Does not release them.
    func stopAll() {
        for module in loaded { module.stop() }
    }

    /// Makes every module's model available to `view` and its descendants via `@EnvironmentObject`.
    func inject(into view: AnyView) -> AnyView {
        loaded.reduce(view) { $1.inject($0) }
    }
}
