import SwiftUI

struct PdfToolsView: View {
    let onBack: () -> Void
    @EnvironmentObject var pdfToolsModel: PdfToolsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // MARK: - Header
            HStack {
                Button { onBack() } label: {
                    Label("Back", systemImage: "chevron.left").labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
                Text("PDF Tools").font(.system(.headline, design: .rounded))
                Spacer()
            }
            Divider()

            // MARK: - Open Window Button
            Button { pdfToolsModel.openWindow() } label: {
                HStack {
                    Image(systemName: "doc.badge.gearshape")
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Open PDF Tools")
                            .font(.system(.subheadline, design: .rounded))
                            .fontWeight(.semibold)
                        Text("Merge, split, compress, rotate & convert PDFs")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.forward.square")
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.14)))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.18), lineWidth: 0.8))
            }
            .buttonStyle(.plain)

            // MARK: - Quick Actions
            HStack(spacing: 8) {
                quickActionButton("Merge", icon: "doc.on.doc", operation: .merge)
                quickActionButton("Split", icon: "scissors", operation: .split)
                quickActionButton("Compress", icon: "arrow.down.doc", operation: .compress)
            }

            // MARK: - Processing Indicator
            if case .processing(let progress, let desc) = pdfToolsModel.state {
                VStack(alignment: .leading, spacing: 4) {
                    Text(desc)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.08)))
            }

            // MARK: - Recent History
            if !pdfToolsModel.operationHistory.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Recent")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Clear") { pdfToolsModel.clearHistory() }
                            .font(.system(.caption2, design: .rounded))
                            .buttonStyle(.plain)
                            .foregroundStyle(.tertiary)
                    }
                    ForEach(pdfToolsModel.operationHistory.prefix(3)) { item in
                        HStack(spacing: 8) {
                            Image(systemName: iconForOperation(item.operation))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.inputDescription)
                                    .font(.system(.caption, design: .rounded))
                                    .lineLimit(1)
                                Text(item.completedAt, style: .relative)
                                    .font(.system(.caption2, design: .rounded))
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            if let path = item.outputPath ?? item.outputDirectory {
                                Button { pdfToolsModel.revealInFinder(path) } label: {
                                    Image(systemName: "folder").font(.caption2)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }

            Spacer()
        }
    }

    // MARK: - Helpers

    private func quickActionButton(_ title: String, icon: String, operation: PdfOperation) -> some View {
        Button {
            pdfToolsModel.selectedOperation = operation
            pdfToolsModel.openWindow()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.body)
                Text(title).font(.system(.caption2, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.12), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private func iconForOperation(_ op: String) -> String {
        switch op {
        case "merge": return "doc.on.doc"
        case "split": return "scissors"
        case "compress": return "arrow.down.doc"
        case "rotate": return "rotate.right"
        case "pdfToImage": return "photo"
        case "imageToPdf": return "doc.richtext"
        default: return "doc"
        }
    }
}
