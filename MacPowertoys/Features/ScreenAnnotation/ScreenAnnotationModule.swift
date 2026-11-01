import SwiftUI

extension ScreenAnnotationModel: ModuleModel {}

enum ScreenAnnotationModule {
    @MainActor static let module = ModuleDescriptor(
        id: "screenAnnotation",
        make: { ScreenAnnotationModel() },
        view: { AnyView(ScreenAnnotationView(onBack: $0)) },
        commands: { m in [
            PaletteCommand(id: "screenAnnotation.start", title: "Screen Annotation", subtitle: "Draw on screen", symbol: "pencil.tip.crop.circle", group: .screenTools, shortcut: "⌃⌥D", keywords: ["draw", "markup"], run: { m.startSession() })
        ] }
    ).erased()
}
