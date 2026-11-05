import SwiftUI

extension AdvancedPasteModel: ModuleModel {}

enum AdvancedPasteModule {
    @MainActor static let module = ModuleDescriptor(
        id: "advancedPaste",
        title: "Advanced Paste", icon: "doc.on.clipboard",
        make: { AdvancedPasteModel() },
        status: { $0.isEnabled ? "⌃⌥⇧V ready" : "Off" },
        toggle: \.isEnabled,
        view: { AnyView(AdvancedPasteView(onBack: $0)) },
        commands: { m in [
            PaletteCommand(id: "advancedPaste.open", title: "Advanced Paste", subtitle: "Paste as plain text, Markdown, JSON…", symbol: "doc.on.clipboard", group: .tools, shortcut: "⌃⌥⇧V", keywords: ["paste", "plain text", "markdown", "json", "case"],
                           screen: { _ in AnyView(AdvancedPastePaletteView().environmentObject(m)) },
                           screenWidth: AdvancedPastePaletteView.width)
        ] }
    ).erased()
}
