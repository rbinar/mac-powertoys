import SwiftUI

extension CrosshairsModel: ModuleModel {}

enum CrosshairsModule {
    @MainActor static let module = ModuleDescriptor(
        id: "crosshairs",
        make: { CrosshairsModel() },
        view: { AnyView(CrosshairsView(onBack: $0)) },
        commands: { m in [
            PaletteCommand(id: "crosshairs.toggle", title: "Mouse Crosshairs", subtitle: "Crosshair overlay", symbol: "plus.circle", group: .modes, isOn: { m.isEnabled }, run: { m.isEnabled.toggle() })
        ] }
    ).erased()
}
