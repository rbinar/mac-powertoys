import SwiftUI

struct CursorWrapView: View {
    @EnvironmentObject var model: CursorWrapModel
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FeatureHeader(title: "Cursor Wrap", onBack: onBack)

            Divider()

            HStack {
                Label("Enable Cursor Wrap", systemImage: "arrow.trianglehead.2.counterclockwise")
                    .font(.body)
                Spacer()
                Toggle("Enable Cursor Wrap", isOn: $model.isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            if model.isEnabled {
                Divider()

                Text("Cursor wraps around screen edges seamlessly")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("Horizontal Wrap")
                        .font(.subheadline)
                    Spacer()
                    Toggle("Horizontal Wrap", isOn: $model.wrapHorizontal)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }

                HStack {
                    Text("Vertical Wrap")
                        .font(.subheadline)
                    Spacer()
                    Toggle("Vertical Wrap", isOn: $model.wrapVertical)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }

                // Edge margin
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Edge Margin")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(model.edgeMargin))px")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $model.edgeMargin, in: 0...10, step: 1)
                        .accessibilityLabel("Edge Margin")
                        .accessibilityValue("\(Int(model.edgeMargin)) pixels")
                }
            }
            
            Spacer()
        }
    }
}
