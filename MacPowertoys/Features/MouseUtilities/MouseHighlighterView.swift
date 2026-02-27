import SwiftUI

struct MouseHighlighterView: View {
    @EnvironmentObject var model: MouseHighlighterModel
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

                Text("Mouse Highlighter")
                    .font(.system(.headline, design: .rounded))

                Spacer()
            }

            Divider()

            ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {

            Toggle(isOn: $model.isEnabled) {
                Label("Enable Mouse Highlighter", systemImage: "hand.tap")
                    .font(.system(.body, design: .rounded))
            }
            .toggleStyle(.switch)

            HStack(spacing: 4) {
                Image(systemName: "keyboard")
                    .font(.caption2)
                Text("Toggle: Double Left ⌥")
                    .font(.system(.caption, design: .rounded))
            }
            .foregroundStyle(.tertiary)

            if model.isEnabled {
                Divider()

                // Primary button color
                HStack {
                    Text("Left Click Color")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                    ColorPicker("", selection: Binding(
                        get: { Color(nsColor: model.primaryButtonColor) },
                        set: { model.primaryButtonColor = NSColor($0) }
                    ))
                    .labelsHidden()
                }

                // Secondary button color
                HStack {
                    Text("Right Click Color")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                    ColorPicker("", selection: Binding(
                        get: { Color(nsColor: model.secondaryButtonColor) },
                        set: { model.secondaryButtonColor = NSColor($0) }
                    ))
                    .labelsHidden()
                }

                // Radius
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Highlight Radius")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(model.highlightRadius))px")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    Slider(value: $model.highlightRadius, in: 10...80, step: 5)
                }

                // Fade delay
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Fade Delay")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(model.fadeDelayMs))ms")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    Slider(value: $model.fadeDelayMs, in: 50...2000, step: 50)
                }

                // Fade duration
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Fade Duration")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(model.fadeDurationMs))ms")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    Slider(value: $model.fadeDurationMs, in: 100...2000, step: 50)
                }
            }
            } // VStack inside ScrollView
            } // ScrollView
        }
    }
}
