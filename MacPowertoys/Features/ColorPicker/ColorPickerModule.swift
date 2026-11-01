import SwiftUI

extension ColorModel: ModuleModel {}

enum ColorPickerModule {
    @MainActor static let module = ModuleDescriptor(
        id: "colorPicker",
        make: { ColorModel() },
        view: { AnyView(ColorPickerView(onBack: $0)) },
        commands: { m in [
            PaletteCommand(id: "colorPicker.pick", title: "Color Picker", subtitle: "Pick a color from the screen", symbol: "eyedropper", group: .screenTools, shortcut: "⌃⌥C", keywords: ["eyedropper", "hex"], run: { m.pickFromScreen() })
        ] },
        stop: { $0.closeColorPanel(); $0.stopMonitoring() }
    ).erased()
}
