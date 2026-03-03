import SwiftUI

struct ScreenCaptureView: View {
    @EnvironmentObject var model: ScreenCaptureModel
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

                Text("Screen Capture")
                    .font(.system(.headline, design: .rounded))

                Spacer()
            }

            Divider()

            Toggle(isOn: $model.isEnabled) {
                Label("Enable Screen Capture", systemImage: "camera.viewfinder")
                    .font(.system(.body, design: .rounded))
            }
            .toggleStyle(.switch)

            if model.isEnabled {
                HStack(spacing: 4) {
                    Image(systemName: "keyboard")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text("⌃⌥4 to start selection · ESC to cancel")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.tertiary)
                }

                if model.isCapturing {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(.orange)
                            .frame(width: 6, height: 6)
                        Text("Selecting area…")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("How it works")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        Label("Press ⌃⌥4 to enter selection mode", systemImage: "1.circle.fill")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                        Label("Drag to select a region on screen", systemImage: "2.circle.fill")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                        Label("Release to copy image to clipboard", systemImage: "3.circle.fill")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.white.opacity(0.08))
                )

                Spacer()
            } else {
                Spacer()
            }
        }
    }
}
