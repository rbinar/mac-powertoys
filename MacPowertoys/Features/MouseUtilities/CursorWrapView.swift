import SwiftUI

struct CursorWrapView: View {
    @EnvironmentObject var model: CursorWrapModel
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

                Text("Cursor Wrap")
                    .font(.system(.headline, design: .rounded))

                Spacer()
            }

            Divider()

            Toggle(isOn: $model.isEnabled) {
                Label("Enable Cursor Wrap", systemImage: "arrow.trianglehead.2.counterclockwise")
                    .font(.system(.body, design: .rounded))
            }
            .toggleStyle(.switch)

            if model.isEnabled {
                Divider()

                Text("Cursor wraps around screen edges seamlessly")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)

                Toggle(isOn: $model.wrapHorizontal) {
                    Text("Horizontal Wrap")
                        .font(.system(.subheadline, design: .rounded))
                }
                .toggleStyle(.switch)

                Toggle(isOn: $model.wrapVertical) {
                    Text("Vertical Wrap")
                        .font(.system(.subheadline, design: .rounded))
                }
                .toggleStyle(.switch)

                // Edge margin
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Edge Margin")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(model.edgeMargin))px")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    Slider(value: $model.edgeMargin, in: 0...10, step: 1)
                }
            }
        }
    }
}
