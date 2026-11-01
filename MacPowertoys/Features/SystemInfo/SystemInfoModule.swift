import SwiftUI

extension SystemInfoModel: ModuleModel {}

enum SystemInfoModule {
    @MainActor static let module = ModuleDescriptor(
        id: "systemInfo",
        make: { SystemInfoModel() },
        view: { AnyView(SystemInfoView(onBack: $0)) },
        commands: { m in [
            PaletteCommand(id: "systemInfo.open", title: "System Info", subtitle: "CPU, memory and disk", symbol: "gauge.with.dots.needle.33percent", group: .tools)
        ] }
    ).erased()
}
