import SwiftUI

extension DownloadManagerModel: ModuleModel {}

enum DownloadManagerModule {
    @MainActor static let module = ModuleDescriptor(
        id: "downloadManager",
        title: "Download Manager", icon: "arrow.down.circle",
        make: { DownloadManagerModel() },
        status: { $0.hubStatusText },
        view: { AnyView(DownloadManagerView(onBack: $0)) },
        commands: { _ in [
            PaletteCommand(id: "downloadManager.open", title: "Download URL", subtitle: "Download a link with parallel connections", symbol: "arrow.down.circle", group: .tools, keywords: ["download", "url", "link", "yt-dlp", "video"])
        ] }
    ).erased()
}
