import SwiftUI

struct CrosshairsView: View {
    @EnvironmentObject var model: CrosshairsModel
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FeatureHeader(title: "Mouse Crosshairs", onBack: onBack)

            Divider()

            ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {

            HStack {
                Label("Enable Crosshairs", systemImage: "plus.circle")
                    .font(.body)
                Spacer()
                Toggle("Enable Crosshairs", isOn: $model.isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            HStack(spacing: 4) {
                Image(systemName: "keyboard")
                    .font(.caption2)
                Text("Toggle: double-tap right ⌥ · ESC to turn off")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)

            if model.isEnabled {
                Divider()

                // Crosshair color
                HStack {
                    Text("Color")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    ColorPicker("Crosshair Color", selection: Binding(
                        get: { Color(nsColor: model.crosshairColor) },
                        set: { model.crosshairColor = NSColor($0) }
                    ))
                    .labelsHidden()
                }

                // Opacity
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Opacity")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(model.crosshairOpacity * 100))%")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $model.crosshairOpacity, in: 0.1...1.0, step: 0.05)
                        .accessibilityLabel("Opacity")
                        .accessibilityValue("\(Int(model.crosshairOpacity * 100))%")
                }

                // Center radius
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Center Radius")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(model.centerRadius))px")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $model.centerRadius, in: 5...60, step: 5)
                        .accessibilityLabel("Center Radius")
                        .accessibilityValue("\(Int(model.centerRadius)) pixels")
                }

                // Thickness
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Thickness")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(model.thickness))px")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $model.thickness, in: 1...10, step: 1)
                        .accessibilityLabel("Thickness")
                        .accessibilityValue("\(Int(model.thickness)) pixels")
                }

                // Border color
                HStack {
                    Text("Border Color")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    ColorPicker("Border Color", selection: Binding(
                        get: { Color(nsColor: model.borderColor) },
                        set: { model.borderColor = NSColor($0) }
                    ))
                    .labelsHidden()
                }

                // Border size
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Border Size")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(model.borderSize))px")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $model.borderSize, in: 0...5, step: 1)
                        .accessibilityLabel("Border Size")
                        .accessibilityValue("\(Int(model.borderSize)) pixels")
                }
            }
            } // VStack inside ScrollView
            } // ScrollView
        }
    }
}
