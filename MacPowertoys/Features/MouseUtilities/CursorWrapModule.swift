import SwiftUI

extension CursorWrapModel: ModuleModel {}

enum CursorWrapModule {
    @MainActor static let module = ModuleDescriptor(
        id: "cursorWrap",
        title: "Cursor Wrap", icon: "arrow.trianglehead.2.counterclockwise",
        group: .mouseUtilities, rowSubtitle: "Wrap at edges", rowShortcut: nil,
        make: { CursorWrapModel() },
        toggle: \.isEnabled,
        view: { AnyView(CursorWrapView(onBack: $0)) },
        commands: { m in [
            PaletteCommand(id: "cursorWrap.toggle", title: "Cursor Wrap", subtitle: "Wrap at screen edges", symbol: "arrow.trianglehead.2.counterclockwise", group: .modes, isOn: { m.isEnabled }, run: { m.isEnabled.toggle() })
        ] }
    ).erased()
}
