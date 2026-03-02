import SwiftUI
import PDFKit
import UniformTypeIdentifiers

struct PdfToolsWindowView: View {
    @EnvironmentObject var model: PdfToolsModel
    @State private var draggedItemID: UUID?

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            contentArea
        }
        .frame(minWidth: 600, minHeight: 400)
        .font(.system(.body, design: .rounded))
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Operations")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 4)

            ForEach(PdfOperation.allCases, id: \.self) { operation in
                sidebarRow(operation)
            }

            Divider()
                .padding(.vertical, 8)
                .padding(.horizontal, 12)

            historySection

            Spacer()
        }
        .frame(width: 200)
        .background(.ultraThinMaterial)
    }

    private func sidebarRow(_ operation: PdfOperation) -> some View {
        let isSelected = model.selectedOperation == operation
        return Button {
            model.selectedOperation = operation
        } label: {
            HStack(spacing: 8) {
                Image(systemName: operation.icon)
                    .frame(width: 20)
                Text(operation.displayName)
                Spacer()
            }
            .font(.system(.subheadline, design: .rounded))
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("History")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                if !model.operationHistory.isEmpty {
                    Button("Clear") { model.clearHistory() }
                        .font(.system(.caption2, design: .rounded))
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)

            if model.operationHistory.isEmpty {
                Text("No history yet")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 12)
            } else {
                ForEach(model.operationHistory.prefix(5)) { item in
                    historyRow(item)
                }
            }
        }
    }

    private func historyRow(_ item: PdfOperationHistoryItem) -> some View {
        Button {
            if let path = item.outputPath ?? item.outputDirectory {
                model.revealInFinder(path)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.system(.caption2))
                    .foregroundStyle(.tertiary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.operation)
                        .font(.system(.caption2, design: .rounded))
                        .fontWeight(.medium)
                    Text(item.inputDescription)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    // MARK: - Content Area

    private var contentArea: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                switch model.selectedOperation {
                case .merge: mergeView
                case .split: splitView
                case .compress: compressView
                case .rotate: rotateView
                case .pdfToImage: pdfToImageView
                case .imageToPdf: imageToPdfView
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Merge

    private var mergeView: some View {
        VStack(alignment: .leading, spacing: 16) {
            operationHeader("Merge PDFs", subtitle: "Combine multiple PDFs into one")

            HStack {
                Button {
                    model.selectFiles(multiple: true)
                } label: {
                    Label("Add Files", systemImage: "plus.circle")
                        .font(.system(.subheadline, design: .rounded))
                }
                .buttonStyle(.plain)

                Spacer()

                if !model.mergeFiles.isEmpty {
                    Text("\(model.mergeFiles.count) files, \(model.mergeFiles.reduce(0) { $0 + $1.pageCount }) pages")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            if !model.mergeFiles.isEmpty {
                fileList(
                    items: model.mergeFiles,
                    onDelete: { model.removeMergeFile(at: $0) },
                    onMove: { model.moveMergeFile(from: $0, to: $1) },
                    showPageCount: true
                )
                .onDrop(of: [.fileURL, .pdf], isTargeted: nil) { providers in
                    handlePdfDrop(providers)
                }
            } else {
                dropZone(message: "Drop PDF files here or click Add Files", types: [.fileURL, .pdf]) { providers in
                    handlePdfDrop(providers)
                }
            }

            actionArea(
                canPerform: model.mergeFiles.count >= 2,
                performAction: { model.performMerge() },
                actionLabel: "Merge \(model.mergeFiles.count) Files"
            )
        }
    }

    // MARK: - Split

    private var splitView: some View {
        VStack(alignment: .leading, spacing: 16) {
            operationHeader("Split PDF", subtitle: "Split a PDF into separate files")

            fileSelectionButton(multiple: false)

            if let metadata = model.selectedFileMetadata {
                metadataCard(metadata)
            }

            if model.selectedFileURL != nil {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Split Mode")
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.medium)

                    Picker("", selection: $model.splitMode) {
                        ForEach(SplitMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.mini)

                    switch model.splitMode {
                    case .ranges:
                        TextField("e.g. 1-5, 8, 10-15", text: $model.splitRangeText)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.subheadline, design: .rounded))
                    case .everyN:
                        HStack {
                            Text("Pages per file:")
                                .font(.system(.subheadline, design: .rounded))
                            Stepper("\(model.splitEveryN)", value: $model.splitEveryN, in: 1...(model.selectedFileMetadata?.pageCount ?? 1))
                                .font(.system(.subheadline, design: .rounded))
                        }
                    case .burst:
                        Text("Each page will become a separate PDF file.")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.06)))
            }

            if model.selectedFileURL != nil {
                actionArea(
                    canPerform: splitCanPerform,
                    performAction: { model.performSplit() },
                    actionLabel: "Split PDF"
                )
            }
        }
    }

    private var splitCanPerform: Bool {
        guard model.selectedFileURL != nil else { return false }
        switch model.splitMode {
        case .ranges: return !model.splitRangeText.trimmingCharacters(in: .whitespaces).isEmpty
        case .everyN: return model.splitEveryN >= 1
        case .burst: return true
        }
    }

    // MARK: - Compress

    private var compressView: some View {
        VStack(alignment: .leading, spacing: 16) {
            operationHeader("Compress PDF", subtitle: "Reduce PDF file size")

            fileSelectionButton(multiple: false)

            if let metadata = model.selectedFileMetadata {
                metadataCard(metadata)
            }

            if model.selectedFileURL != nil {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Quality")
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.medium)

                    Picker("", selection: $model.compressQuality) {
                        ForEach(CompressQuality.allCases, id: \.self) { quality in
                            Text(quality.displayName).tag(quality)
                        }
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.mini)

                    Text(compressQualityDescription)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.06)))

                actionArea(
                    canPerform: true,
                    performAction: { model.performCompress() },
                    actionLabel: "Compress PDF"
                )
            }
        }
    }

    private var compressQualityDescription: String {
        switch model.compressQuality {
        case .high: return "Minimal quality loss, smaller file size reduction"
        case .medium: return "Balanced quality and file size"
        case .low: return "Maximum file size reduction, noticeable quality loss"
        }
    }

    // MARK: - Rotate

    private var rotateView: some View {
        VStack(alignment: .leading, spacing: 16) {
            operationHeader("Rotate PDF", subtitle: "Rotate PDF pages")

            fileSelectionButton(multiple: false)

            if let metadata = model.selectedFileMetadata {
                metadataCard(metadata)
            }

            if model.selectedFileURL != nil {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Rotation")
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.medium)

                    Picker("", selection: $model.rotationAngle) {
                        ForEach(RotationAngle.allCases, id: \.self) { angle in
                            Text(angle.displayName).tag(angle)
                        }
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.mini)

                    Toggle("All pages", isOn: $model.rotateAllPages)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .font(.system(.subheadline, design: .rounded))

                    if !model.rotateAllPages {
                        TextField("e.g. 1-5, 8, 10-15", text: $model.rotatePageRangeText)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.subheadline, design: .rounded))
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.06)))

                actionArea(
                    canPerform: model.rotateAllPages || !model.rotatePageRangeText.trimmingCharacters(in: .whitespaces).isEmpty,
                    performAction: { model.performRotate() },
                    actionLabel: "Rotate PDF"
                )
            }
        }
    }

    // MARK: - PDF to Image

    private var pdfToImageView: some View {
        VStack(alignment: .leading, spacing: 16) {
            operationHeader("PDF to Images", subtitle: "Export PDF pages as images")

            fileSelectionButton(multiple: false)

            if let metadata = model.selectedFileMetadata {
                metadataCard(metadata)
            }

            if model.selectedFileURL != nil {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Format")
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.medium)

                    Picker("", selection: $model.imageExportFormat) {
                        ForEach(ImageExportFormat.allCases, id: \.self) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.mini)

                    Text("DPI")
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.medium)

                    Picker("", selection: $model.imageExportDPI) {
                        Text("72").tag(72)
                        Text("150").tag(150)
                        Text("300").tag(300)
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.mini)

                    Text(dpiDescription)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.06)))

                actionArea(
                    canPerform: true,
                    performAction: { model.performPdfToImage() },
                    actionLabel: "Export as \(model.imageExportFormat.displayName)"
                )
            }
        }
    }

    private var dpiDescription: String {
        switch model.imageExportDPI {
        case 72: return "Screen resolution — small file size"
        case 150: return "Good quality — suitable for most uses"
        case 300: return "Print quality — larger file size"
        default: return ""
        }
    }

    // MARK: - Image to PDF

    private var imageToPdfView: some View {
        VStack(alignment: .leading, spacing: 16) {
            operationHeader("Images to PDF", subtitle: "Convert images to a PDF")

            HStack {
                Button {
                    model.selectImagesForPdf()
                } label: {
                    Label("Add Images", systemImage: "plus.circle")
                        .font(.system(.subheadline, design: .rounded))
                }
                .buttonStyle(.plain)

                Spacer()

                if !model.imageToPdfFiles.isEmpty {
                    Text("\(model.imageToPdfFiles.count) images")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            if !model.imageToPdfFiles.isEmpty {
                fileList(
                    items: model.imageToPdfFiles,
                    onDelete: { model.removeImageToPdfFile(at: $0) },
                    onMove: { model.moveImageToPdfFile(from: $0, to: $1) },
                    showPageCount: false
                )
                .onDrop(of: [.fileURL, .image], isTargeted: nil) { providers in
                    handleImageDrop(providers)
                }
            } else {
                dropZone(message: "Drop images here or click Add Images", types: [.fileURL, .image]) { providers in
                    handleImageDrop(providers)
                }
            }

            actionArea(
                canPerform: !model.imageToPdfFiles.isEmpty,
                performAction: { model.performImageToPdf() },
                actionLabel: "Create PDF"
            )
        }
    }

    // MARK: - Shared Components

    private func operationHeader(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(.title2, design: .rounded))
                .fontWeight(.semibold)
            Text(subtitle)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private func fileSelectionButton(multiple: Bool) -> some View {
        HStack {
            Button {
                model.selectFiles(multiple: multiple)
            } label: {
                Label(model.selectedFileURL == nil ? "Select PDF" : "Change PDF", systemImage: "doc.badge.plus")
                    .font(.system(.subheadline, design: .rounded))
            }
            .buttonStyle(.plain)

            if let url = model.selectedFileURL {
                Text(url.lastPathComponent)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    @ViewBuilder
    private func metadataCard(_ metadata: PdfMetadata) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Label("\(metadata.pageCount) pages", systemImage: "doc.plaintext")
                Label(metadata.formattedFileSize, systemImage: "internaldrive")
                Label("\(Int(metadata.pageWidth))x\(Int(metadata.pageHeight)) pt", systemImage: "aspectratio")
            }
            .font(.system(.caption, design: .rounded))
            .foregroundStyle(.secondary)

            if metadata.isEncrypted {
                Label("Encrypted", systemImage: "lock.fill")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.orange)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.06)))
    }

    private func fileList(items: [MergeFileItem], onDelete: @escaping (IndexSet) -> Void, onMove: @escaping (IndexSet, Int) -> Void, showPageCount: Bool) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                HStack(spacing: 8) {
                    Image(systemName: "line.3.horizontal")
                        .foregroundStyle(.tertiary)
                        .font(.caption2)

                    if showPageCount {
                        Image(systemName: "doc.fill")
                            .foregroundStyle(.secondary)
                    } else {
                        thumbnailView(for: item.url)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.name)
                            .font(.system(.caption, design: .rounded))
                            .lineLimit(1)
                        HStack(spacing: 8) {
                            if showPageCount {
                                Text("\(item.pageCount) pg")
                            }
                            Text(ByteCountFormatter.string(fromByteCount: item.fileSize, countStyle: .file))
                        }
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        onDelete(IndexSet(integer: index))
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 5)
                .padding(.horizontal, 10)
                .contentShape(Rectangle())
                .background(draggedItemID == item.id ? Color.gray.opacity(0.1) : Color.clear)
                .onDrag {
                    draggedItemID = item.id
                    return NSItemProvider(object: item.id.uuidString as NSString)
                }
                .onDrop(
                    of: [.text],
                    delegate: ReorderDropDelegate(
                        item: item,
                        items: items,
                        draggedItemID: $draggedItemID,
                        onMove: onMove
                    )
                )

                if index < items.count - 1 {
                    Divider().padding(.leading, 36)
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.1), lineWidth: 0.5))
    }

    private func thumbnailView(for url: URL) -> some View {
        Group {
            if let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 24, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func dropZone(message: String, types: [UTType], handler: @escaping ([NSItemProvider]) -> Bool) -> some View {
        RoundedRectangle(cornerRadius: 10)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
            .foregroundStyle(.white.opacity(0.18))
            .frame(height: 80)
            .overlay(
                VStack(spacing: 6) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(.title3, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text(message)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            )
            .onDrop(of: types, isTargeted: nil, perform: handler)
    }

    @ViewBuilder
    private func actionArea(canPerform: Bool, performAction: @escaping () -> Void, actionLabel: String) -> some View {
        switch model.state {
        case .idle:
            Button(action: performAction) {
                HStack {
                    Image(systemName: "play.fill")
                    Text(actionLabel)
                }
                .font(.system(.subheadline, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(canPerform ? Color.accentColor : Color.gray.opacity(0.3)))
                .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            .disabled(!canPerform)

        case .processing(let progress, let description):
            VStack(spacing: 6) {
                HStack {
                    Text(description)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(progress * 100))%")
                        .font(.system(.caption, design: .monospaced))
                }
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                Button("Cancel") { model.cancelOperation() }
                    .font(.system(.caption, design: .rounded))
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.06)))

        case .completed(let result):
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(result.message)
                        .font(.system(.subheadline, design: .rounded))
                }

                if let inputSize = result.inputSize, let outputSize = result.outputSize {
                    HStack(spacing: 12) {
                        Label(ByteCountFormatter.string(fromByteCount: inputSize, countStyle: .file), systemImage: "arrow.right")
                        Label(ByteCountFormatter.string(fromByteCount: outputSize, countStyle: .file), systemImage: "arrow.left")
                        let pct = inputSize > 0 ? Double(inputSize - outputSize) / Double(inputSize) * 100 : 0
                        Text(pct > 0 ? "-\(Int(pct))%" : "+\(Int(abs(pct)))%")
                            .foregroundStyle(pct > 0 ? .green : .orange)
                    }
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                }

                if let count = result.fileCount, count > 1 {
                    Text("\(count) files created")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                HStack {
                    if let path = result.outputPath ?? result.outputDirectory {
                        Button("Reveal in Finder") { model.revealInFinder(path) }
                            .font(.system(.caption, design: .rounded))
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    }
                    Button("New Operation") { model.resetState() }
                        .font(.system(.caption, design: .rounded))
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(.green.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.green.opacity(0.2), lineWidth: 0.5))

        case .failed(let message):
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                    Text("Error")
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.medium)
                }
                Text(message)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                Button("Try Again") { model.resetState() }
                    .font(.system(.caption, design: .rounded))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(.red.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.red.opacity(0.2), lineWidth: 0.5))
        }
    }

    // MARK: - Drag & Drop

    private func handlePdfDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                guard let data = data as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil),
                      url.pathExtension.lowercased() == "pdf" else { return }
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("pdf")
                try? FileManager.default.copyItem(at: url, to: tempURL)
                Task { @MainActor in
                    model.addMergeFiles([tempURL])
                }
            }
            handled = true
        }
        return handled
    }

    private func handleImageDrop(_ providers: [NSItemProvider]) -> Bool {
        let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "tiff", "tif", "bmp", "gif", "heic"]
        var handled = false
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                guard let data = data as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil),
                      imageExtensions.contains(url.pathExtension.lowercased()) else { return }
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(url.pathExtension)
                try? FileManager.default.copyItem(at: url, to: tempURL)
                Task { @MainActor in
                    let fileSize = (try? FileManager.default.attributesOfItem(atPath: tempURL.path)[.size] as? Int64) ?? 0
                    let item = MergeFileItem(id: UUID(), url: tempURL, name: url.lastPathComponent, pageCount: 1, fileSize: fileSize)
                    model.imageToPdfFiles.append(item)
                }
            }
            handled = true
        }
        return handled
    }
}

// MARK: - Reorder Drop Delegate
struct ReorderDropDelegate: DropDelegate {
    let item: MergeFileItem
    let items: [MergeFileItem]
    @Binding var draggedItemID: UUID?
    let onMove: (IndexSet, Int) -> Void

    func dropEntered(info: DropInfo) {
        guard let draggedId = draggedItemID, draggedId != item.id else { return }
        guard let from = items.firstIndex(where: { $0.id == draggedId }),
              let to = items.firstIndex(where: { $0.id == item.id }) else { return }

        if from != to {
            withAnimation(.default) {
                onMove(IndexSet(integer: from), to > from ? to + 1 : to)
            }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedItemID = nil
        return true
    }
}
