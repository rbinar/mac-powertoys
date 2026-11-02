import SwiftUI

struct PdfToolsView: View {
    let onBack: () -> Void
    @EnvironmentObject var pdfToolsModel: PdfToolsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // MARK: - Header
            FeatureHeader(title: "PDF Tools", onBack: onBack)
            Divider()

            // MARK: - Open Window Button
            Button { pdfToolsModel.openWindow() } label: {
                HStack {
                    Image(systemName: "doc.badge.gearshape")
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Open PDF Tools")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("Merge, split, compress, rotate & convert PDFs")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.forward.square")
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .cardBackground()
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
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                }
                .padding(10)
                .cardBackground()
            }

            // MARK: - Recent History
            if !pdfToolsModel.operationHistory.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        SectionHeader("Recent")
                        Spacer()
                        Button("Clear") { pdfToolsModel.clearHistory() }
                            .font(.caption2)
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(pdfToolsModel.operationHistory.prefix(3)) { item in
                        HStack(spacing: 8) {
                            Image(systemName: iconForOperation(item.operation))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.inputDescription)
                                    .font(.caption)
                                    .lineLimit(1)
                                Text(item.completedAt, style: .relative)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let path = item.outputPath ?? item.outputDirectory {
                                Button { pdfToolsModel.revealInFinder(path) } label: {
                                    Image(systemName: "folder").font(.caption2)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Reveal in Finder")
                                .help("Reveal in Finder")
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
                Text(title).font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .cardBackground()
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
