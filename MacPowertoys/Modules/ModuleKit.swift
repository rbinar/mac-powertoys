import SwiftUI
import Combine

// MARK: - Module contract

/// Every feature model conforms with a one-line extension; each already has `stopMonitoring()`.
@MainActor
protocol ModuleModel: ObservableObject where ObjectWillChangePublisher == ObservableObjectPublisher {
    func stopMonitoring()
}

struct ModuleContext {
    /// Combined palette commands of all loaded modules. Only QuickLaunch subscribes.
    let paletteCommands: AnyPublisher<[PaletteCommand], Never>
}

/// Registration data of one feature module. `make` is the only place the model is created.
@MainActor
struct ModuleDescriptor<Model: ModuleModel> {
    let id: String                                                    // = UserDefaults key prefix ("screenRuler")
    let make: () -> Model
    let view: (_ onBack: @escaping () -> Void) -> AnyView             // view keeps reading its model via @EnvironmentObject
    var commands: (Model) -> [PaletteCommand] = { _ in [] }           // `screen` is filled in by the registry
    var stop: (Model) -> Void = { $0.stopMonitoring() }
    var attach: (Model, ModuleContext) -> AnyCancellable? = { _, _ in nil }
}

// MARK: - Type erasure

/// Metadata readable without creating the model.
@MainActor
struct AnyModule {
    let id: String
    let load: (ModuleContext) -> LoadedModule
}

/// The single owner of a live module's model. Releasing it releases the model (call `stop()` first).
@MainActor
final class LoadedModule {
    let id: String
    let model: AnyObject
    let commands: () -> [PaletteCommand]
    let stop: () -> Void
    /// Wraps a view so it can read this module's model through `@EnvironmentObject`.
    /// Temporary: lets the unchanged `ContentView` keep working until the hub is registry-driven.
    let inject: (AnyView) -> AnyView
    private let attachment: AnyCancellable?

    init(id: String, model: AnyObject, commands: @escaping () -> [PaletteCommand],
         stop: @escaping () -> Void, inject: @escaping (AnyView) -> AnyView, attachment: AnyCancellable?) {
        self.id = id
        self.model = model
        self.commands = commands
        self.stop = stop
        self.inject = inject
        self.attachment = attachment
    }
}

extension ModuleDescriptor {
    func erased() -> AnyModule {
        AnyModule(id: id) { ctx in
            let m = make()
            let screen: (@escaping () -> Void) -> AnyView = { back in AnyView(view(back).environmentObject(m)) }
            return LoadedModule(
                id: id, model: m,
                commands: { commands(m).map { var c = $0; c.screen = screen; return c } },
                stop: { stop(m) },
                inject: { AnyView($0.environmentObject(m)) },
                attachment: attach(m, ctx))
        }
    }
}
