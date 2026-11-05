import SwiftUI

extension CrosshairsModel: ModuleModel {}

enum CrosshairsModule {
    @MainActor static let module = ModuleDescriptor(
        id: "crosshairs",
        title: "Mouse Crosshairs", icon: "plus.circle",
        group: .mouseUtilities, rowSubtitle: "Crosshair overlay", rowShortcut: "Double Right ⌥",
        make: { CrosshairsModel() },
        toggle: \.isEnabled,
        view: { AnyView(CrosshairsView(onBack: $0)) },
        commands: { m in [
            PaletteCommand(id: "crosshairs.toggle", title: "Mouse Crosshairs", subtitle: "Crosshair overlay", symbol: "plus.circle", group: .modes, isOn: { m.isEnabled }, run: { m.isEnabled.toggle() })
        ] }
    ).erased()
}
