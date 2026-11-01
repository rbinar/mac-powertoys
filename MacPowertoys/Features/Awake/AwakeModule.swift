import SwiftUI

extension AwakeModel: ModuleModel {}

enum AwakeModule {
    @MainActor static let module = ModuleDescriptor(
        id: "awake",
        make: { AwakeModel() },
        view: { AnyView(AwakeView(onBack: $0)) },
        commands: { m in [
            PaletteCommand(id: "awake.toggle", title: "Awake", subtitle: "Keep the Mac awake", symbol: "cup.and.saucer.fill", group: .modes, keywords: ["sleep", "caffeinate"], isOn: { m.isEnabled }, run: { m.isEnabled.toggle() })
        ] }
    ).erased()
}
