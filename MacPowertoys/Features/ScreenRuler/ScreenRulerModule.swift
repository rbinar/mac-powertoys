import SwiftUI

extension ScreenRulerModel: ModuleModel {}

enum ScreenRulerModule {
    @MainActor static let module = ModuleDescriptor(
        id: "screenRuler",
        title: "Screen Ruler", icon: "ruler",
        make: { ScreenRulerModel() },
        status: { $0.isActive ? "Measuring" : ($0.isEnabled ? "⌃⌥R ready" : "Off") },
        toggle: \.isEnabled,
        view: { AnyView(ScreenRulerView(onBack: $0)) },
        commands: { m in [
            PaletteCommand(id: "screenRuler.start", title: "Screen Ruler", subtitle: "Start measuring", symbol: "ruler", group: .screenTools, shortcut: "⌃⌥R", keywords: ["measure", "pixels"], run: { m.startSession() })
        ] }
    ).erased()
}
