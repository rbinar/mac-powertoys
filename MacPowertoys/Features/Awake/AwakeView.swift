import SwiftUI

struct AwakeView: View {
    @EnvironmentObject var model: AwakeModel
    let onBack: () -> Void

    private let durationPresets = [15, 30, 60, 120, 240]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Navigation header
            HStack {
                Button { onBack() } label: {
                    Label("Back", systemImage: "chevron.left")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)

                Text("Awake")
                    .font(.system(.headline, design: .rounded))

                Spacer()
            }

            Divider()

            Toggle(isOn: $model.isEnabled) {
                Label("Keep Awake", systemImage: "cup.and.saucer.fill")
                    .font(.system(.body, design: .rounded))
            }
            .toggleStyle(.switch)

            if model.isEnabled {
                Divider()

                // Status indicator
                HStack(spacing: 8) {
                    Image(systemName: "cup.and.saucer.fill")
                        .foregroundStyle(.green)
                        .symbolEffect(.pulse, isActive: true)

                    if model.isIndefinite {
                        Text("Keeping Mac awake indefinitely")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Remaining: \(model.formattedRemaining)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                // Keep Display On toggle
                Toggle(isOn: $model.keepDisplayOn) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Keep Display On")
                            .font(.system(.subheadline, design: .rounded))
                        Text(model.keepDisplayOn ? "Screen and system stay awake" : "Only system stays awake")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.tertiary)
                    }
                }
                .toggleStyle(.switch)

                Divider()

                // Mode selection
                Toggle(isOn: $model.isIndefinite) {
                    Text("Indefinite")
                        .font(.system(.subheadline, design: .rounded))
                }
                .toggleStyle(.switch)

                if !model.isIndefinite {
                    // Duration presets
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Duration")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.secondary)

                        Picker("Duration", selection: $model.durationMinutes) {
                            ForEach(durationPresets, id: \.self) { minutes in
                                Text(durationLabel(minutes))
                                    .accessibilityLabel(durationAccessibilityLabel(minutes))
                                    .tag(minutes)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                }
            }
            
            Spacer()
        }
    }

    private func durationLabel(_ minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes)m"
        } else {
            let hours = minutes / 60
            return "\(hours)h"
        }
    }

    private func durationAccessibilityLabel(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) minutes" }
        let hours = minutes / 60
        return hours == 1 ? "1 hour" : "\(hours) hours"
    }
}
