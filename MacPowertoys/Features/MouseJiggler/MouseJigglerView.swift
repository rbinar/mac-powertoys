import SwiftUI

struct MouseJigglerView: View {
    @EnvironmentObject var model: MouseJigglerModel
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
                .help("Back")

                Text("Mouse Jiggler")
                    .font(.system(.headline, design: .rounded))

                Spacer()
            }

            Divider()

            if !AXIsProcessTrusted() {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.shield")
                        .foregroundStyle(.orange)
                    Text("Needs Accessibility permission to move the cursor")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("Grant…") {
                        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
                        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .controlSize(.small)
                }
            }

            Toggle(isOn: $model.isEnabled) {
                Label("Enable Mouse Jiggler", systemImage: "computermouse.fill")
                    .font(.system(.body, design: .rounded))
            }
            .toggleStyle(.switch)

            if model.isEnabled {
                Divider()

                Text("Simulates tiny mouse movements to stay active in Teams, Slack, etc.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Jiggle Interval")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(model.jiggleIntervalSeconds)s")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    Slider(value: Binding(
                        get: { Double(model.jiggleIntervalSeconds) },
                        set: { model.jiggleIntervalSeconds = Int($0) }
                    ), in: 10...120, step: 5)
                    .accessibilityLabel("Jiggle Interval")
                    .accessibilityValue("\(model.jiggleIntervalSeconds) seconds")
                }
            }
            
            Spacer()
        }
    }
}
