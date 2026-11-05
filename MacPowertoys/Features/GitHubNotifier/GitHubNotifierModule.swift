import SwiftUI

extension GitHubNotifierModel: ModuleModel {}

enum GitHubNotifierModule {
    @MainActor static let module = ModuleDescriptor(
        id: "gitHubNotifier",
        title: "GitHub Notifier", icon: "bell.badge.circle",
        make: { GitHubNotifierModel() },
        status: { $0.hubStatusText },
        toggle: \.isEnabled,
        view: { AnyView(GitHubNotifierView(onBack: $0)) },
        commands: { m in [
            PaletteCommand(id: "gitHubNotifier.open", title: "GitHub Notifier", subtitle: "Pull requests and notifications", symbol: "bell.badge.circle", group: .tools, keywords: ["pr", "notifications"])
        ] }
    ).erased()
}
