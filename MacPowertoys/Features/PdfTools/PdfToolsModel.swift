import Foundation
import AppKit
import SwiftUI
import PDFKit
import UniformTypeIdentifiers

// MARK: - Enums & Types

enum PdfOperation: String, CaseIterable {
    case merge, split, compress, rotate, pdfToImage, imageToPdf

    var displayName: String {
        switch self {
        case .merge: return "Merge"
        case .split: return "Split"
        case .compress: return "Compress"
        case .rotate: return "Rotate"
        case .pdfToImage: return "PDF to Image"
        case .imageToPdf: return "Image to PDF"
        }
    }

    var icon: String {
        switch self {
        case .merge: return "doc.on.doc"
        case .split: return "scissors"
        case .compress: return "arrow.down.doc"
        case .rotate: return "rotate.right"
        case .pdfToImage: return "photo"
        case .imageToPdf: return "doc.richtext"
        }
    }

    var description: String {
        switch self {
        case .merge: return "Combine multiple PDFs into one"
        case .split: return "Split a PDF into separate files"
        case .compress: return "Reduce PDF file size"
        case .rotate: return "Rotate PDF pages"
        case .pdfToImage: return "Export PDF pages as images"
        case .imageToPdf: return "Convert images to a PDF"
        }
    }
}

enum PdfToolsState: Equatable {
    case idle
    case processing(progress: Double, description: String)
    case completed(result: OperationResult)
    case failed(message: String)
}

struct OperationResult: Equatable {
    let message: String
    let outputPath: String?
    let outputDirectory: String?
    let inputSize: Int64?
    let outputSize: Int64?
    let fileCount: Int?
}

enum SplitMode: String, CaseIterable {
    case ranges
    case everyN
    case burst

    var displayName: String {
        switch self {
        case .ranges: return "Page Ranges"
        case .everyN: return "Every N Pages"
        case .burst: return "Every Page"
        }
    }
}

enum CompressQuality: String, CaseIterable {
    case high, medium, low

    var displayName: String {
        switch self {
        case .high: return "High"
        case .medium: return "Medium"
        case .low: return "Low"
        }
    }

    var scaleFactor: CGFloat {
        switch self {
        case .high: return 0.9
        case .medium: return 0.7
        case .low: return 0.5
        }
    }

    var jpegQuality: CGFloat {
        switch self {
        case .high: return 0.85
        case .medium: return 0.6
        case .low: return 0.35
        }
    }
}

enum ImageExportFormat: String, CaseIterable {
    case png, jpeg, tiff

    var displayName: String {
        switch self {
        case .png: return "PNG"
        case .jpeg: return "JPEG"
        case .tiff: return "TIFF"
        }
    }

    var fileExtension: String {
        switch self {
        case .png: return "png"
        case .jpeg: return "jpg"
        case .tiff: return "tiff"
        }
    }
}

enum RotationAngle: Int, CaseIterable {
    case cw90 = 90
    case ccw90 = -90
    case flip180 = 180

    var displayName: String {
        switch self {
        case .cw90: return "90° Clockwise"
        case .ccw90: return "90° Counter-clockwise"
        case .flip180: return "180° Flip"
        }
    }
}

struct MergeFileItem: Identifiable {
    let id: UUID
    let url: URL
    let name: String
    let pageCount: Int
    let fileSize: Int64
}

struct PdfMetadata: Equatable {
    let pageCount: Int
    let fileSize: Int64
    let formattedFileSize: String
    let pageWidth: CGFloat
    let pageHeight: CGFloat
    let isEncrypted: Bool
}

struct PdfOperationHistoryItem: Codable, Identifiable {
    let id: UUID
    let operation: String
    let inputDescription: String
    let outputPath: String?
    let outputDirectory: String?
    let completedAt: Date
    let inputSize: Int64?
    let outputSize: Int64?
    let fileCount: Int?
}

// MARK: - Model

@MainActor
final class PdfToolsModel: ObservableObject {

    // MARK: - Settings

    @Published var selectedOperation: PdfOperation = .merge {
        didSet {
            UserDefaults.standard.set(selectedOperation.rawValue, forKey: "pdfTools.selectedOperation")
            if case .completed = state { state = .idle }
            if case .failed = state { state = .idle }
        }
    }
    @Published var splitMode: SplitMode = .ranges {
        didSet { UserDefaults.standard.set(splitMode.rawValue, forKey: "pdfTools.splitMode") }
    }
    @Published var compressQuality: CompressQuality = .medium {
        didSet { UserDefaults.standard.set(compressQuality.rawValue, forKey: "pdfTools.compressQuality") }
    }
    @Published var rotationAngle: RotationAngle = .cw90 {
        didSet { UserDefaults.standard.set(rotationAngle.rawValue, forKey: "pdfTools.rotationAngle") }
    }
    @Published var imageExportFormat: ImageExportFormat = .png {
        didSet { UserDefaults.standard.set(imageExportFormat.rawValue, forKey: "pdfTools.imageExportFormat") }
    }
    @Published var imageExportDPI: Int = 150 {
        didSet { UserDefaults.standard.set(imageExportDPI, forKey: "pdfTools.imageExportDPI") }
    }
    @Published var splitRangeText: String = ""
    @Published var splitEveryN: Int = 1
    @Published var rotateAllPages: Bool = true
    @Published var rotatePageRangeText: String = ""

    // MARK: - Runtime State

    @Published private(set) var state: PdfToolsState = .idle
    @Published private(set) var selectedFileMetadata: PdfMetadata?
    @Published var mergeFiles: [MergeFileItem] = []
    @Published private(set) var selectedFileURL: URL?
    @Published var imageToPdfFiles: [MergeFileItem] = []
    @Published private(set) var operationHistory: [PdfOperationHistoryItem] = []

    // MARK: - Private

    private var toolsWindow: NSWindow?
    private var currentTask: Task<Void, Never>?

    // MARK: - Init

    init() {
        if let raw = UserDefaults.standard.string(forKey: "pdfTools.selectedOperation"),
           let op = PdfOperation(rawValue: raw) {
            selectedOperation = op
        }
        if let raw = UserDefaults.standard.string(forKey: "pdfTools.splitMode"),
           let mode = SplitMode(rawValue: raw) {
            splitMode = mode
        }
        if let raw = UserDefaults.standard.string(forKey: "pdfTools.compressQuality"),
           let quality = CompressQuality(rawValue: raw) {
            compressQuality = quality
        }
        if let raw = UserDefaults.standard.object(forKey: "pdfTools.rotationAngle") as? Int,
           let angle = RotationAngle(rawValue: raw) {
            rotationAngle = angle
        }
        if let raw = UserDefaults.standard.string(forKey: "pdfTools.imageExportFormat"),
           let format = ImageExportFormat(rawValue: raw) {
            imageExportFormat = format
        }
        let dpi = UserDefaults.standard.integer(forKey: "pdfTools.imageExportDPI")
        if dpi > 0 {
            imageExportDPI = dpi
        }
        if let data = UserDefaults.standard.data(forKey: "pdfTools.operationHistory"),
           let history = try? JSONDecoder().decode([PdfOperationHistoryItem].self, from: data) {
            operationHistory = history
        }
    }

    // MARK: - Lifecycle

    func stopMonitoring() {
        currentTask?.cancel()
        currentTask = nil
        toolsWindow?.close()
        toolsWindow = nil
    }

    // MARK: - Window

    func openWindow() {
        if let window = toolsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 550),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 600, height: 400)
        window.title = "PDF Tools"
        window.center()
        window.contentView = NSHostingView(rootView: PdfToolsWindowView().environmentObject(self))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        toolsWindow = window
    }

    // MARK: - File Selection

    func selectFiles(multiple: Bool) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = multiple
        panel.canChooseDirectories = false
        panel.message = multiple ? "Select PDF files to merge" : "Select a PDF file"

        guard panel.runModal() == .OK else { return }

        if multiple {
            addMergeFiles(panel.urls)
        } else if let url = panel.url {
            setFile(url)
        }
    }

    func selectImagesForPdf() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .bmp, .gif]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Select images to convert to PDF"

        guard panel.runModal() == .OK else { return }

        for url in panel.urls {
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
            let item = MergeFileItem(id: UUID(), url: url, name: url.lastPathComponent, pageCount: 1, fileSize: fileSize)
            imageToPdfFiles.append(item)
        }
    }

    func setFile(_ url: URL) {
        selectedFileURL = url
        selectedFileMetadata = extractMetadata(from: url)
    }

    func addMergeFiles(_ urls: [URL]) {
        for url in urls {
            guard let doc = openPdfDocument(at: url) else { continue }
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
            let item = MergeFileItem(id: UUID(), url: url, name: url.lastPathComponent, pageCount: doc.pageCount, fileSize: fileSize)
            mergeFiles.append(item)
        }
    }

    func removeMergeFile(at offsets: IndexSet) {
        mergeFiles.remove(atOffsets: offsets)
    }

    func moveMergeFile(from source: IndexSet, to destination: Int) {
        mergeFiles.move(fromOffsets: source, toOffset: destination)
    }

    func removeImageToPdfFile(at offsets: IndexSet) {
        imageToPdfFiles.remove(atOffsets: offsets)
    }

    func moveImageToPdfFile(from source: IndexSet, to destination: Int) {
        imageToPdfFiles.move(fromOffsets: source, toOffset: destination)
    }

    // MARK: - Metadata

    private func extractMetadata(from url: URL) -> PdfMetadata? {
        guard let doc = openPdfDocument(at: url) else { return nil }
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        let formattedSize = ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
        var pageWidth: CGFloat = 0
        var pageHeight: CGFloat = 0
        if let firstPage = doc.page(at: 0) {
            let bounds = firstPage.bounds(for: .mediaBox)
            pageWidth = bounds.width
            pageHeight = bounds.height
        }
        return PdfMetadata(
            pageCount: doc.pageCount,
            fileSize: fileSize,
            formattedFileSize: formattedSize,
            pageWidth: pageWidth,
            pageHeight: pageHeight,
            isEncrypted: doc.isEncrypted
        )
    }

    private func openPdfDocument(at url: URL) -> PDFDocument? {
        guard let doc = PDFDocument(url: url) else {
            NSLog("[PdfTools] Failed to open PDF at %@", url.path)
            return nil
        }
        if doc.isEncrypted && doc.isLocked {
            return showPasswordDialog(for: url)
        }
        return doc
    }

    private func showPasswordDialog(for url: URL) -> PDFDocument? {
        for attempt in 1...3 {
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "Password Protected PDF"
            if attempt > 1 {
                alert.informativeText = "Incorrect password. Attempt \(attempt) of 3.\nEnter password to unlock \(url.lastPathComponent):"
            } else {
                alert.informativeText = "Enter password to unlock \(url.lastPathComponent):"
            }
            alert.addButton(withTitle: "Unlock")
            alert.addButton(withTitle: "Cancel")

            let passwordField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
            alert.accessoryView = passwordField
            alert.window.initialFirstResponder = passwordField

            let response = alert.runModal()
            guard response == .alertFirstButtonReturn else { return nil }

            let password = passwordField.stringValue
            guard let doc = PDFDocument(url: url) else { return nil }
            if doc.unlock(withPassword: password) {
                return doc
            }
        }
        NSLog("[PdfTools] Failed to unlock password-protected PDF after 3 attempts: %@", url.lastPathComponent)
        return nil
    }

    // MARK: - Operations

    func performMerge() {
        guard mergeFiles.count >= 2 else {
            state = .failed(message: "Select at least 2 PDF files to merge.")
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "Merged.pdf"
        panel.message = "Save merged PDF"
        guard panel.runModal() == .OK, let outputURL = panel.url else { return }

        let files = mergeFiles
        let totalInputSize = files.reduce(Int64(0)) { $0 + $1.fileSize }

        state = .processing(progress: 0, description: "Merging PDFs...")
        currentTask = Task.detached { [weak self] in
            do {
                let outputDoc = PDFDocument()
                var pageIndex = 0
                let totalPages = files.reduce(0) { $0 + $1.pageCount }

                for file in files {
                    guard !Task.isCancelled else {
                        await MainActor.run { self?.state = .idle }
                        return
                    }
                    guard let doc = PDFDocument(url: file.url) else {
                        await MainActor.run { self?.state = .failed(message: "Failed to open \(file.name)") }
                        return
                    }
                    if doc.isEncrypted && doc.isLocked {
                        await MainActor.run { self?.state = .failed(message: "\(file.name) is password protected. Open it individually first.") }
                        return
                    }
                    for i in 0..<doc.pageCount {
                        guard !Task.isCancelled else {
                            await MainActor.run { self?.state = .idle }
                            return
                        }
                        if let page = doc.page(at: i) {
                            outputDoc.insert(page, at: pageIndex)
                            pageIndex += 1
                        }
                        let progress = Double(pageIndex) / Double(totalPages)
                        await MainActor.run { self?.state = .processing(progress: progress, description: "Merging page \(pageIndex) of \(totalPages)...") }
                    }
                }

                guard outputDoc.write(to: outputURL) else {
                    await MainActor.run { self?.state = .failed(message: "Failed to write merged PDF.") }
                    return
                }

                let outputSize = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int64) ?? 0
                let result = OperationResult(
                    message: "Merged \(files.count) files (\(totalPages) pages)",
                    outputPath: outputURL.path,
                    outputDirectory: nil,
                    inputSize: totalInputSize,
                    outputSize: outputSize,
                    fileCount: files.count
                )
                await MainActor.run {
                    self?.state = .completed(result: result)
                    self?.addToHistory(operation: "Merge", input: "\(files.count) files", outputPath: outputURL.path, outputDirectory: nil, inputSize: totalInputSize, outputSize: outputSize, fileCount: files.count)
                }
            }
        }
    }

    func performSplit() {
        guard let fileURL = selectedFileURL, let metadata = selectedFileMetadata else {
            state = .failed(message: "Select a PDF file first.")
            return
        }
        guard let doc = PDFDocument(url: fileURL) else {
            state = .failed(message: "Failed to open PDF.")
            return
        }

        let pageCount = metadata.pageCount
        var splitRanges: [[Int]] = []
        let baseName = fileURL.deletingPathExtension().lastPathComponent

        switch splitMode {
        case .ranges:
            guard let ranges = parsePageRanges(splitRangeText, maxPage: pageCount) else {
                state = .failed(message: "Invalid page ranges. Use format: 1-5, 8, 10-15")
                return
            }
            for range in ranges {
                splitRanges.append(range.map { $0 - 1 })
            }
        case .everyN:
            guard splitEveryN >= 1 else {
                state = .failed(message: "Pages per split must be at least 1.")
                return
            }
            var start = 0
            while start < pageCount {
                let end = min(start + splitEveryN, pageCount)
                splitRanges.append(Array(start..<end))
                start = end
            }
        case .burst:
            for i in 0..<pageCount {
                splitRanges.append([i])
            }
        }

        guard !splitRanges.isEmpty else {
            state = .failed(message: "No page ranges to split.")
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.message = "Select output directory for split PDFs"
        guard panel.runModal() == .OK, let outputDir = panel.url else { return }

        let inputSize = metadata.fileSize
        let mode = splitMode

        state = .processing(progress: 0, description: "Splitting PDF...")
        currentTask = Task.detached { [weak self] in
            let total = splitRanges.count
            var filesWritten = 0

            for (index, pageIndices) in splitRanges.enumerated() {
                guard !Task.isCancelled else {
                    await MainActor.run { self?.state = .idle }
                    return
                }

                let newDoc = PDFDocument()
                for (insertIndex, pageIdx) in pageIndices.enumerated() {
                    if let page = doc.page(at: pageIdx) {
                        newDoc.insert(page, at: insertIndex)
                    }
                }

                let fileName: String
                switch mode {
                case .ranges:
                    let first = pageIndices.first.map { $0 + 1 } ?? 0
                    let last = pageIndices.last.map { $0 + 1 } ?? 0
                    fileName = first == last ? "\(baseName)_page_\(first).pdf" : "\(baseName)_pages_\(first)-\(last).pdf"
                case .everyN:
                    let first = pageIndices.first.map { $0 + 1 } ?? 0
                    let last = pageIndices.last.map { $0 + 1 } ?? 0
                    fileName = "\(baseName)_pages_\(first)-\(last).pdf"
                case .burst:
                    let pageNum = (pageIndices.first ?? 0) + 1
                    fileName = "\(baseName)_page_\(pageNum).pdf"
                }

                let fileURL = outputDir.appendingPathComponent(fileName)
                guard newDoc.write(to: fileURL) else {
                    NSLog("[PdfTools] Failed to write split file: %@", fileName)
                    await MainActor.run { self?.state = .failed(message: "Failed to write \(fileName)") }
                    return
                }
                filesWritten += 1

                let progress = Double(index + 1) / Double(total)
                await MainActor.run { self?.state = .processing(progress: progress, description: "Writing file \(index + 1) of \(total)...") }
            }

            let result = OperationResult(
                message: "Split into \(filesWritten) files",
                outputPath: nil,
                outputDirectory: outputDir.path,
                inputSize: inputSize,
                outputSize: nil,
                fileCount: filesWritten
            )
            await MainActor.run {
                self?.state = .completed(result: result)
                self?.addToHistory(operation: "Split", input: baseName, outputPath: nil, outputDirectory: outputDir.path, inputSize: inputSize, outputSize: nil, fileCount: filesWritten)
            }
        }
    }

    func performCompress() {
        guard let fileURL = selectedFileURL, let metadata = selectedFileMetadata else {
            state = .failed(message: "Select a PDF file first.")
            return
        }
        guard let doc = PDFDocument(url: fileURL) else {
            state = .failed(message: "Failed to open PDF.")
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(fileURL.deletingPathExtension().lastPathComponent)_compressed.pdf"
        panel.message = "Save compressed PDF"
        guard panel.runModal() == .OK, let outputURL = panel.url else { return }

        let quality = compressQuality
        let inputSize = metadata.fileSize
        let pageCount = doc.pageCount

        state = .processing(progress: 0, description: "Compressing PDF...")
        currentTask = Task.detached { [weak self] in
            let outputDoc = PDFDocument()

            for i in 0..<pageCount {
                guard !Task.isCancelled else {
                    await MainActor.run { self?.state = .idle }
                    return
                }

                guard let page = doc.page(at: i) else { continue }
                let bounds = page.bounds(for: .mediaBox)
                let newWidth = bounds.width * quality.scaleFactor
                let newHeight = bounds.height * quality.scaleFactor

                let colorSpace = CGColorSpaceCreateDeviceRGB()
                guard let context = CGContext(
                    data: nil,
                    width: Int(newWidth),
                    height: Int(newHeight),
                    bitsPerComponent: 8,
                    bytesPerRow: 0,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                ) else { continue }

                context.scaleBy(x: quality.scaleFactor, y: quality.scaleFactor)

                NSGraphicsContext.saveGraphicsState()
                let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
                NSGraphicsContext.current = nsContext
                page.draw(with: .mediaBox, to: context)
                NSGraphicsContext.restoreGraphicsState()

                guard let cgImage = context.makeImage() else { continue }
                let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
                guard let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: quality.jpegQuality]) else { continue }

                let nsImage = NSImage(data: jpegData)
                if let nsImage, let compressedPage = PDFPage(image: nsImage) {
                    outputDoc.insert(compressedPage, at: i)
                }

                let progress = Double(i + 1) / Double(pageCount)
                await MainActor.run { self?.state = .processing(progress: progress, description: "Compressing page \(i + 1) of \(pageCount)...") }
            }

            guard outputDoc.write(to: outputURL) else {
                await MainActor.run { self?.state = .failed(message: "Failed to write compressed PDF.") }
                return
            }

            let outputSize = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int64) ?? 0
            let savedPercent = inputSize > 0 ? Int((1.0 - Double(outputSize) / Double(inputSize)) * 100) : 0
            let message: String
            if outputSize >= inputSize {
                message = "Compressed PDF is not smaller than original (\(ByteCountFormatter.string(fromByteCount: inputSize, countStyle: .file)) → \(ByteCountFormatter.string(fromByteCount: outputSize, countStyle: .file))). The original may already be well-optimized."
            } else {
                message = "Compressed: \(ByteCountFormatter.string(fromByteCount: inputSize, countStyle: .file)) → \(ByteCountFormatter.string(fromByteCount: outputSize, countStyle: .file)) (\(savedPercent)% reduction)"
            }

            let result = OperationResult(
                message: message,
                outputPath: outputURL.path,
                outputDirectory: nil,
                inputSize: inputSize,
                outputSize: outputSize,
                fileCount: 1
            )
            await MainActor.run {
                self?.state = .completed(result: result)
                self?.addToHistory(operation: "Compress", input: fileURL.lastPathComponent, outputPath: outputURL.path, outputDirectory: nil, inputSize: inputSize, outputSize: outputSize, fileCount: 1)
            }
        }
    }

    func performRotate() {
        guard let fileURL = selectedFileURL, let metadata = selectedFileMetadata else {
            state = .failed(message: "Select a PDF file first.")
            return
        }
        guard let doc = PDFDocument(url: fileURL) else {
            state = .failed(message: "Failed to open PDF.")
            return
        }

        let pageCount = metadata.pageCount
        var targetPageIndices: [Int]

        if rotateAllPages {
            targetPageIndices = Array(0..<pageCount)
        } else {
            guard let ranges = parsePageRanges(rotatePageRangeText, maxPage: pageCount) else {
                state = .failed(message: "Invalid page ranges. Use format: 1-5, 8, 10-15")
                return
            }
            targetPageIndices = ranges.flatMap { Array($0).map { $0 - 1 } }
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(fileURL.deletingPathExtension().lastPathComponent)_rotated.pdf"
        panel.message = "Save rotated PDF"
        guard panel.runModal() == .OK, let outputURL = panel.url else { return }

        let angle = rotationAngle
        let inputSize = metadata.fileSize
        let targetSet = Set(targetPageIndices)

        state = .processing(progress: 0, description: "Rotating pages...")
        currentTask = Task.detached { [weak self] in
            for i in 0..<pageCount {
                guard !Task.isCancelled else {
                    await MainActor.run { self?.state = .idle }
                    return
                }

                if targetSet.contains(i), let page = doc.page(at: i) {
                    let current = page.rotation
                    let delta: Int
                    switch angle {
                    case .cw90: delta = 90
                    case .ccw90: delta = 270
                    case .flip180: delta = 180
                    }
                    page.rotation = (current + delta) % 360
                }

                let progress = Double(i + 1) / Double(pageCount)
                await MainActor.run { self?.state = .processing(progress: progress, description: "Rotating page \(i + 1) of \(pageCount)...") }
            }

            guard doc.write(to: outputURL) else {
                await MainActor.run { self?.state = .failed(message: "Failed to write rotated PDF.") }
                return
            }

            let outputSize = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int64) ?? 0
            let result = OperationResult(
                message: "Rotated \(targetSet.count) page(s) by \(angle.displayName)",
                outputPath: outputURL.path,
                outputDirectory: nil,
                inputSize: inputSize,
                outputSize: outputSize,
                fileCount: 1
            )
            await MainActor.run {
                self?.state = .completed(result: result)
                self?.addToHistory(operation: "Rotate", input: fileURL.lastPathComponent, outputPath: outputURL.path, outputDirectory: nil, inputSize: inputSize, outputSize: outputSize, fileCount: 1)
            }
        }
    }

    func performPdfToImage() {
        guard let fileURL = selectedFileURL, let metadata = selectedFileMetadata else {
            state = .failed(message: "Select a PDF file first.")
            return
        }
        guard let doc = PDFDocument(url: fileURL) else {
            state = .failed(message: "Failed to open PDF.")
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.message = "Select output directory for images"
        guard panel.runModal() == .OK, let outputDir = panel.url else { return }

        let pageCount = metadata.pageCount
        let format = imageExportFormat
        let dpi = imageExportDPI
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        let inputSize = metadata.fileSize

        state = .processing(progress: 0, description: "Exporting pages as images...")
        currentTask = Task.detached { [weak self] in
            let scale = CGFloat(dpi) / 72.0

            for i in 0..<pageCount {
                guard !Task.isCancelled else {
                    await MainActor.run { self?.state = .idle }
                    return
                }

                guard let page = doc.page(at: i) else { continue }
                let bounds = page.bounds(for: .mediaBox)
                let pixelWidth = Int(bounds.width * scale)
                let pixelHeight = Int(bounds.height * scale)

                let colorSpace = CGColorSpaceCreateDeviceRGB()
                guard let context = CGContext(
                    data: nil,
                    width: pixelWidth,
                    height: pixelHeight,
                    bitsPerComponent: 8,
                    bytesPerRow: 0,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                ) else { continue }

                context.setFillColor(CGColor.white)
                context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
                context.scaleBy(x: scale, y: scale)

                NSGraphicsContext.saveGraphicsState()
                let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
                NSGraphicsContext.current = nsContext
                page.draw(with: .mediaBox, to: context)
                NSGraphicsContext.restoreGraphicsState()

                guard let cgImage = context.makeImage() else { continue }
                let bitmapRep = NSBitmapImageRep(cgImage: cgImage)

                let imageData: Data?
                switch format {
                case .png:
                    imageData = bitmapRep.representation(using: .png, properties: [:])
                case .jpeg:
                    imageData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
                case .tiff:
                    imageData = bitmapRep.representation(using: .tiff, properties: [:])
                }

                guard let data = imageData else { continue }

                let fileName = "\(baseName)_page_\(i + 1).\(format.fileExtension)"
                let fileURL = outputDir.appendingPathComponent(fileName)
                do {
                    try data.write(to: fileURL)
                } catch {
                    NSLog("[PdfTools] Failed to write image %@: %@", fileName, error.localizedDescription)
                }

                let progress = Double(i + 1) / Double(pageCount)
                await MainActor.run { self?.state = .processing(progress: progress, description: "Exporting page \(i + 1) of \(pageCount)...") }
            }

            let result = OperationResult(
                message: "Exported \(pageCount) pages as \(format.displayName) images at \(dpi) DPI",
                outputPath: nil,
                outputDirectory: outputDir.path,
                inputSize: inputSize,
                outputSize: nil,
                fileCount: pageCount
            )
            await MainActor.run {
                self?.state = .completed(result: result)
                self?.addToHistory(operation: "PDF to Image", input: baseName, outputPath: nil, outputDirectory: outputDir.path, inputSize: inputSize, outputSize: nil, fileCount: pageCount)
            }
        }
    }

    func performImageToPdf() {
        guard !imageToPdfFiles.isEmpty else {
            state = .failed(message: "Select at least 1 image.")
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "Images.pdf"
        panel.message = "Save PDF"
        guard panel.runModal() == .OK, let outputURL = panel.url else { return }

        let files = imageToPdfFiles
        let totalInputSize = files.reduce(Int64(0)) { $0 + $1.fileSize }

        state = .processing(progress: 0, description: "Converting images to PDF...")
        currentTask = Task.detached { [weak self] in
            let outputDoc = PDFDocument()
            let total = files.count

            for (index, file) in files.enumerated() {
                guard !Task.isCancelled else {
                    await MainActor.run { self?.state = .idle }
                    return
                }

                guard let image = NSImage(contentsOf: file.url),
                      let page = PDFPage(image: image) else {
                    NSLog("[PdfTools] Failed to create PDF page from image: %@", file.name)
                    continue
                }

                outputDoc.insert(page, at: index)

                let progress = Double(index + 1) / Double(total)
                await MainActor.run { self?.state = .processing(progress: progress, description: "Converting image \(index + 1) of \(total)...") }
            }

            guard outputDoc.pageCount > 0 else {
                await MainActor.run { self?.state = .failed(message: "No images could be converted.") }
                return
            }

            guard outputDoc.write(to: outputURL) else {
                await MainActor.run { self?.state = .failed(message: "Failed to write PDF.") }
                return
            }

            let outputSize = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int64) ?? 0
            let result = OperationResult(
                message: "Created PDF with \(outputDoc.pageCount) page(s) from \(total) image(s)",
                outputPath: outputURL.path,
                outputDirectory: nil,
                inputSize: totalInputSize,
                outputSize: outputSize,
                fileCount: total
            )
            await MainActor.run {
                self?.state = .completed(result: result)
                self?.addToHistory(operation: "Image to PDF", input: "\(total) images", outputPath: outputURL.path, outputDirectory: nil, inputSize: totalInputSize, outputSize: outputSize, fileCount: total)
            }
        }
    }

    // MARK: - Cancel & Reset

    func cancelOperation() {
        currentTask?.cancel()
        currentTask = nil
        state = .idle
    }

    func resetState() {
        currentTask?.cancel()
        currentTask = nil
        state = .idle
    }

    // MARK: - History

    private func addToHistory(operation: String, input: String, outputPath: String?, outputDirectory: String?, inputSize: Int64?, outputSize: Int64?, fileCount: Int?) {
        let item = PdfOperationHistoryItem(
            id: UUID(),
            operation: operation,
            inputDescription: input,
            outputPath: outputPath,
            outputDirectory: outputDirectory,
            completedAt: Date(),
            inputSize: inputSize,
            outputSize: outputSize,
            fileCount: fileCount
        )
        operationHistory.insert(item, at: 0)
        if operationHistory.count > 20 {
            operationHistory = Array(operationHistory.prefix(20))
        }
        persistHistory()
    }

    func clearHistory() {
        operationHistory = []
        persistHistory()
    }

    private func persistHistory() {
        if let data = try? JSONEncoder().encode(operationHistory) {
            UserDefaults.standard.set(data, forKey: "pdfTools.operationHistory")
        }
    }

    func revealInFinder(_ path: String) {
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
    }

    // MARK: - Page Range Parsing

    private func parsePageRanges(_ text: String, maxPage: Int) -> [ClosedRange<Int>]? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        var ranges: [ClosedRange<Int>] = []
        let components = trimmed.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        for component in components {
            if component.contains("-") {
                let parts = component.split(separator: "-").map { $0.trimmingCharacters(in: .whitespaces) }
                guard parts.count == 2,
                      let start = Int(parts[0]),
                      let end = Int(parts[1]),
                      start >= 1, end >= start, end <= maxPage else {
                    return nil
                }
                ranges.append(start...end)
            } else {
                guard let page = Int(component), page >= 1, page <= maxPage else {
                    return nil
                }
                ranges.append(page...page)
            }
        }

        return ranges.isEmpty ? nil : ranges
    }
}
