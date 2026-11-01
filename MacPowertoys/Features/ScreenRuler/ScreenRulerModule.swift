import SwiftUI

extension ScreenRulerModel: ModuleModel {}

enum ScreenRulerModule {
    @MainActor static let module = ModuleDescriptor(
        id: "screenRuler",
        make: { ScreenRulerModel() },
        view: { AnyView(ScreenRulerView(onBack: $0)) },
        commands: { m in [
            PaletteCommand(id: "screenRuler.start", title: "Screen Ruler", subtitle: "Start measuring", symbol: "ruler", group: .screenTools, shortcut: "⌃⌥R", keywords: ["measure", "pixels"], run: { m.startSession() })
        ] }
    ).erased()
}
