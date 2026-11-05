import SwiftUI

extension MarkdownPreviewModel: ModuleModel {}

enum MarkdownPreviewModule {
    @MainActor static let module = ModuleDescriptor(
        id: "markdownPreview",
        title: "Markdown Preview", icon: "doc.richtext",
        make: { MarkdownPreviewModel() },
        status: { "\($0.recentFiles.count) recent" },
        view: { AnyView(MarkdownPreviewView(onBack: $0)) },
        commands: { m in [
            PaletteCommand(id: "markdownPreview.open", title: "Markdown Preview", subtitle: "Preview markdown files", symbol: "doc.richtext", group: .tools)
        ] }
    ).erased()
}
