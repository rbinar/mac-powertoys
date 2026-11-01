import SwiftUI

extension PortManagerModel: ModuleModel {}

enum PortManagerModule {
    @MainActor static let module = ModuleDescriptor(
        id: "portManager",
        make: { PortManagerModel() },
        view: { AnyView(PortManagerView(onBack: $0)) },
        commands: { m in [
            PaletteCommand(id: "portManager.open", title: "Port Manager", subtitle: "Listening ports and processes", symbol: "network", group: .tools)
        ] }
    ).erased()
}
