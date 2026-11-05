import SwiftUI

extension FileLocksmithModel: ModuleModel {}

enum FileLocksmithModule {
    @MainActor static let module = ModuleDescriptor(
        id: "fileLocksmith",
        title: "File Locksmith", icon: "lock.doc",
        make: { FileLocksmithModel() },
        status: { $0.hubStatusText },
        view: { AnyView(FileLocksmithView(onBack: $0)) },
        commands: { m in [
            PaletteCommand(id: "fileLocksmith.open", title: "File Locksmith", subtitle: "See which apps use a file", symbol: "lock.doc", group: .tools, keywords: ["lsof", "in use", "locked", "unlock"])
        ] }
    ).erased()
}
