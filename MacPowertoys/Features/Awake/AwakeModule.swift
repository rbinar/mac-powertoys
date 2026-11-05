import SwiftUI

extension AwakeModel: ModuleModel {}

enum AwakeModule {
    @MainActor static let module = ModuleDescriptor(
        id: "awake",
        title: "Awake", icon: "cup.and.saucer.fill",
        make: { AwakeModel() },
        status: { $0.isEnabled ? ($0.isIndefinite ? "Indefinite" : $0.formattedRemaining) : "Off" },
        toggle: \.isEnabled,
        view: { AnyView(AwakeView(onBack: $0)) },
        commands: { m in [
            PaletteCommand(id: "awake.toggle", title: "Awake", subtitle: "Keep the Mac awake", symbol: "cup.and.saucer.fill", group: .modes, keywords: ["sleep", "caffeinate"], isOn: { m.isEnabled }, run: { m.isEnabled.toggle() })
        ] }
    ).erased()
}
