import Foundation
import AVFoundation
import UniformTypeIdentifiers
import AppKit

// MARK: - Enums

enum VideoOutputFormat: String, CaseIterable, Identifiable {
    // Video formats
    case mp4 = "MP4"
    case mov = "MOV"
    case m4v = "M4V"
    case mkv = "MKV"
    case webm = "WEBM"
    case avi = "AVI"
    case flv = "FLV"
    case wmv = "WMV"
    case threeGP = "3GP"
    case gif = "GIF"
    
    // Audio extraction
    case mp3 = "MP3"
    case aac = "AAC"
    case wav = "WAV"
    case flac = "FLAC"
    case m4a = "M4A"
    case ogg = "OGG"
    
    var id: String { rawValue }
    
    var fileExtension: String {
        switch self {
        case .threeGP: return "3gp"
        default: return rawValue.lowercased()
        }
    }
    
    var isAudioOnly: Bool {
        switch self {
        case .mp3, .aac, .wav, .flac, .m4a, .ogg: return true
        default: return false
        }
    }
    
    var category: FormatCategory {
        switch self {
        case .gif: return .animated
        case .mp3, .aac, .wav, .flac, .m4a, .ogg: return .audio
        default: return .video
        }
    }
    
    var icon: String {
        switch category {
        case .video: return "film"
        case .audio: return "waveform"
        case .animated: return "photo.on.rectangle.angled"
        }
    }
    
    enum FormatCategory: String, CaseIterable, Identifiable {
        case video = "Video"
        case audio = "Audio"
        case animated = "Animated"
        var id: String { rawValue }
    }
}

enum VideoQualityPreset: String, CaseIterable, Identifiable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case highest = "Highest"
    
    var id: String { rawValue }
    
    var ffmpegCRF: Int {
        switch self {
        case .low: return 32
        case .medium: return 23
        case .high: return 18
        case .highest: return 12
        }
    }
    
    var ffmpegAudioQuality: Int {
        switch self {
        case .low: return 6
        case .medium: return 4
        case .high: return 2
        case .highest: return 0
        }
    }
    
    var ffmpegAudioBitrate: Int {
        switch self {
        case .low: return 96
        case .medium: return 128
        case .high: return 192
        case .highest: return 320
        }
    }
}

enum ResolutionPreset: String, CaseIterable, Identifiable {
    case original = "Original"
    case p2160 = "4K (2160p)"
    case p1440 = "1440p"
    case p1080 = "1080p"
    case p720 = "720p"
    case p480 = "480p"
    case p360 = "360p"
    
    var id: String { rawValue }
    
    var dimensions: (width: Int, height: Int)? {
        switch self {
        case .original: return nil
        case .p2160: return (3840, 2160)
        case .p1440: return (2560, 1440)
        case .p1080: return (1920, 1080)
        case .p720: return (1280, 720)
        case .p480: return (854, 480)
        case .p360: return (640, 360)
        }
    }
}

enum ConversionState: Equatable {
    case idle
    case analyzing
    case converting(progress: Double)
    case completed(outputPath: String)
    case failed(message: String)
    case cancelled
}

enum VideoConverterError: LocalizedError {
    case noInputFile
    case ffmpegNotAvailable
    case ffmpegProcessFailed(exitCode: Int32)
    case cancelled
    case outputLocationDenied
    case inputFileUnreadable
    
    var errorDescription: String? {
        switch self {
        case .noInputFile: return "No input file selected"
        case .ffmpegNotAvailable: return "FFmpeg is not installed"
        case .ffmpegProcessFailed(let code): return "FFmpeg exited with code \(code)"
        case .cancelled: return "Conversion was cancelled"
        case .outputLocationDenied: return "Cannot write to the output location"
        case .inputFileUnreadable: return "Cannot read the input file"
        }
    }
}

struct ConversionHistoryItem: Identifiable {
    let id = UUID()
    let inputName: String
    let outputPath: String
    let outputFormat: String
    let completedAt: Date
    let elapsedTime: TimeInterval
}

struct VideoMetadata: Equatable {
    let duration: TimeInterval
    let resolution: CGSize
    let codec: String
    let frameRate: Float
    let fileSize: Int64
    let hasAudioTrack: Bool
    let audioCodec: String?
    
    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var formattedResolution: String {
        "\(Int(resolution.width))×\(Int(resolution.height))"
    }
    
    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}

// MARK: - Model

@MainActor
final class VideoConverterModel: ObservableObject {
    
    // MARK: Input State
    @Published var inputFileURL: URL?
    @Published var inputMetadata: VideoMetadata?
    @Published var isDragTargeted: Bool = false
    
    // MARK: Conversion Settings
    @Published var selectedFormat: VideoOutputFormat = .mp4 {
        didSet {
            UserDefaults.standard.set(selectedFormat.rawValue, forKey: "videoConverter.format")
        }
    }
    @Published var selectedQuality: VideoQualityPreset = .high {
        didSet {
            UserDefaults.standard.set(selectedQuality.rawValue, forKey: "videoConverter.quality")
        }
    }
    @Published var selectedResolution: ResolutionPreset = .original {
        didSet {
            UserDefaults.standard.set(selectedResolution.rawValue, forKey: "videoConverter.resolution")
        }
    }
    @Published var selectedCategory: VideoOutputFormat.FormatCategory = .video
    
    // MARK: Conversion State
    @Published var conversionState: ConversionState = .idle
    @Published var elapsedTime: TimeInterval = 0
    
    // MARK: Engine Detection
    @Published private(set) var ffmpegAvailable: Bool = false
    @Published private(set) var ffmpegVersion: String?
    @Published private(set) var homebrewAvailable: Bool = false
    @Published private(set) var homebrewPath: String?
    @Published var isInstallingFFmpeg: Bool = false
    @Published var installLog: String = ""
    @Published var installFailed: Bool = false
    
    // MARK: History
    @Published var conversionHistory: [ConversionHistoryItem] = []
    
    // MARK: Private
    private var ffmpegBridge: FFmpegBridge?
    private var conversionTask: Task<Void, Never>?
    private var elapsedTimer: Timer?
    private var conversionStartTime: Date?
    
    // MARK: - Init
    
    init() {
        if let fmt = UserDefaults.standard.string(forKey: "videoConverter.format"),
           let format = VideoOutputFormat(rawValue: fmt) {
            self.selectedFormat = format
        }
        if let qual = UserDefaults.standard.string(forKey: "videoConverter.quality"),
           let quality = VideoQualityPreset(rawValue: qual) {
            self.selectedQuality = quality
        }
        if let res = UserDefaults.standard.string(forKey: "videoConverter.resolution"),
           let resolution = ResolutionPreset(rawValue: res) {
            self.selectedResolution = resolution
        }
        Task { [weak self] in
            self?.detectFFmpeg()
        }
    }
    
    // MARK: - FFmpeg Installation
    
    func installFFmpeg() {
        guard let brewPath = homebrewPath else { return }
        
        // Ensure helper script is installed first (silent install via entitlement)
        if !FFmpegBridge.isScriptInstalled() {
            do {
                try FFmpegBridge.ensureScript()
            } catch {
                // Silent install failed, try NSSavePanel as last resort
                if !FFmpegBridge.installScriptViaPanel() {
                    installFailed = true
                    installLog = "❌ Helper script setup cancelled. Required to install FFmpeg."
                    return
                }
            }
        }
        
        isInstallingFFmpeg = true
        installLog = "Starting FFmpeg installation...\n"
        installFailed = false
        
        FFmpegBridge.installViaHomebrew(
            brewPath: brewPath,
            outputHandler: { [weak self] line in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    // Keep only last ~20 lines to avoid UI bloat
                    let lines = self.installLog.components(separatedBy: "\n")
                    if lines.count > 20 {
                        self.installLog = lines.suffix(20).joined(separator: "\n")
                    }
                    self.installLog += line
                }
            },
            completion: { [weak self] success in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.isInstallingFFmpeg = false
                    if success {
                        self.installLog += "\n✅ FFmpeg installed successfully!"
                        self.detectFFmpeg()
                    } else {
                        self.installFailed = true
                        self.installLog += "\n❌ Installation failed."
                    }
                }
            }
        )
    }
    
    func retryDetection() {
        detectFFmpeg()
    }
    
    // MARK: - Public Methods
    
    func selectInputFile() {
        NSApp.activate(ignoringOtherApps: true)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.movie, .video, .audio, .mpeg4Movie, .quickTimeMovie, .avi, .mpeg2Video, .mp3, .wav, .aiff]
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            panel.message = "Select a video or audio file to convert"
            panel.level = .floating
            
            panel.begin { [weak self] response in
                DispatchQueue.main.async {
                    if response == .OK, let url = panel.url {
                        self?.setInputFile(url)
                    }
                    Self.reopenMenuBarPanel()
                }
            }
        }
    }
    
    func setInputFile(_ url: URL) {
        inputFileURL = url
        inputMetadata = nil
        conversionState = .idle
        
        Task {
            await analyzeInputFile(url)
        }
    }
    
    func startConversion() {
        guard let inputURL = inputFileURL else {
            conversionState = .failed(message: VideoConverterError.noInputFile.localizedDescription)
            return
        }
        guard let bridge = ffmpegBridge else {
            conversionState = .failed(message: VideoConverterError.ffmpegNotAvailable.localizedDescription)
            return
        }
        
        // Ensure helper script is installed (silent install via entitlement)
        if !FFmpegBridge.isScriptInstalled() {
            do {
                try FFmpegBridge.ensureScript()
            } catch {
                // Silent install failed, try NSSavePanel as last resort
                if !FFmpegBridge.installScriptViaPanel() {
                    conversionState = .failed(message: "Helper script is required to run FFmpeg. Please try again and click Install.")
                    return
                }
            }
        }
        
        NSApp.activate(ignoringOtherApps: true)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            // Show save panel
            let savePanel = NSSavePanel()
            savePanel.allowedContentTypes = [UTType(filenameExtension: self.selectedFormat.fileExtension) ?? .data]
            savePanel.nameFieldStringValue = inputURL.deletingPathExtension().lastPathComponent + "." + self.selectedFormat.fileExtension
            savePanel.message = "Choose where to save the converted file"
            savePanel.level = .floating
            
            savePanel.begin { [weak self] response in
                DispatchQueue.main.async {
                    if response == .OK, let outputURL = savePanel.url {
                        self?.runConversion(inputURL: inputURL, outputURL: outputURL)
                    }
                    Self.reopenMenuBarPanel()
                }
            }
        }
    }
    
    static func reopenMenuBarPanel() {
        // Find and reopen the MenuBarExtra panel
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let button = NSApp.windows
                .compactMap({ $0 as? NSPanel })
                .first(where: { $0.className.contains("StatusBarWindow") || $0.className.contains("MenuBarExtra") })?
                .value(forKey: "statusItem") as? NSStatusItem {
                button.button?.performClick(nil)
            } else {
                // Fallback: find status item button directly
                for window in NSApp.windows {
                    let className = String(describing: type(of: window))
                    if className.contains("MenuBarExtraWindow") || className.contains("_NSStatusBarWindow") {
                        window.makeKeyAndOrderFront(nil)
                        NSApp.activate(ignoringOtherApps: true)
                        return
                    }
                }
            }
        }
    }
    
    private func runConversion(inputURL: URL, outputURL: URL) {
        guard let bridge = ffmpegBridge else { return }
        
        conversionState = .converting(progress: 0)
        conversionStartTime = Date()
        startElapsedTimer()
        
        conversionTask = Task {
            do {
                let duration = inputMetadata?.duration ?? 0
                
                if selectedFormat == .gif {
                    try await bridge.convertGIF(
                        input: inputURL,
                        output: outputURL,
                        resolution: selectedResolution,
                        duration: duration,
                        progressHandler: { [weak self] progress in
                            Task { @MainActor [weak self] in
                                self?.conversionState = .converting(progress: progress)
                            }
                        }
                    )
                } else {
                    let args = bridge.buildArguments(
                        input: inputURL,
                        output: outputURL,
                        format: selectedFormat,
                        quality: selectedQuality,
                        resolution: selectedResolution
                    )
                    
                    try await bridge.convert(
                        input: inputURL,
                        output: outputURL,
                        arguments: args,
                        duration: duration,
                        progressHandler: { [weak self] progress in
                            Task { @MainActor [weak self] in
                                self?.conversionState = .converting(progress: progress)
                            }
                        }
                    )
                }
                
                stopElapsedTimer()
                let completedPath = outputURL.path
                
                // Add to history
                let historyItem = ConversionHistoryItem(
                    inputName: inputURL.lastPathComponent,
                    outputPath: completedPath,
                    outputFormat: selectedFormat.fileExtension.uppercased(),
                    completedAt: Date(),
                    elapsedTime: elapsedTime
                )
                conversionHistory.insert(historyItem, at: 0)
                
                // Reset for next conversion (keep settings)
                inputFileURL = nil
                inputMetadata = nil
                conversionState = .idle
                elapsedTime = 0
                conversionTask = nil
            } catch is CancellationError {
                stopElapsedTimer()
                conversionState = .cancelled
            } catch let error as VideoConverterError where error.errorDescription == VideoConverterError.cancelled.errorDescription {
                stopElapsedTimer()
                conversionState = .cancelled
            } catch {
                stopElapsedTimer()
                if conversionState == .cancelled { return }
                conversionState = .failed(message: error.localizedDescription)
            }
        }
    }
    
    func cancelConversion() {
        FFmpegBridge.cancelConversion()
        conversionTask?.cancel()
        conversionTask = nil
        stopElapsedTimer()
        conversionState = .cancelled
    }
    
    func revealInFinder(_ path: String) {
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
    }
    
    func reset() {
        inputFileURL = nil
        inputMetadata = nil
        conversionState = .idle
        elapsedTime = 0
        conversionTask = nil
    }
    
    func stopMonitoring() {
        cancelConversion()
    }
    
    var formattedElapsedTime: String {
        let minutes = Int(elapsedTime) / 60
        let seconds = Int(elapsedTime) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    // MARK: - Private Methods
    
    private func detectFFmpeg() {
        ffmpegAvailable = false
        ffmpegVersion = nil
        homebrewAvailable = false
        homebrewPath = nil

        // Helper script is auto-installed silently via the
        // home-relative-path.read-write entitlement for Application Scripts.
        // detect() / detectHomebrew() internally call ensureScript().
        Task.detached { [weak self] in
            let path = await FFmpegBridge.detect()
            NSLog("[VideoConverterModel] FFmpegBridge.detect() returned path: %@", path ?? "nil")
            var version: String?
            if let path {
                version = await FFmpegBridge(path: path).version()
            }
            let brewPath = await FFmpegBridge.detectHomebrew()

            await MainActor.run {
                guard let self else { return }
                if let path {
                    self.ffmpegBridge = FFmpegBridge(path: path)
                    self.ffmpegAvailable = true
                    self.ffmpegVersion = version
                }
                if let brewPath {
                    self.homebrewAvailable = true
                    self.homebrewPath = brewPath
                } else {
                    // Fallback: check brew via FileManager
                    let brewCandidates = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
                    for candidate in brewCandidates {
                        if FileManager.default.isExecutableFile(atPath: candidate) {
                            self.homebrewAvailable = true
                            self.homebrewPath = candidate
                            break
                        }
                    }
                }
            }
        }
    }
    
    private func analyzeInputFile(_ url: URL) async {
        conversionState = .analyzing
        
        let asset = AVURLAsset(url: url)
        
        do {
            let duration = try await asset.load(.duration)
            let tracks = try await asset.load(.tracks)
            
            var resolution = CGSize.zero
            var codec = "Unknown"
            var frameRate: Float = 0
            var hasAudio = false
            var audioCodec: String?
            
            for track in tracks {
                let mediaType = track.mediaType
                if mediaType == .video {
                    let size = try await track.load(.naturalSize)
                    let transform = try await track.load(.preferredTransform)
                    let transformed = size.applying(transform)
                    resolution = CGSize(width: abs(transformed.width), height: abs(transformed.height))
                    
                    let descriptions = try await track.load(.formatDescriptions)
                    if let desc = descriptions.first {
                        let formatDesc = desc as CMFormatDescription
                        let codecType = CMFormatDescriptionGetMediaSubType(formatDesc)
                        codec = fourCharCodeToString(codecType)
                    }
                    
                    frameRate = try await track.load(.nominalFrameRate)
                } else if mediaType == .audio {
                    hasAudio = true
                    let descriptions = try await track.load(.formatDescriptions)
                    if let desc = descriptions.first {
                        let formatDesc = desc as CMFormatDescription
                        let codecType = CMFormatDescriptionGetMediaSubType(formatDesc)
                        audioCodec = fourCharCodeToString(codecType)
                    }
                }
            }
            
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
            
            inputMetadata = VideoMetadata(
                duration: duration.seconds,
                resolution: resolution,
                codec: codec,
                frameRate: frameRate,
                fileSize: fileSize,
                hasAudioTrack: hasAudio,
                audioCodec: audioCodec
            )
            
            conversionState = .idle
        } catch {
            conversionState = .failed(message: "Failed to analyze file: \(error.localizedDescription)")
        }
    }
    
    private func fourCharCodeToString(_ code: FourCharCode) -> String {
        let bytes: [CChar] = [
            CChar(truncatingIfNeeded: (code >> 24) & 0xFF),
            CChar(truncatingIfNeeded: (code >> 16) & 0xFF),
            CChar(truncatingIfNeeded: (code >> 8) & 0xFF),
            CChar(truncatingIfNeeded: code & 0xFF),
            0
        ]
        return String(cString: bytes).trimmingCharacters(in: .whitespaces)
    }
    
    private func startElapsedTimer() {
        elapsedTime = 0
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let start = self.conversionStartTime else { return }
                self.elapsedTime = Date().timeIntervalSince(start)
            }
        }
    }
    
    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }
}
