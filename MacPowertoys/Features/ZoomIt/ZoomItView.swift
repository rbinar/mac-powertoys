import SwiftUI

struct ZoomItView: View {
    @EnvironmentObject var model: ZoomItModel
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Navigation header
            FeatureHeader(title: "ZoomIt", onBack: onBack)

            Divider()

            Toggle(isOn: $model.isEnabled) {
                Label("Enable ZoomIt", systemImage: "magnifyingglass")
                    .font(.body)
            }
            .toggleStyle(.switch)

            Text(model.isEnabled ? "Screen Zoom: ⌃⌥Z · Live Zoom: ⌃⌥L · ESC to exit" : "Enable to use ⌃⌥Z (Screen Zoom) and ⌃⌥L (Live Zoom)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Screen Zoom freezes the screen; Live Zoom follows it in real time.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            // Magnification Level
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Magnification Level")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.2fx", model.magnificationLevel))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Slider(value: $model.magnificationLevel, in: 1.25...4.0, step: 0.25)
                .accessibilityLabel("Magnification Level")
                .accessibilityValue(String(format: "%.2fx", model.magnificationLevel))
            }

            // Animate Zoom
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Animate Zoom")
                        .font(.subheadline)
                    Text("Smooth transition when zooming in and out")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Animate Zoom", isOn: $model.animateZoom)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            Spacer()
        }
    }
}
