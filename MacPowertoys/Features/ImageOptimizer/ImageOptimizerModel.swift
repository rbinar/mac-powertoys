import Foundation
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - Supporting Types

enum ImageOutputFormat: String, CaseIterable, Identifiable {
    case original = "Original"
    case jpeg = "JPEG"
    case png = "PNG"
    case webp = "WebP"

    var id: String { rawValue }

    var fileExtension: String? {
        switch self {
        case .original: return nil
        case .jpeg: return "jpg"
        case .png: return "png"
        case .webp: return "webp"
        }
    }

    var utType: UTType? {
        switch self {
        case .original: return nil
        case .jpeg: return .jpeg
        case .png: return .png
        case .webp: return .webP
        }
    }
}

enum ResizeMode: String, CaseIterable, Identifiable {
    case pixels = "Pixels"
    case percent = "Percent"

    var id: String { rawValue }
}

enum ImageOptimizerState: Equatable {
    case idle
    case processing(progress: Double, message: String)
    case completed(totalSaved: Int64, fileCount: Int)
    case failed(message: String)
}

struct ImageItem: Identifiable {
    let id: UUID
    let url: URL
    let originalSize: Int64
    var outputURL: URL?
    var outputSize: Int64?
    var error: String?

    var name: String { url.lastPathComponent }
    var isProcessed: Bool { outputURL != nil || error != nil }

    var savedBytes: Int64 { max(0, originalSize - (outputSize ?? originalSize)) }

    var savingsDescription: String {
        let original = ByteCountFormatter.string(fromByteCount: originalSize, countStyle: .file)
        guard let outSize = outputSize else { return original }
        let output = ByteCountFormatter.string(fromByteCount: outSize, countStyle: .file)
        let saved = originalSize - outSize
        guard originalSize > 0 else { return "\(original) → \(output)" }
        let percent = Int(round(Double(saved) / Double(originalSize) * 100))
        return "\(original) → \(output) (-\(percent)%)"
    }
}

// MARK: - Model

@MainActor
final class ImageOptimizerModel: ObservableObject {

    // MARK: - Settings

    @Published var outputFormat: ImageOutputFormat {
        didSet { UserDefaults.standard.set(outputFormat.rawValue, forKey: "imageOptimizer.outputFormat") }
    }

    @Published var compressionQuality: Double {
        didSet { UserDefaults.standard.set(compressionQuality, forKey: "imageOptimizer.compressionQuality") }
    }

    @Published var shouldResize: Bool {
        didSet { UserDefaults.standard.set(shouldResize, forKey: "imageOptimizer.shouldResize") }
    }

    @Published var resizeMode: ResizeMode {
        didSet { UserDefaults.standard.set(resizeMode.rawValue, forKey: "imageOptimizer.resizeMode") }
    }

    @Published var resizeWidth: Int {
        didSet { UserDefaults.standard.set(resizeWidth, forKey: "imageOptimizer.resizeWidth") }
    }

    @Published var resizeHeight: Int {
        didSet { UserDefaults.standard.set(resizeHeight, forKey: "imageOptimizer.resizeHeight") }
    }

    @Published var resizePercent: Int {
        didSet { UserDefaults.standard.set(resizePercent, forKey: "imageOptimizer.resizePercent") }
    }

    @Published var maintainAspectRatio: Bool {
        didSet { UserDefaults.standard.set(maintainAspectRatio, forKey: "imageOptimizer.maintainAspectRatio") }
    }

    // MARK: - Runtime State

    @Published private(set) var items: [ImageItem] = []
    @Published private(set) var state: ImageOptimizerState = .idle
    @Published var isDragTargeted: Bool = false

    // MARK: - Private

    private var currentTask: Task<Void, Never>?

    // MARK: - Init

    init() {
        if let raw = UserDefaults.standard.string(forKey: "imageOptimizer.outputFormat"),
           let format = ImageOutputFormat(rawValue: raw) {
            outputFormat = format
        } else {
            outputFormat = .original
        }

        let quality = UserDefaults.standard.double(forKey: "imageOptimizer.compressionQuality")
        compressionQuality = quality > 0 ? quality : 0.8

        shouldResize = UserDefaults.standard.bool(forKey: "imageOptimizer.shouldResize")

        if let raw = UserDefaults.standard.string(forKey: "imageOptimizer.resizeMode"),
           let mode = ResizeMode(rawValue: raw) {
            resizeMode = mode
        } else {
            resizeMode = .pixels
        }

        let width = UserDefaults.standard.integer(forKey: "imageOptimizer.resizeWidth")
        resizeWidth = width > 0 ? width : 1920

        let height = UserDefaults.standard.integer(forKey: "imageOptimizer.resizeHeight")
        resizeHeight = height > 0 ? height : 1080

        let percent = UserDefaults.standard.integer(forKey: "imageOptimizer.resizePercent")
        resizePercent = percent > 0 ? percent : 50

        if UserDefaults.standard.object(forKey: "imageOptimizer.maintainAspectRatio") != nil {
            maintainAspectRatio = UserDefaults.standard.bool(forKey: "imageOptimizer.maintainAspectRatio")
        } else {
            maintainAspectRatio = true
        }
    }

    // MARK: - Lifecycle

    func stopMonitoring() {
        currentTask?.cancel()
        currentTask = nil
    }

    // MARK: - Input

    func selectImages() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.jpeg, .png, .webP, .heic]
        panel.message = "Select images to optimize"
        let response = panel.runModal()
        if response == .OK {
            addImages(panel.urls)
        }
        NotificationCenter.default.post(name: NSNotification.Name("ShowImageOptimizer"), object: nil)
    }

    func addImages(_ urls: [URL]) {
        let allowed = Set(["jpg", "jpeg", "png", "webp", "heic"])
        let existing = Set(items.map { $0.url })
        for url in urls {
            guard allowed.contains(url.pathExtension.lowercased()) else { continue }
            guard !existing.contains(url) else { continue }
            let size = fileSize(url)
            items.append(ImageItem(id: UUID(), url: url, originalSize: size))
        }
    }

    func removeItem(_ item: ImageItem) {
        items.removeAll { $0.id == item.id }
    }

    func clearAll() {
        items = []
        state = .idle
    }

    func reset() {
        items = []
        state = .idle
    }

    // MARK: - Processing

    func process() {
        guard !items.isEmpty else { return }

        for i in items.indices {
            items[i].outputURL = nil
            items[i].outputSize = nil
            items[i].error = nil
        }

        state = .processing(progress: 0, message: "Preparing...")

        let snapshot = items

        let quality = compressionQuality
        let doResize = shouldResize
        let mode = resizeMode
        let targetWidth = resizeWidth
        let targetHeight = resizeHeight
        let targetPercent = resizePercent
        let keepAspect = maintainAspectRatio
        let format = outputFormat

        currentTask = Task.detached(priority: .userInitiated) { [weak self] in
            var totalSaved: Int64 = 0

            for (idx, item) in snapshot.enumerated() {
                guard !Task.isCancelled else {
                    await MainActor.run { self?.state = .idle }
                    return
                }

                await MainActor.run {
                    self?.state = .processing(
                        progress: Double(idx) / Double(snapshot.count),
                        message: "Processing \(item.name)..."
                    )
                }

                do {
                    let (outputURL, outputSize) = try ImageOptimizerModel.compressImage(
                        item: item,
                        quality: quality,
                        doResize: doResize,
                        resizeMode: mode,
                        resizeWidth: targetWidth,
                        resizeHeight: targetHeight,
                        resizePercent: targetPercent,
                        maintainAspectRatio: keepAspect,
                        outputFormat: format
                    )
                    let saved = item.originalSize - outputSize
                    totalSaved += max(0, saved)
                    await MainActor.run {
                        if let i = self?.items.firstIndex(where: { $0.id == item.id }) {
                            self?.items[i].outputURL = outputURL
                            self?.items[i].outputSize = outputSize
                        }
                    }
                } catch {
                    await MainActor.run {
                        if let i = self?.items.firstIndex(where: { $0.id == item.id }) {
                            self?.items[i].error = error.localizedDescription
                        }
                    }
                }
            }

            await MainActor.run {
                self?.state = .completed(totalSaved: totalSaved, fileCount: snapshot.count)
            }
        }
    }

    nonisolated private static func compressImage(
        item: ImageItem,
        quality: Double,
        doResize: Bool,
        resizeMode: ResizeMode,
        resizeWidth: Int,
        resizeHeight: Int,
        resizePercent: Int,
        maintainAspectRatio: Bool,
        outputFormat: ImageOutputFormat
    ) throws -> (URL, Int64) {
        guard let source = CGImageSourceCreateWithURL(item.url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ImageOptimizerError.cannotReadImage
        }

        let finalImage = resizeImageIfNeeded(
            cgImage,
            doResize: doResize,
            resizeMode: resizeMode,
            resizeWidth: resizeWidth,
            resizeHeight: resizeHeight,
            resizePercent: resizePercent,
            maintainAspectRatio: maintainAspectRatio
        )

        let outputURL = buildOutputURL(for: item.url, outputFormat: outputFormat)
        let destType = resolveUTType(for: item.url, outputFormat: outputFormat)

        guard let dest = CGImageDestinationCreateWithURL(outputURL as CFURL, destType.identifier as CFString, 1, nil) else {
            throw ImageOptimizerError.cannotCreateDestination
        }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality
        ]
        CGImageDestinationAddImage(dest, finalImage, options as CFDictionary)

        guard CGImageDestinationFinalize(dest) else {
            throw ImageOptimizerError.cannotWriteImage
        }

        let outSize = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int64) ?? 0
        return (outputURL, outSize)
    }

    // MARK: - Helpers

    nonisolated private static func resizeImageIfNeeded(
        _ image: CGImage,
        doResize: Bool,
        resizeMode: ResizeMode,
        resizeWidth: Int,
        resizeHeight: Int,
        resizePercent: Int,
        maintainAspectRatio: Bool
    ) -> CGImage {
        guard doResize else { return image }

        let srcWidth = image.width
        let srcHeight = image.height

        let targetW: Int
        let targetH: Int

        switch resizeMode {
        case .pixels:
            if maintainAspectRatio {
                let scaleX = Double(resizeWidth) / Double(srcWidth)
                let scaleY = Double(resizeHeight) / Double(srcHeight)
                let scale = min(scaleX, scaleY)
                targetW = max(1, Int(Double(srcWidth) * scale))
                targetH = max(1, Int(Double(srcHeight) * scale))
            } else {
                targetW = resizeWidth
                targetH = resizeHeight
            }
        case .percent:
            let scale = Double(resizePercent) / 100.0
            targetW = max(1, Int(Double(srcWidth) * scale))
            targetH = max(1, Int(Double(srcHeight) * scale))
        }

        if targetW == srcWidth && targetH == srcHeight { return image }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard let context = CGContext(
            data: nil,
            width: targetW,
            height: targetH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else { return image }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: targetW, height: targetH))

        return context.makeImage() ?? image
    }

    nonisolated private static func buildOutputURL(for inputURL: URL, outputFormat: ImageOutputFormat) -> URL {
        let stem = inputURL.deletingPathExtension().lastPathComponent
        let ext: String
        switch outputFormat {
        case .original: ext = inputURL.pathExtension
        case .jpeg: ext = "jpg"
        case .png: ext = "png"
        case .webp: ext = "webp"
        }
        let filename = "\(stem)_optimized.\(ext)"
        return inputURL.deletingLastPathComponent().appendingPathComponent(filename)
    }

    nonisolated private static func resolveUTType(for inputURL: URL, outputFormat: ImageOutputFormat) -> UTType {
        switch outputFormat {
        case .original:
            let ext = inputURL.pathExtension.lowercased()
            if ext == "jpg" || ext == "jpeg" { return .jpeg }
            if ext == "png" { return .png }
            if ext == "webp" { return .webP }
            if ext == "heic" { return .heic }
            return .jpeg
        case .jpeg: return .jpeg
        case .png: return .png
        case .webp: return .webP
        }
    }

    // MARK: - Estimation

    var estimatedOutputSize: Int64 {
        guard !items.isEmpty else { return 0 }
        let totalOriginal = items.reduce(Int64(0)) { $0 + $1.originalSize }

        let qualityFactor: Double
        switch outputFormat {
        case .original:
            qualityFactor = compressionQuality * 0.9
        case .jpeg:
            qualityFactor = compressionQuality * 0.85
        case .png:
            qualityFactor = 0.9
        case .webp:
            qualityFactor = compressionQuality * 0.70
        }

        let resizeFactor: Double
        if shouldResize {
            switch resizeMode {
            case .percent:
                let scale = Double(resizePercent) / 100.0
                resizeFactor = scale * scale
            case .pixels:
                resizeFactor = 0.5
            }
        } else {
            resizeFactor = 1.0
        }

        return Int64(Double(totalOriginal) * qualityFactor * resizeFactor)
    }

    var estimatedSavingsDescription: String {
        guard !items.isEmpty else { return "" }
        let totalOriginal = items.reduce(Int64(0)) { $0 + $1.originalSize }
        let estimated = estimatedOutputSize
        let originalStr = ByteCountFormatter.string(fromByteCount: totalOriginal, countStyle: .file)
        let estimatedStr = ByteCountFormatter.string(fromByteCount: estimated, countStyle: .file)
        let saved = totalOriginal - estimated
        guard totalOriginal > 0 else { return "" }
        let percent = Int(round(Double(saved) / Double(totalOriginal) * 100))
        if percent <= 0 {
            return "\(originalStr) → ~\(estimatedStr)"
        }
        return "\(originalStr) → ~\(estimatedStr) (-\(percent)%)"
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func fileSize(_ url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
    }
}

// MARK: - Errors

enum ImageOptimizerError: LocalizedError {
    case cannotReadImage
    case cannotCreateDestination
    case cannotWriteImage

    var errorDescription: String? {
        switch self {
        case .cannotReadImage: return "Cannot read image file"
        case .cannotCreateDestination: return "Cannot create output destination"
        case .cannotWriteImage: return "Failed to write optimized image"
        }
    }
}
