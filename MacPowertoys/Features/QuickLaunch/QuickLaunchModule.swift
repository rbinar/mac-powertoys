import SwiftUI
import Combine

extension QuickLaunchModel: ModuleModel {}

enum QuickLaunchModule {
    @MainActor static let module = ModuleDescriptor(
        id: "quickLaunch",
        title: "Quick Launch", icon: "bolt.fill",
        make: { QuickLaunchModel() },
        status: { "\($0.customEntries.count) shortcuts" },
        view: { AnyView(QuickLaunchView(onBack: $0)) },
        attach: { m, ctx in ctx.paletteCommands.sink { m.commands = $0 } }
    ).erased()
}
