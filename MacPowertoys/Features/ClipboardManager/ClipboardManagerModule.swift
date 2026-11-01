import SwiftUI

extension ClipboardManagerModel: ModuleModel {}

enum ClipboardManagerModule {
    @MainActor static let module = ModuleDescriptor(
        id: "clipboardManager",
        make: { ClipboardManagerModel() },
        view: { AnyView(ClipboardManagerView(onBack: $0)) },
        commands: { m in [
            PaletteCommand(id: "clipboardManager.open", title: "Clipboard Manager", subtitle: "Clipboard history", symbol: "list.clipboard", group: .tools, shortcut: "⌃⌥V", keywords: ["paste", "history"])
        ] }
    ).erased()
}
