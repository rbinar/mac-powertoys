import SwiftUI

struct MarkdownPreviewView: View {
    @EnvironmentObject var model: MarkdownPreviewModel
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Button(action: onBack) {
                    Label("Back", systemImage: "chevron.left")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)

                Text("Markdown Preview")
                    .font(.system(.headline, design: .rounded))

                Spacer()
            }

            Divider()

                // Open File Button
                Button {
                    model.openFile()
                } label: {
                    HStack {
                        Image(systemName: "folder")
                            .font(.body.weight(.semibold))
                        Text("Open Markdown File")
                            .font(.system(.subheadline, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.white.opacity(0.1))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.white.opacity(0.15), lineWidth: 0.8)
                    )
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
                            .font(.system(.subheadline, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.white.opacity(0.1))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.white.opacity(0.15), lineWidth: 0.8)
                    )
                }
                .buttonStyle(.plain)

                // Theme Toggle
                HStack {
                    Image(systemName: "circle.lefthalf.filled")
                        .foregroundStyle(.secondary)
                    Text("Dark Theme")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Toggle("", isOn: $model.isDarkTheme)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                }
                .padding(.vertical, 2)

                Divider()

                // Recent Files
                if !model.recentFiles.isEmpty {
                    HStack {
                        Text("Recent Files")
                            .font(.system(.caption, design: .rounded))
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            model.clearRecentFiles()
                        } label: {
                            Text("Clear")
                                .font(.system(.caption2, design: .rounded))
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
                                        .font(.system(.caption, design: .rounded))
                                        .lineLimit(1)
                                    Text(url.deletingLastPathComponent().path)
                                        .font(.system(.caption2, design: .rounded))
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
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
                                .foregroundStyle(.quaternary)
                            Text("No recent files")
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(.quaternary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
        }
    }
}
