import SwiftUI

extension MarkdownPreviewModel: ModuleModel {}

enum MarkdownPreviewModule {
    @MainActor static let module = ModuleDescriptor(
        id: "markdownPreview",
        make: { MarkdownPreviewModel() },
        view: { AnyView(MarkdownPreviewView(onBack: $0)) },
        commands: { m in [
            PaletteCommand(id: "markdownPreview.open", title: "Markdown Preview", subtitle: "Preview markdown files", symbol: "doc.richtext", group: .tools)
        ] }
    ).erased()
}
