import SwiftUI

struct CrosshairsView: View {
    @EnvironmentObject var model: CrosshairsModel
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Navigation header
            HStack {
                Button { onBack() } label: {
                    Label("Back", systemImage: "chevron.left")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)

                Text("Mouse Crosshairs")
                    .font(.system(.headline, design: .rounded))

                Spacer()
            }

            Divider()

            ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {

            Toggle(isOn: $model.isEnabled) {
                Label("Enable Crosshairs", systemImage: "plus.circle")
                    .font(.system(.body, design: .rounded))
            }
            .toggleStyle(.switch)

            HStack(spacing: 4) {
                Image(systemName: "keyboard")
                    .font(.caption2)
                Text("Toggle: Double Right ⌥")
                    .font(.system(.caption, design: .rounded))
            }
            .foregroundStyle(.tertiary)

            if model.isEnabled {
                Divider()

                // Crosshair color
                HStack {
                    Text("Color")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                    ColorPicker("", selection: Binding(
                        get: { Color(nsColor: model.crosshairColor) },
                        set: { model.crosshairColor = NSColor($0) }
                    ))
                    .labelsHidden()
                }

                // Opacity
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Opacity")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(model.crosshairOpacity * 100))%")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    Slider(value: $model.crosshairOpacity, in: 0.1...1.0, step: 0.05)
                }

                // Center radius
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Center Radius")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(model.centerRadius))px")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    Slider(value: $model.centerRadius, in: 5...60, step: 5)
                }

                // Thickness
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Thickness")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(model.thickness))px")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    Slider(value: $model.thickness, in: 1...10, step: 1)
                }

                // Border color
                HStack {
                    Text("Border Color")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                    ColorPicker("", selection: Binding(
                        get: { Color(nsColor: model.borderColor) },
                        set: { model.borderColor = NSColor($0) }
                    ))
                    .labelsHidden()
                }

                // Border size
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Border Size")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(model.borderSize))px")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    Slider(value: $model.borderSize, in: 0...5, step: 1)
                }
            }
            } // VStack inside ScrollView
            } // ScrollView
        }
    }
}
