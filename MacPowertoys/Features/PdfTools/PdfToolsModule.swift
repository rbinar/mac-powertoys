import SwiftUI

extension PdfToolsModel: ModuleModel {}

enum PdfToolsModule {
    @MainActor static let module = ModuleDescriptor(
        id: "pdfTools",
        title: "PDF Tools", icon: "doc.badge.gearshape",
        make: { PdfToolsModel() },
        view: { AnyView(PdfToolsView(onBack: $0)) },
        commands: { m in [
            PaletteCommand(id: "pdfTools.open", title: "PDF Tools", subtitle: "Merge, split and convert PDFs", symbol: "doc.badge.gearshape", group: .tools)
        ] }
    ).erased()
}
