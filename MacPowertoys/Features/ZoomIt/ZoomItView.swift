import SwiftUI

struct ZoomItView: View {
    @EnvironmentObject var model: ZoomItModel
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

                Text("ZoomIt")
                    .font(.system(.headline, design: .rounded))

                Spacer()
            }

            Divider()

            Toggle(isOn: $model.isEnabled) {
                Label("Enable ZoomIt", systemImage: "magnifyingglass")
                    .font(.system(.body, design: .rounded))
            }
            .toggleStyle(.switch)

            if model.isEnabled {
                Toggle(isOn: $model.liveZoomEnabled) {
                    Label("Live Zoom", systemImage: "video")
                        .font(.system(.body, design: .rounded))
                }
                .toggleStyle(.switch)

                HStack {
                    Text("Toggle Zoom: ⌃⌥Z · Live Zoom: ⌃⌥L")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.tertiary)
                }

                Divider()

                // Magnification Level
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Magnification Level")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.2fx", model.magnificationLevel))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    Slider(value: $model.magnificationLevel, in: 1.25...4.0, step: 0.25)
                }

                // Animate Zoom
                Toggle(isOn: $model.animateZoom) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Animate Zoom")
                            .font(.system(.subheadline, design: .rounded))
                        Text("Smooth transition when zooming in and out")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.tertiary)
                    }
                }
                .toggleStyle(.switch)
            } else {
                Spacer()
            }
        }
    }
}
