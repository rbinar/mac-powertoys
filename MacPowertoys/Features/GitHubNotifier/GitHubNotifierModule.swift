import SwiftUI

extension GitHubNotifierModel: ModuleModel {}

enum GitHubNotifierModule {
    @MainActor static let module = ModuleDescriptor(
        id: "gitHubNotifier",
        make: { GitHubNotifierModel() },
        view: { AnyView(GitHubNotifierView(onBack: $0)) },
        commands: { m in [
            PaletteCommand(id: "gitHubNotifier.open", title: "GitHub Notifier", subtitle: "Pull requests and notifications", symbol: "bell.badge.circle", group: .tools, keywords: ["pr", "notifications"])
        ] }
    ).erased()
}
