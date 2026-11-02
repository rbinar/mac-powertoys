import SwiftUI

struct ScreenCaptureView: View {
    @EnvironmentObject var model: ScreenCaptureModel
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Navigation header
            FeatureHeader(title: "Screen Capture", onBack: onBack)

            Divider()

            Toggle(isOn: $model.isEnabled) {
                Label("Enable Screen Capture", systemImage: "camera.viewfinder")
                    .font(.body)
            }
            .toggleStyle(.switch)

            if model.isEnabled {
                HStack(spacing: 4) {
                    Image(systemName: "keyboard")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("⌃⌥4 to start selection · ESC to cancel")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if model.isCapturing {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(.orange)
                            .frame(width: 6, height: 6)
                        Text("Selecting area…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                    SectionHeader("How it works")

                    VStack(alignment: .leading, spacing: 4) {
                        Label("Press ⌃⌥4 to enter selection mode", systemImage: "1.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Label("Drag to select a region on screen", systemImage: "2.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Label("Release to copy image to clipboard", systemImage: "3.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .cardBackground()

            Spacer()
        }
    }
}
