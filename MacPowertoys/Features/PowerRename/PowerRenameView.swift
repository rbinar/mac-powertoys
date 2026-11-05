import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct PowerRenameView: View {
    @EnvironmentObject var model: PowerRenameModel
    let onBack: () -> Void

    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FeatureHeader(title: "PowerRename", onBack: onBack)
            Divider()
            dropZone
            TextField("Search", text: $model.search).textFieldStyle(.roundedBorder)
            TextField("Replace", text: $model.replace).textFieldStyle(.roundedBorder)
            VStack(alignment: .leading, spacing: 2) {
                Toggle("Regex", isOn: $model.useRegex)
                Toggle("Case Sensitive", isOn: $model.caseSensitive)
                Toggle("Numbering ({n})", isOn: $model.numbering)
                Toggle("Include extension", isOn: $model.includeExtension)
            }
            .controlSize(.small)
            if let error = model.plan.regexError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            preview
            HStack {
                Button("Apply") { model.applyRename() }.disabled(!model.plan.canApply)
                Button("Undo") { model.undo() }.disabled(model.lastBatch.isEmpty)
                Button("Clear") { model.clear() }.disabled(model.files.isEmpty)
            }
            .controlSize(.small)
            if let message = model.message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding()
    }

    private var dropZone: some View {
        VStack(spacing: 6) {
            Text("Drop files or folders").font(.system(.subheadline, design: .rounded))
            Button("Choose…") { choose() }.controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                              style: StrokeStyle(lineWidth: 1.5, dash: [5]))
        )
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in model.addFiles([url]) }
                }
            }
            return true
        }
    }

    @ViewBuilder
    private var preview: some View {
        if !model.plan.rows.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(model.plan.rows) { row in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.oldName).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            switch row.status {
                            case .unchanged:
                                Text("Unchanged").font(.caption).foregroundStyle(.tertiary)
                            case .changed:
                                Text("→ \(row.newName)").font(.system(.caption, design: .rounded)).lineLimit(1).truncationMode(.middle)
                            case .conflict(let reason):
                                Text("→ \(row.newName) (\(reason))").font(.system(.caption, design: .rounded))
                                    .foregroundStyle(.red).lineLimit(1).truncationMode(.middle)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 160)
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { model.addFiles(panel.urls) }
    }
}
