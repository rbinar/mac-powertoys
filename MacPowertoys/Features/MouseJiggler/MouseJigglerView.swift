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

                Text("Mouse Jiggler")
                    .font(.system(.headline, design: .rounded))

                Spacer()
            }

            Divider()

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
                }
            }
            
            Spacer()
        }
    }
}
