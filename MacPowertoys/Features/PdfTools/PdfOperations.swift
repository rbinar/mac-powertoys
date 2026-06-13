import Foundation
import AppKit
import PDFKit

// MARK: - PdfOperations
//
// Pure, off-main-actor processing for each PDF operation. These types own ONLY
// the heavy lifting (PDF page work + file I/O); they hold no UI/published state.
//
// `PdfToolsModel` remains the @MainActor ObservableObject the views bind to: it
// owns published state, presents the NSOpenPanel/NSSavePanel, builds the inputs
// below, and drives progress/state. Each operation here runs inside the model's
// `Task.detached` and reports progress through a `@Sendable` callback, exactly
// matching the previous inline behavior (same progress fractions, same
// descriptions, same cancellation checks, same OperationResult payloads).

/// Outcome of an operation's processing pass. Cancellation is represented by
/// `.cancelled` so the model can transition to `.idle` (matching the prior
/// behavior where a cancelled task set `state = .idle`).
enum PdfOperationOutcome {
    case success(OperationResult)
    case failure(message: String)
    case cancelled
}

/// Progress reporter handed to each operation. The model supplies a closure that
/// hops back onto the main actor and sets `.processing(progress:description:)`.
/// It is `async` and awaited at each step so the worker stays in lockstep with
/// the UI update, matching the previous inline `await MainActor.run { ... }`.
typealias PdfProgressReporter = @Sendable (_ progress: Double, _ description: String) async -> Void

// MARK: - Merge

enum PdfMergeOperation {
    /// Mirrors the previous `performMerge()` detached-task body.
    static func run(
        files: [MergeFileItem],
        outputURL: URL,
        totalInputSize: Int64,
        reportProgress: PdfProgressReporter
    ) async -> PdfOperationOutcome {
        let outputDoc = PDFDocument()
        var pageIndex = 0
        let totalPages = files.reduce(0) { $0 + $1.pageCount }

        for file in files {
            guard !Task.isCancelled else { return .cancelled }
            guard let doc = PDFDocument(url: file.url) else {
                return .failure(message: "Failed to open \(file.name)")
            }
            if doc.isEncrypted && doc.isLocked {
                return .failure(message: "\(file.name) is password protected. Open it individually first.")
            }
            for i in 0..<doc.pageCount {
                guard !Task.isCancelled else { return .cancelled }
                if let page = doc.page(at: i) {
                    outputDoc.insert(page, at: pageIndex)
                    pageIndex += 1
                }
                let progress = Double(pageIndex) / Double(totalPages)
                await reportProgress(progress, "Merging page \(pageIndex) of \(totalPages)...")
            }
        }

        guard outputDoc.write(to: outputURL) else {
            return .failure(message: "Failed to write merged PDF.")
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
        return .success(result)
    }
}

// MARK: - Split

enum PdfSplitOperation {
    /// Mirrors the previous `performSplit()` detached-task body.
    static func run(
        doc: PDFDocument,
        splitRanges: [[Int]],
        mode: SplitMode,
        baseName: String,
        outputDir: URL,
        inputSize: Int64,
        reportProgress: PdfProgressReporter
    ) async -> PdfOperationOutcome {
        let total = splitRanges.count
        var filesWritten = 0

        for (index, pageIndices) in splitRanges.enumerated() {
            guard !Task.isCancelled else { return .cancelled }

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
                return .failure(message: "Failed to write \(fileName)")
            }
            filesWritten += 1

            let progress = Double(index + 1) / Double(total)
            await reportProgress(progress, "Writing file \(index + 1) of \(total)...")
        }

        let result = OperationResult(
            message: "Split into \(filesWritten) files",
            outputPath: nil,
            outputDirectory: outputDir.path,
            inputSize: inputSize,
            outputSize: nil,
            fileCount: filesWritten
        )
        return .success(result)
    }
}

// MARK: - Compress

enum PdfCompressOperation {
    /// Mirrors the previous `performCompress()` detached-task body.
    static func run(
        doc: PDFDocument,
        pageCount: Int,
        quality: CompressQuality,
        outputURL: URL,
        inputSize: Int64,
        reportProgress: PdfProgressReporter
    ) async -> PdfOperationOutcome {
        let outputDoc = PDFDocument()

        for i in 0..<pageCount {
            guard !Task.isCancelled else { return .cancelled }

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
            await reportProgress(progress, "Compressing page \(i + 1) of \(pageCount)...")
        }

        guard outputDoc.write(to: outputURL) else {
            return .failure(message: "Failed to write compressed PDF.")
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
        return .success(result)
    }
}

// MARK: - Rotate

enum PdfRotateOperation {
    /// Mirrors the previous `performRotate()` detached-task body.
    static func run(
        doc: PDFDocument,
        pageCount: Int,
        targetSet: Set<Int>,
        angle: RotationAngle,
        outputURL: URL,
        inputSize: Int64,
        reportProgress: PdfProgressReporter
    ) async -> PdfOperationOutcome {
        for i in 0..<pageCount {
            guard !Task.isCancelled else { return .cancelled }

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
            await reportProgress(progress, "Rotating page \(i + 1) of \(pageCount)...")
        }

        guard doc.write(to: outputURL) else {
            return .failure(message: "Failed to write rotated PDF.")
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
        return .success(result)
    }
}

// MARK: - PDF to Image

enum PdfToImageOperation {
    /// Mirrors the previous `performPdfToImage()` detached-task body.
    static func run(
        doc: PDFDocument,
        pageCount: Int,
        format: ImageExportFormat,
        dpi: Int,
        baseName: String,
        outputDir: URL,
        inputSize: Int64,
        reportProgress: PdfProgressReporter
    ) async -> PdfOperationOutcome {
        let scale = CGFloat(dpi) / 72.0

        for i in 0..<pageCount {
            guard !Task.isCancelled else { return .cancelled }

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
            await reportProgress(progress, "Exporting page \(i + 1) of \(pageCount)...")
        }

        let result = OperationResult(
            message: "Exported \(pageCount) pages as \(format.displayName) images at \(dpi) DPI",
            outputPath: nil,
            outputDirectory: outputDir.path,
            inputSize: inputSize,
            outputSize: nil,
            fileCount: pageCount
        )
        return .success(result)
    }
}

// MARK: - Image to PDF

enum PdfImageToPdfOperation {
    /// Mirrors the previous `performImageToPdf()` detached-task body.
    static func run(
        files: [MergeFileItem],
        outputURL: URL,
        totalInputSize: Int64,
        reportProgress: PdfProgressReporter
    ) async -> PdfOperationOutcome {
        let outputDoc = PDFDocument()
        let total = files.count

        for (index, file) in files.enumerated() {
            guard !Task.isCancelled else { return .cancelled }

            guard let image = NSImage(contentsOf: file.url),
                  let page = PDFPage(image: image) else {
                NSLog("[PdfTools] Failed to create PDF page from image: %@", file.name)
                continue
            }

            outputDoc.insert(page, at: index)

            let progress = Double(index + 1) / Double(total)
            await reportProgress(progress, "Converting image \(index + 1) of \(total)...")
        }

        guard outputDoc.pageCount > 0 else {
            return .failure(message: "No images could be converted.")
        }

        guard outputDoc.write(to: outputURL) else {
            return .failure(message: "Failed to write PDF.")
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
        return .success(result)
    }
}
