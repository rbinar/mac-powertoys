import SwiftUI

struct AwakeView: View {
    @EnvironmentObject var model: AwakeModel
    let onBack: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let durationPresets = [15, 30, 60, 120, 240]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FeatureHeader(title: "Awake", onBack: onBack)

            Divider()

            HStack {
                Label("Keep Awake", systemImage: "cup.and.saucer.fill")
                    .font(.body)
                Spacer()
                Toggle("Keep Awake", isOn: $model.isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            if model.isEnabled {
                Divider()

                // Status indicator
                HStack(spacing: 8) {
                    Image(systemName: "cup.and.saucer.fill")
                        .foregroundStyle(.green)
                        .symbolEffect(.pulse, isActive: !reduceMotion)

                    if model.isIndefinite {
                        Text("Keeping Mac awake indefinitely")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Remaining: \(model.formattedRemaining)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                // Keep Display On toggle
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Keep Display On")
                            .font(.subheadline)
                        Text(model.keepDisplayOn ? "Screen and system stay awake" : "Only system stays awake")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("Keep Display On", isOn: $model.keepDisplayOn)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }

                Divider()

                // Mode selection
                HStack {
                    Text("Indefinite")
                        .font(.subheadline)
                    Spacer()
                    Toggle("Indefinite", isOn: $model.isIndefinite)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }

                if !model.isIndefinite {
                    // Duration presets
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Duration")
                            .font(.subheadline)
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
