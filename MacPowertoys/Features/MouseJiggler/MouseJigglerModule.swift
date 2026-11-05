import SwiftUI

extension MouseJigglerModel: ModuleModel {}

enum MouseJigglerModule {
    @MainActor static let module = ModuleDescriptor(
        id: "mouseJiggler",
        title: "Mouse Jiggler", icon: "computermouse.fill",
        make: { MouseJigglerModel() },
        status: { $0.isEnabled ? "Running" : "Off" },
        toggle: \.isEnabled,
        view: { AnyView(MouseJigglerView(onBack: $0)) },
        commands: { m in [
            PaletteCommand(id: "mouseJiggler.toggle", title: "Mouse Jiggler", subtitle: "Stay active", symbol: "computermouse.fill", group: .modes, keywords: ["idle"], isOn: { m.isEnabled }, run: { m.isEnabled.toggle() })
        ] }
    ).erased()
}
