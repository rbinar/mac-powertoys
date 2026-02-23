import SwiftUI
import AppKit

struct ColorPickerView: View {
    @EnvironmentObject var model: ColorModel
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Navigation header
            HStack {
                Button {
                    onBack()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)

                Text("Color Picker")
                    .font(.system(.headline, design: .rounded))

                Spacer()
            }

            Divider()

            HStack {
                Button {
                    model.pickFromScreen()
                } label: {
                    Label("Pick", systemImage: "eyedropper")
                }

                Spacer(minLength: 8)

                Button {
                    model.openColorPanel()
                } label: {
                    Circle()
                        .fill(Color(nsColor: model.nsColor))
                        .frame(width: 28, height: 28)
                        .overlay(Circle().stroke(.secondary, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .help("Open color picker")
            }

            Divider()

            // Swatch strip
            SwatchView(nsColor: model.nsColor)

            // Value cards
            ValueRow(title: "HEX", value: model.hexString, onCopy: { model.copy(model.hexString) })
            ValueRow(title: "RGB", value: model.rgbString, onCopy: { model.copy(model.rgbString) })
            ValueRow(title: "HSL", value: model.hslString, onCopy: { model.copy(model.hslString) })
            ValueRow(title: "HSV", value: model.hsvString, onCopy: { model.copy(model.hsvString) })

            if !model.colorHistory.isEmpty {
                ColorHistoryView()
                    .environmentObject(model)
            }
        }
    }
}

struct ValueRow: View {
    let title: String
    let value: String
    let onCopy: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(.subheadline, design: .rounded))
                .frame(width: 44, alignment: .leading)
                .foregroundStyle(.secondary)

            TextField("", text: .constant(value))
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .disabled(true)

            Button(action: onCopy) {
                Image(systemName: "doc.on.doc")
            }
            .help("Copy")
        }
    }
}

struct SwatchView: View {
    let nsColor: NSColor
    var swatchHeight: CGFloat = 38
    var swatchCornerRadius: CGFloat = 6
    var onSelect: ((NSColor) -> Void)? = nil

    var body: some View {
        let shades = ColorMath.shades(of: nsColor, count: 7)
        return HStack(spacing: 6) {
            ForEach(0..<shades.count, id: \.self) { i in
                if let onSelect {
                    Button {
                        onSelect(shades[i])
                    } label: {
                        RoundedRectangle(cornerRadius: swatchCornerRadius)
                            .fill(Color(nsColor: shades[i]))
                            .frame(height: swatchHeight)
                    }
                    .buttonStyle(.plain)
                    .help("Use shade \(ColorMath.hexString(shades[i]))")
                } else {
                    RoundedRectangle(cornerRadius: swatchCornerRadius)
                        .fill(Color(nsColor: shades[i]))
                        .frame(height: swatchHeight)
                }
            }
        }
    }
}

struct ColorHistoryView: View {
    @EnvironmentObject var model: ColorModel
    
    var body: some View {
        HStack(spacing: 4) {
            Label("History", systemImage: "clock")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
                .labelStyle(.iconOnly)
            
            ForEach(Array(model.colorHistory.enumerated()), id: \.offset) { index, color in
                Button {
                    model.selectFromHistory(color)
                } label: {
                    Circle()
                        .fill(Color(nsColor: color))
                        .frame(width: 20, height: 20)
                        .overlay(
                            Circle()
                                .stroke(.secondary.opacity(0.3), lineWidth: 0.5)
                        )
                        .overlay(
                            model.nsColor == color ?
                            Circle()
                                .stroke(.primary, lineWidth: 1.5)
                                .frame(width: 22, height: 22)
                            : nil
                        )
                }
                .buttonStyle(.plain)
                .help("Select from color history: \(ColorMath.hexString(color))")
            }
        }
    }
}
