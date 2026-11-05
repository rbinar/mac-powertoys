import SwiftUI

extension PowerRenameModel: ModuleModel {}

enum PowerRenameModule {
    @MainActor static let module = ModuleDescriptor(
        id: "powerRename",
        title: "PowerRename", icon: "pencil.line",
        make: { PowerRenameModel() },
        status: { $0.hubStatusText },
        view: { AnyView(PowerRenameView(onBack: $0)) },
        commands: { m in [
            PaletteCommand(id: "powerRename.open", title: "PowerRename", subtitle: "Batch rename files", symbol: "pencil.line", group: .tools, keywords: ["rename", "batch", "regex", "files"])
        ] }
    ).erased()
}
