import SwiftUI

struct SystemInfoView: View {
    @EnvironmentObject var model: SystemInfoModel
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

                Text("System Info")
                    .font(.system(.headline, design: .rounded))

                Spacer()
            }

            Divider()

            // CPU
            MetricRow(
                icon: "gauge.medium",
                label: "CPU",
                fraction: model.cpuFraction,
                value: model.formattedCPU
            )

            // Memory
            MetricRow(
                icon: "memorychip",
                label: "Memory",
                fraction: model.memoryFraction,
                value: model.formattedMemory
            )

            // Disk
            MetricRow(
                icon: "internaldrive",
                label: "Disk",
                fraction: model.diskFraction,
                value: model.formattedDisk
            )

            // Network
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "arrow.up.arrow.down")
                    .frame(width: 16)

                Text("Network")
                    .font(.system(.subheadline, design: .rounded))

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("↑ \(model.formattedNetOut)")
                    Text("↓ \(model.formattedNetIn)")
                }
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            }

            Divider()

            // Refresh Interval Picker
            HStack {
                Text("Refresh Interval")
                    .font(.system(.subheadline, design: .rounded))

                Spacer()

                Picker("Refresh Interval", selection: $model.refreshInterval) {
                    Text("1s").tag(1.0)
                    Text("2s").tag(2.0)
                    Text("5s").tag(5.0)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 140)
            }

            Spacer()
        }
    }
}

private struct MetricRow: View {
    let icon: String
    let label: String
    let fraction: Double
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .frame(width: 16)

                Text(label)
                    .font(.system(.subheadline, design: .rounded))

                Spacer()

                Text(value)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: fraction)
                .tint(colorForFraction(fraction))
        }
    }

    private func colorForFraction(_ fraction: Double) -> Color {
        if fraction > 0.85 { return .red }
        if fraction >= 0.6 { return .yellow }
        return .green
    }
}
