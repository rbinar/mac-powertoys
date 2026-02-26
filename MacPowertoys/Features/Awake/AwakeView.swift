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

                        HStack(spacing: 6) {
                            ForEach(durationPresets, id: \.self) { minutes in
                                Button {
                                    model.durationMinutes = minutes
                                } label: {
                                    Text(durationLabel(minutes))
                                        .font(.system(.caption, design: .rounded))
                                        .fontWeight(model.durationMinutes == minutes ? .semibold : .regular)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(model.durationMinutes == minutes ? .white.opacity(0.15) : .white.opacity(0.05))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(model.durationMinutes == minutes ? .white.opacity(0.3) : .clear, lineWidth: 0.8)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
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
}
