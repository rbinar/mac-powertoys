import SwiftUI

extension ZoomItModel: ModuleModel {}

enum ZoomItModule {
    @MainActor static let module = ModuleDescriptor(
        id: "zoomIt",
        make: { ZoomItModel() },
        view: { AnyView(ZoomItView(onBack: $0)) },
        commands: { m in [
            PaletteCommand(id: "zoomIt.screenZoom", title: "Screen Zoom", subtitle: "Freeze and magnify the screen", symbol: "plus.magnifyingglass", group: .screenTools, shortcut: "⌃⌥Z", keywords: ["zoomit", "magnify"], run: { m.activateScreenZoom() }),
            PaletteCommand(id: "zoomIt.liveZoom", title: "Live Zoom", subtitle: "Magnify in real time", symbol: "video", group: .screenTools, shortcut: "⌃⌥L", keywords: ["zoomit", "magnify"], run: { m.activateLiveZoom() })
        ] }
    ).erased()
}
