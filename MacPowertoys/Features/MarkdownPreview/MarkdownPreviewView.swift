import SwiftUI

struct MarkdownPreviewView: View {
    @EnvironmentObject var model: MarkdownPreviewModel
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            FeatureHeader(title: "Markdown Preview", onBack: onBack)

            Divider()

                // Open File Button
                Button {
                    model.openFile()
                } label: {
                    HStack {
                        Image(systemName: "folder")
                            .font(.body.weight(.semibold))
                        Text("Open Markdown File")
                            .font(.subheadline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .cardBackground()
                }
                .buttonStyle(.plain)

                // Paste from Clipboard Button
                Button {
                    model.pasteFromClipboard()
                } label: {
                    HStack {
                        Image(systemName: "doc.on.clipboard")
                            .font(.body.weight(.semibold))
                        Text("Paste from Clipboard")
                            .font(.subheadline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .cardBackground()
                }
                .buttonStyle(.plain)

                // Theme Toggle
                HStack {
                    Image(systemName: "circle.lefthalf.filled")
                        .foregroundStyle(.secondary)
                    Text("Dark Theme")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Toggle("Dark Theme", isOn: $model.isDarkTheme)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                .padding(.vertical, 2)

                Divider()

                // Recent Files
                if !model.recentFiles.isEmpty {
                    HStack {
                        SectionHeader("Recent Files")
                        Spacer()
                        Button {
                            model.clearRecentFiles()
                        } label: {
                            Text("Clear")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(model.recentFiles, id: \.self) { url in
                        Button {
                            model.openRecentFile(url)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "doc.text")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(url.lastPathComponent)
                                        .font(.caption)
                                        .lineLimit(1)
                                    Text(url.deletingLastPathComponent().path)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 2)
                    }
                } else {
                    HStack {
                        Spacer()
                        VStack(spacing: 4) {
                            Image(systemName: "doc.richtext")
                                .font(.title2)
                                .foregroundStyle(.tertiary) // style-ok: decorative empty-state icon
                            Text("No recent files")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
                
            Spacer()
        }
    }
}
