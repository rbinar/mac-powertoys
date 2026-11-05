import SwiftUI

extension TextExtractorModel: ModuleModel {}

enum TextExtractorModule {
    @MainActor static let module = ModuleDescriptor(
        id: "textExtractor",
        title: "Text Extractor", icon: "text.viewfinder",
        make: { TextExtractorModel() },
        status: { $0.isActive ? "Selecting" : ($0.isEnabled ? "⌃⌥T ready" : "Off") },
        toggle: \.isEnabled,
        view: { AnyView(TextExtractorView(onBack: $0)) },
        commands: { m in [
            PaletteCommand(id: "textExtractor.start", title: "Text Extractor", subtitle: "Copy text from the screen", symbol: "text.viewfinder", group: .screenTools, shortcut: "⌃⌥T", keywords: ["ocr", "copy text", "read"], run: { m.startSession() })
        ] }
    ).erased()
}
