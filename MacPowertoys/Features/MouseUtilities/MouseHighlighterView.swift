import SwiftUI

struct MouseHighlighterView: View {
    @EnvironmentObject var model: MouseHighlighterModel
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FeatureHeader(title: "Mouse Highlighter", onBack: onBack)

            Divider()

            ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {

            HStack {
                Label("Enable Mouse Highlighter", systemImage: "hand.tap")
                    .font(.body)
                Spacer()
                Toggle("Enable Mouse Highlighter", isOn: $model.isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            HStack(spacing: 4) {
                Image(systemName: "keyboard")
                    .font(.caption2)
                Text("Toggle: Double Left ⌥")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)

            if model.isEnabled {
                Divider()

                // Primary button color
                HStack {
                    Text("Left Click Color")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    ColorPicker("Left Click Color", selection: Binding(
                        get: { Color(nsColor: model.primaryButtonColor) },
                        set: { model.primaryButtonColor = NSColor($0) }
                    ))
                    .labelsHidden()
                }

                // Secondary button color
                HStack {
                    Text("Right Click Color")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    ColorPicker("Right Click Color", selection: Binding(
                        get: { Color(nsColor: model.secondaryButtonColor) },
                        set: { model.secondaryButtonColor = NSColor($0) }
                    ))
                    .labelsHidden()
                }

                // Radius
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Highlight Radius")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(model.highlightRadius))px")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $model.highlightRadius, in: 10...80, step: 5)
                        .accessibilityLabel("Highlight Radius")
                        .accessibilityValue("\(Int(model.highlightRadius)) pixels")
                }

                // Fade delay
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Fade Delay")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(model.fadeDelayMs))ms")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $model.fadeDelayMs, in: 50...2000, step: 50)
                        .accessibilityLabel("Fade Delay")
                        .accessibilityValue("\(Int(model.fadeDelayMs)) milliseconds")
                }

                // Fade duration
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Fade Duration")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(model.fadeDurationMs))ms")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $model.fadeDurationMs, in: 100...2000, step: 50)
                        .accessibilityLabel("Fade Duration")
                        .accessibilityValue("\(Int(model.fadeDurationMs)) milliseconds")
                }
            }
            } // VStack inside ScrollView
            } // ScrollView
        }
    }
}
