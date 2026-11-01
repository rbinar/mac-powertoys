import SwiftUI

extension ScreenCaptureModel: ModuleModel {}

enum ScreenCaptureModule {
    @MainActor static let module = ModuleDescriptor(
        id: "screenCapture",
        make: { ScreenCaptureModel() },
        view: { AnyView(ScreenCaptureView(onBack: $0)) },
        commands: { m in [
            PaletteCommand(id: "screenCapture.start", title: "Screen Capture", subtitle: "Select an area, copy to clipboard", symbol: "camera.viewfinder", group: .screenTools, shortcut: "⌃⌥4", keywords: ["screenshot"], run: { m.startCapture() })
        ] }
    ).erased()
}
