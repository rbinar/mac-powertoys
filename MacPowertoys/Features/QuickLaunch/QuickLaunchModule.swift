import SwiftUI
import Combine

extension QuickLaunchModel: ModuleModel {}

enum QuickLaunchModule {
    @MainActor static let module = ModuleDescriptor(
        id: "quickLaunch",
        make: { QuickLaunchModel() },
        view: { AnyView(QuickLaunchView(onBack: $0)) },
        attach: { m, ctx in ctx.paletteCommands.sink { m.commands = $0 } }
    ).erased()
}
