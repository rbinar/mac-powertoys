import Foundation
import AppKit
import UniformTypeIdentifiers
#if canImport(WhisperKit)
import WhisperKit
#endif

enum WhisperModelOption: String, CaseIterable, Identifiable {
    case tiny
    case base
    case small
    case medium
    case largeV3

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tiny: return "Tiny"
        case .base: return "Base"
        case .small: return "Small"
        case .medium: return "Medium"
        case .largeV3: return "Large v3"
        }
    }

    var sizeHint: String {
        switch self {
        case .tiny: return "Fastest"
        case .base: return "Balanced"
        case .small: return "Better quality"
        case .medium: return "High quality"
        case .largeV3: return "Best quality"
        }
    }

    var whisperModelName: String {
        switch self {
        case .largeV3: return "large-v3"
        default: return rawValue
        }
    }
}

enum WhisperLanguageOption: String, CaseIterable, Identifiable {
    case auto
    case en, zh, de, es, ru, ko, fr, ja, pt, tr, pl, ca, nl, ar, sv, it, id, hi, fi, vi, he, uk, el, ms, cs, ro, da, hu, ta, no, th, ur, hr, bg, lt, la, ml, cy, sk, te, fa, lv, bn, sr, az, sl, kn, et, mk, br, eu, `is`, hy, ne, mn, bs, kk, sq, sw, gl, mr, pa, si, km, sn, yo, so, af, oc, ka, be, tg, sd, gu, am, yi, lo, uz, fo, ht, ps, tk, nn, mt, sa, lb, my, bo, tl, mg, `as`, tt, haw, ln, ha, ba, jw, su

    var id: String { rawValue }

    var displayName: String {
        if self == .auto { return "Auto" }
        if let name = Locale.current.localizedString(forLanguageCode: rawValue) {
            return name.localizedCapitalized
        }
        return rawValue.uppercased()
    }

    /// Returns the language code to pass to WhisperKit, or nil for auto-detect.
    var whisperLanguageCode: String? {
        self == .auto ? nil : rawValue
    }
}

@MainActor
final class SpeechToTextModel: ObservableObject {
    enum ViewState: Equatable {
        case idle
        case processing(String)
        case completed
        case error(String)
        
        static func == (lhs: ViewState, rhs: ViewState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.completed, .completed): return true
            case (.processing(let a), .processing(let b)): return a == b
            case (.error(let a), .error(let b)): return a == b
            default: return false
            }
        }
    }

    @Published var selectedModel: WhisperModelOption = .tiny {
        didSet {
            UserDefaults.standard.set(selectedModel.rawValue, forKey: Self.selectedModelKey)
            if selectedModel != loadedModel {
                isModelReady = false
            }
        }
    }
    @Published var selectedLanguage: WhisperLanguageOption = .auto {
        didSet {
            UserDefaults.standard.set(selectedLanguage.rawValue, forKey: Self.selectedLanguageKey)
        }
    }
    @Published var inputFileURL: URL?
    @Published var detectedLanguage: String = "Unknown"
    @Published var transcriptText: String = ""
    @Published var timestampedTranscriptText: String = ""
    @Published var statusMessage: String = "Pick an audio or video file to start."
    @Published var progress: Double = 0
    @Published var isBusy: Bool = false
    @Published var isModelReady: Bool = false
    @Published var viewState: ViewState = .idle
    @Published var isDragTargeted: Bool = false

    var canTranscribe: Bool { inputFileURL != nil && !isBusy && isModelReady }
    var availableModels: [WhisperModelOption] { WhisperModelOption.allCases }
    var availableLanguages: [WhisperLanguageOption] { WhisperLanguageOption.allCases }
    var hubStatusText: String {
        switch viewState {
        case .processing: return "Busy"
        case .error: return "Error"
        case .completed: return "Ready"
        case .idle: return isModelReady ? "Ready" : "Not ready"
        }
    }

    private static let selectedModelKey = "speechToText.selectedModel"
    private static let selectedLanguageKey = "speechToText.selectedLanguage"
    private var transcriptionTask: Task<Void, Never>?
    private var activeTranscriptionTaskID: UUID?

#if canImport(WhisperKit)
    private var whisperKit: WhisperKit?
    private var loadedModel: WhisperModelOption?
#endif

    init() {
        if let storedModel = UserDefaults.standard.string(forKey: Self.selectedModelKey),
           let option = WhisperModelOption(rawValue: storedModel) {
            selectedModel = option
        }
        if let storedLang = UserDefaults.standard.string(forKey: Self.selectedLanguageKey),
           let lang = WhisperLanguageOption(rawValue: storedLang) {
            selectedLanguage = lang
        }
    }

    func setInputFile(_ url: URL) {
        inputFileURL = url
        transcriptText = ""
        timestampedTranscriptText = ""
        detectedLanguage = "Unknown"
        progress = 0
        Task { await self.transcribeSelectedFile() }
    }

    func resetForNewFile() {
        inputFileURL = nil
        transcriptText = ""
        timestampedTranscriptText = ""
        detectedLanguage = "Unknown"
        statusMessage = "Pick an audio or video file to start."
        progress = 0
        isBusy = false
        viewState = .idle
    }

    func selectInputFile() {
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [
                .audio,
                .movie,
                .video,
                .mpeg4Movie,
                .quickTimeMovie,
                .wav,
                .mp3,
                .mpeg2Video,
                .aiff,
                .midi
            ]
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            panel.message = "Select an audio or video file to transcribe"
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

    func prepareModelIfNeeded() async {
        if isBusy { return }

#if canImport(WhisperKit)
        if isModelReady, loadedModel == selectedModel, whisperKit != nil {
            return
        }

        isBusy = true
        progress = 0.1
        statusMessage = "Preparing \(selectedModel.displayName) model..."
        viewState = .processing("Preparing \(selectedModel.displayName) model...")

        defer {
            isBusy = false
        }

        do {
            let config = WhisperKitConfig(model: selectedModel.whisperModelName)
            whisperKit = try await WhisperKit(config)
            loadedModel = selectedModel
            isModelReady = true
            progress = 1
            statusMessage = "Model ready: \(selectedModel.displayName)"
        } catch is CancellationError {
            return
        } catch {
            isModelReady = false
            whisperKit = nil
            loadedModel = nil
            progress = 0
            statusMessage = "Failed to prepare model: \(error.localizedDescription)"
            viewState = .error("Failed to prepare model: \(error.localizedDescription)")
        }
#else
        isModelReady = false
        statusMessage = "WhisperKit dependency is unavailable in this build."
#endif
    }

    func transcribeSelectedFile() async {
        guard let fileURL = inputFileURL else {
            statusMessage = "Select a file first."
            return
        }

        transcriptionTask?.cancel()

        let taskID = UUID()
        activeTranscriptionTaskID = taskID

        let task = Task { [weak self] in
            guard let self else { return }
            await self.performTranscription(for: fileURL, taskID: taskID)
        }

        transcriptionTask = task
        await task.value

        if activeTranscriptionTaskID == taskID {
            transcriptionTask = nil
            activeTranscriptionTaskID = nil
        }
    }

    func stopMonitoring() {
        transcriptionTask?.cancel()
        transcriptionTask = nil
        activeTranscriptionTaskID = nil

        isBusy = false
        progress = 0
        isDragTargeted = false
        viewState = .idle
        statusMessage = "Pick an audio or video file to start."

#if canImport(WhisperKit)
        whisperKit = nil
        loadedModel = nil
#endif
        isModelReady = false
    }

    private func isCurrentTranscriptionTask(_ taskID: UUID) -> Bool {
        activeTranscriptionTaskID == taskID && !Task.isCancelled
    }

    private func performTranscription(for fileURL: URL, taskID: UUID) async {
        guard isCurrentTranscriptionTask(taskID) else {
            return
        }

        viewState = .processing("Preparing model...")

        if !isModelReady {
            await prepareModelIfNeeded()
        }

#if canImport(WhisperKit)
        guard isCurrentTranscriptionTask(taskID) else {
            return
        }

        guard isModelReady, let whisperKit else {
            if statusMessage.isEmpty {
                statusMessage = "Model is not ready."
            }
            return
        }

        isBusy = true
        progress = 0.15
        statusMessage = "Transcribing \(fileURL.lastPathComponent)..."
        viewState = .processing("Transcribing \(fileURL.lastPathComponent)...")

        defer {
            if self.activeTranscriptionTaskID == taskID {
                self.isBusy = false
            }
        }

        do {
            let decodeOptions = DecodingOptions(language: selectedLanguage.whisperLanguageCode)
            let results = try await whisperKit.transcribe(audioPath: fileURL.path, decodeOptions: decodeOptions)

            guard isCurrentTranscriptionTask(taskID) else {
                return
            }

            progress = 0.85

            let plainText = buildPlainTranscript(from: results)
            transcriptText = plainText
            timestampedTranscriptText = buildTimestampedTranscript(from: results, fallback: plainText)
            detectedLanguage = extractLanguage(from: results) ?? "Unknown"

            progress = 1
            statusMessage = "Transcription completed."
            viewState = .completed
        } catch is CancellationError {
            return
        } catch {
            guard isCurrentTranscriptionTask(taskID) else {
                return
            }

            transcriptText = ""
            timestampedTranscriptText = ""
            detectedLanguage = "Unknown"
            progress = 0
            statusMessage = "Transcription failed: \(error.localizedDescription)"
            viewState = .error("Transcription failed: \(error.localizedDescription)")
        }
#else
        statusMessage = "WhisperKit dependency is unavailable in this build."
#endif
    }

    func copyTranscript() {
        let text = !timestampedTranscriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? timestampedTranscriptText
            : transcriptText

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusMessage = "There is no transcript to copy."
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        statusMessage = "Transcript copied to clipboard."
    }

    func saveTimestampedTranscript() {
        let text = !timestampedTranscriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? timestampedTranscriptText
            : transcriptText

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusMessage = "There is no transcript to save."
            return
        }

        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.plainText]
            let baseName = self.inputFileURL?.deletingPathExtension().lastPathComponent ?? "transcript"
            panel.nameFieldStringValue = "\(baseName)-transcript.txt"
            panel.message = "Choose where to save the transcript"
            panel.level = .floating

            panel.begin { response in
                DispatchQueue.main.async {
                    defer { Self.reopenMenuBarPanel() }

                    guard response == .OK, let destinationURL = panel.url else {
                        return
                    }

                    do {
                        try text.write(to: destinationURL, atomically: true, encoding: .utf8)
                        self.statusMessage = "Transcript saved to \(destinationURL.lastPathComponent)."
                    } catch {
                        self.statusMessage = "Failed to save transcript: \(error.localizedDescription)"
                    }
                }
            }
        }
    }

#if canImport(WhisperKit)
    private func buildPlainTranscript(from results: [TranscriptionResult]) -> String {
        let parts = results
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if !parts.isEmpty {
            return parts.joined(separator: "\n")
        }

        return ""
    }

    private func buildTimestampedTranscript(from results: [TranscriptionResult], fallback: String) -> String {
        var lines: [String] = []

        for result in results {
            for segment in result.segments {
                let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else {
                    continue
                }
                lines.append("[\(formatTimestamp(Double(segment.start))) - \(formatTimestamp(Double(segment.end)))] \(text)")
            }
        }

        if lines.isEmpty {
            return fallback
        }

        return lines.joined(separator: "\n")
    }

    private func extractLanguage(from results: [TranscriptionResult]) -> String? {
        return results
            .map { $0.language.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
    }
#endif

    private func formatTimestamp(_ value: Double) -> String {
        let totalMilliseconds = Int((value * 1000).rounded())
        let hours = totalMilliseconds / 3_600_000
        let minutes = (totalMilliseconds % 3_600_000) / 60_000
        let seconds = (totalMilliseconds % 60_000) / 1000
        let milliseconds = totalMilliseconds % 1000

        if hours > 0 {
            return String(format: "%02d:%02d:%02d.%03d", hours, minutes, seconds, milliseconds)
        }
        return String(format: "%02d:%02d.%03d", minutes, seconds, milliseconds)
    }

    private static func reopenMenuBarPanel() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let button = NSApp.windows
                .compactMap({ $0 as? NSPanel })
                .first(where: { $0.className.contains("StatusBarWindow") || $0.className.contains("MenuBarExtra") })?
                .value(forKey: "statusItem") as? NSStatusItem {
                button.button?.performClick(nil)
            } else {
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
}