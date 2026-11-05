import SwiftUI

extension ColorModel: ModuleModel {}

enum ColorPickerModule {
    @MainActor static let module = ModuleDescriptor(
        id: "colorPicker",
        title: "Color Picker", icon: "eyedropper",
        make: { ColorModel() },
        customCard: { model, open in AnyView(
            // Color Picker module - full width (has special controls)
            FeatureCardView(title: "Color Picker", action: open) {
                Button {
                    model.pickFromScreen()
                } label: {
                    Image(systemName: "eyedropper")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(Color.primary.opacity(0.14))
                        )
                        .overlay(
                            Circle()
                                .stroke(Color.primary.opacity(0.18), lineWidth: 0.8)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Pick color from screen")
                .help("Pick from screen")

                SwatchView(
                    nsColor: model.nsColor,
                    swatchHeight: 22,
                    swatchCornerRadius: 5,
                    onSelect: { shade in
                        model.selectFromHistory(shade)
                    }
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    model.copy(model.hexString)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(Color.primary.opacity(0.14))
                        )
                        .overlay(
                            Circle()
                                .stroke(Color.primary.opacity(0.18), lineWidth: 0.8)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy \(model.hexString)")
                .help("Copy \(model.hexString)")

                Circle()
                    .fill(Color(nsColor: model.nsColor))
                    .frame(width: 22, height: 22)
                    .overlay(Circle().stroke(.secondary.opacity(0.4), lineWidth: 0.7))
                    .help(model.hexString)
            }
        ) },
        view: { AnyView(ColorPickerView(onBack: $0)) },
        commands: { m in [
            PaletteCommand(id: "colorPicker.pick", title: "Color Picker", subtitle: "Pick a color from the screen", symbol: "eyedropper", group: .screenTools, shortcut: "⌃⌥C", keywords: ["eyedropper", "hex"], run: { m.pickFromScreen() })
        ] },
        stop: { $0.closeColorPanel(); $0.stopMonitoring() }
    ).erased()
}
