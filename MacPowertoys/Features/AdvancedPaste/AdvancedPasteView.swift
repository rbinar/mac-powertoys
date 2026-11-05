import SwiftUI

struct AdvancedPasteView: View {
    @EnvironmentObject var model: AdvancedPasteModel
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FeatureHeader(title: "Advanced Paste", onBack: onBack) {
                Toggle("Enable Advanced Paste", isOn: $model.isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text(model.isEnabled ? "Press ⌃⌥⇧V to paste the clipboard transformed" : "Enable to use ⌃⌥⇧V")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Plain text, Markdown, JSON and case changes, all on this Mac")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }
}
