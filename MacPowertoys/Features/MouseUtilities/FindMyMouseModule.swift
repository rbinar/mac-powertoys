import SwiftUI

extension FindMyMouseModel: ModuleModel {}

enum FindMyMouseModule {
    @MainActor static let module = ModuleDescriptor(
        id: "findMyMouse",
        title: "Find My Mouse", icon: "cursorarrow.rays",
        group: .mouseUtilities, rowSubtitle: "Spotlight on cursor", rowShortcut: "Double ⌃",
        make: { FindMyMouseModel() },
        toggle: \.isEnabled,
        view: { AnyView(FindMyMouseView(onBack: $0)) },
        commands: { m in [
            PaletteCommand(id: "findMyMouse.spotlight", title: "Find My Mouse", subtitle: "Show the cursor spotlight", symbol: "cursorarrow.rays", group: .screenTools, keywords: ["cursor", "pointer"], run: { m.activateSpotlight() })
        ] }
    ).erased()
}
