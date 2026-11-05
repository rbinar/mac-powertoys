import SwiftUI

struct TextExtractorView: View {
    @EnvironmentObject var model: TextExtractorModel
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FeatureHeader(title: "Text Extractor", onBack: onBack) {
                Toggle("Enable Text Extractor", isOn: $model.isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text(model.isEnabled ? "Press ⌃⌥T, then drag over the text to copy" : "Enable to use ⌃⌥T")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Esc cancels the selection")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Button {
                model.startSession()
            } label: {
                Label("Extract Text", systemImage: "text.viewfinder")
            }
            .disabled(model.isActive)

            if let message = model.permissionMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack {
                SectionHeader("Last result")
                Spacer()
                Button("Copy") { model.copyLastText() }
                    .controlSize(.small)
                    .disabled(model.lastText.isEmpty)
            }

            ScrollView {
                Text(model.lastText.isEmpty ? "Nothing extracted yet" : model.lastText)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(model.lastText.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(maxHeight: 220)
            .cardBackground()

            Spacer(minLength: 0)
        }
    }
}
