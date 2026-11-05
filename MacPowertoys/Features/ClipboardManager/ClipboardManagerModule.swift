import SwiftUI

extension ClipboardManagerModel: ModuleModel {}

enum ClipboardManagerModule {
    @MainActor static let module = ModuleDescriptor(
        id: "clipboardManager",
        title: "Clipboard Manager", icon: "list.clipboard",
        make: { ClipboardManagerModel() },
        status: { $0.isEnabled ? "\($0.clipboardItems.count) items" : "Off" },
        toggle: \.isEnabled,
        view: { AnyView(ClipboardManagerView(onBack: $0)) },
        commands: { m in [
            PaletteCommand(id: "clipboardManager.open", title: "Clipboard Manager", subtitle: "Clipboard history", symbol: "list.clipboard", group: .tools, shortcut: "⌃⌥V", keywords: ["paste", "history"])
        ] }
    ).erased()
}
