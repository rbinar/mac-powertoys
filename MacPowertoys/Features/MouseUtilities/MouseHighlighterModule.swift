import SwiftUI

extension MouseHighlighterModel: ModuleModel {}

enum MouseHighlighterModule {
    @MainActor static let module = ModuleDescriptor(
        id: "mouseHighlighter",
        make: { MouseHighlighterModel() },
        view: { AnyView(MouseHighlighterView(onBack: $0)) },
        commands: { m in [
            PaletteCommand(id: "mouseHighlighter.toggle", title: "Mouse Highlighter", subtitle: "Highlight clicks", symbol: "hand.tap", group: .modes, isOn: { m.isEnabled }, run: { m.isEnabled.toggle() })
        ] }
    ).erased()
}
