import SwiftUI

extension ArchiveModel: ModuleModel {}

enum ArchiveModule {
    @MainActor static let module = ModuleDescriptor(
        id: "archive",
        title: "Archive", icon: "archivebox",
        make: { ArchiveModel() },
        status: { $0.hubStatusText },
        view: { AnyView(ArchiveView(onBack: $0)) },
        commands: { m in [
            PaletteCommand(id: "archive.extract", title: "Extract Archive", subtitle: "RAR, ZIP, 7z, TAR and more", symbol: "archivebox", group: .tools, keywords: ["unzip", "unrar", "7z", "rar", "decompress"],
                           screen: { AnyView(ArchiveView(onBack: $0, initialMode: .extract).environmentObject(m)) }),
            PaletteCommand(id: "archive.compress", title: "Compress Files", subtitle: "Create a ZIP or 7z", symbol: "archivebox", group: .tools, keywords: ["zip", "7z", "pack", "archive"],
                           screen: { AnyView(ArchiveView(onBack: $0, initialMode: .compress).environmentObject(m)) }),
        ] }
    ).erased()
}
