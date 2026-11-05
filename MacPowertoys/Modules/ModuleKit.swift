import SwiftUI
import Combine

// MARK: - Module contract

/// Every feature model conforms with a one-line extension; each already has `stopMonitoring()`.
@MainActor
protocol ModuleModel: ObservableObject where ObjectWillChangePublisher == ObservableObjectPublisher {
    func stopMonitoring()
}

/// A hub card that opens a sub-screen listing several modules (e.g. Mouse Utilities).
struct HubGroup: Hashable {
    let id: String
    let title: String
    let icon: String
    static let mouseUtilities = HubGroup(id: "mouseUtilities", title: "Mouse Utilities", icon: "cursorarrow")
}

enum ModuleNotifications {
    /// Posted with the module id as `object`; the hub navigates to that module's screen.
    static let show = Notification.Name("MacPowerToys.showModule")
    /// Posted with a palette command id as `object`; Quick Launch shows the panel and opens that command's screen.
    static let openPaletteScreen = Notification.Name("MacPowerToys.openPaletteScreen")
    /// Posted without an object; Quick Launch hides its panel.
    static let hidePalette = Notification.Name("MacPowerToys.hidePalette")
}

struct ModuleContext {
    /// Combined palette commands of all loaded modules. Only QuickLaunch subscribes.
    let paletteCommands: AnyPublisher<[PaletteCommand], Never>
}

/// Registration data of one feature module. `make` is the only place the model is created.
@MainActor
struct ModuleDescriptor<Model: ModuleModel> {
    let id: String                                                    // = UserDefaults key prefix ("screenRuler")
    let title: String
    let icon: String                                                  // SF Symbol
    var group: HubGroup? = nil                                        // grouped modules have no hub card of their own
    var rowSubtitle: String? = nil                                    // group screen row ("Spotlight on cursor")
    var rowShortcut: String? = nil                                    // group screen row ("Double ⌃")
    let make: () -> Model
    var status: (Model) -> String = { _ in "Ready" }                  // hub card subtitle
    var toggle: ReferenceWritableKeyPath<Model, Bool>? = nil          // card switch = the feature's own isEnabled
    var customCard: ((Model, _ open: @escaping () -> Void) -> AnyView)? = nil  // full-width card (Color Picker)
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
    let title: String
    let icon: String
    let group: HubGroup?
    let rowSubtitle: String?
    let rowShortcut: String?
    let isFullWidth: Bool
    let load: (ModuleContext) -> LoadedModule
}

/// The single owner of a live module's model. Releasing it releases the model (call `stop()` first).
@MainActor
final class LoadedModule {
    let id: String
    let model: AnyObject
    let changes: AnyPublisher<Void, Never>
    let toggle: Binding<Bool>?
    let screen: (_ onBack: @escaping () -> Void) -> AnyView
    let card: (_ open: @escaping () -> Void) -> AnyView
    let commands: () -> [PaletteCommand]
    let stop: () -> Void
    private let attachment: AnyCancellable?

    init(id: String, model: AnyObject, changes: AnyPublisher<Void, Never>, toggle: Binding<Bool>?,
         screen: @escaping (@escaping () -> Void) -> AnyView, card: @escaping (@escaping () -> Void) -> AnyView,
         commands: @escaping () -> [PaletteCommand], stop: @escaping () -> Void, attachment: AnyCancellable?) {
        self.id = id
        self.model = model
        self.changes = changes
        self.toggle = toggle
        self.screen = screen
        self.card = card
        self.commands = commands
        self.stop = stop
        self.attachment = attachment
    }
}

extension ModuleDescriptor {
    func erased() -> AnyModule {
        AnyModule(id: id, title: title, icon: icon, group: group,
                  rowSubtitle: rowSubtitle, rowShortcut: rowShortcut, isFullWidth: customCard != nil) { ctx in
            let m = make()
            let screen: (@escaping () -> Void) -> AnyView = { back in AnyView(view(back).environmentObject(m)) }
            return LoadedModule(
                id: id, model: m,
                changes: m.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
                toggle: toggle.map { kp in Binding(get: { m[keyPath: kp] }, set: { m[keyPath: kp] = $0 }) },
                screen: screen,
                card: { open in AnyView(HubCardHost(model: m, descriptor: self, open: open)) },
                commands: { commands(m).map { var c = $0; if c.screen == nil { c.screen = screen }; return c } },
                stop: { stop(m) },
                attachment: attach(m, ctx))
        }
    }
}

// MARK: - Hub layout

enum HubItem: Identifiable {
    case module(String)
    case group(HubGroup, [String])

    var id: String {
        switch self {
        case .module(let id): return id
        case .group(let group, _): return "group." + group.id
        }
    }

    /// Catalog order; a group takes the position of its first child and is absent when it has no children.
    static func layout(_ modules: [AnyModule]) -> [HubItem] {
        var items: [HubItem] = []
        var groupIndex: [String: Int] = [:]
        for module in modules {
            guard let group = module.group else { items.append(.module(module.id)); continue }
            if let index = groupIndex[group.id], case .group(let g, let ids) = items[index] {
                items[index] = .group(g, ids + [module.id])
            } else {
                groupIndex[group.id] = items.count
                items.append(.group(group, [module.id]))
            }
        }
        return items
    }
}
