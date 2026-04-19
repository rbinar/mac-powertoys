import Foundation
import AppKit
import UniformTypeIdentifiers

/// Sandbox-compatible FFmpeg bridge using NSUserUnixTask.
/// Scripts run in ~/Library/Application Scripts/<bundle-id>/ — outside the sandbox.
final class FFmpegBridge: Sendable {
    let path: String
    
    init(path: String) {
        self.path = path
    }
    
    // MARK: - Script Management
    
    private static let scriptName = "ffmpeg-runner.sh"
    private static let scriptVersion = "v4"
    
    private static var scriptDirectory: URL? {
        FileManager.default.urls(for: .applicationScriptsDirectory, in: .userDomainMask).first
    }
    
    @discardableResult
    static func ensureScript() throws -> URL {
        guard let dir = scriptDirectory else {
            NSLog("[FFmpegBridge] Application Scripts directory not available")
            throw NSError(domain: "FFmpegBridge", code: 1, userInfo: [NSLocalizedDescriptionKey: "Application Scripts directory not available"])
        }
        
        let url = dir.appendingPathComponent(scriptName)
        NSLog("[FFmpegBridge] Script target: %@", url.path)
        
        // Check if already installed and current version
        if FileManager.default.fileExists(atPath: url.path),
           let content = try? String(contentsOf: url, encoding: .utf8),
           content.contains("# \(scriptVersion)") {
            NSLog("[FFmpegBridge] Script already installed and current")
            return url
        }
        
        if !FileManager.default.fileExists(atPath: dir.path) {
            NSLog("[FFmpegBridge] Creating directory: %@", dir.path)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        
        NSLog("[FFmpegBridge] Writing script to: %@", url.path)
        try scriptContent.write(to: url, atomically: true, encoding: .utf8)
        
        // IMPORTANT: App Sandbox automatically adds com.apple.quarantine to files written by the app.
        // NSUserUnixTask will fail to execute the script with "Unknown interpreter" if quarantine is present.
        // We must remove the quarantine attribute immediately after writing.
        removexattr(url.path, "com.apple.quarantine", 0)
        
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        NSLog("[FFmpegBridge] Script installed successfully")
        return url
    }
    
    // Shell script that runs OUTSIDE the sandbox via NSUserUnixTask
    private static let scriptContent: String = """
        #!/bin/bash
        # \(scriptVersion) - MacPowerToys FFmpeg Runner
        
        CMD="${1:-}"
        shift 2>/dev/null || true
        
        PID_FILE="/tmp/macpowertoys-ffmpeg.pid"
        
        case "$CMD" in
            detect)
                for p in /opt/homebrew/bin/ffmpeg /usr/local/bin/ffmpeg; do
                    if [ -x "$p" ] && "$p" -version >/dev/null 2>&1; then
                        echo "$p"
                        exit 0
                    fi
                done
                exit 1
                ;;
            detect-brew)
                for p in /opt/homebrew/bin/brew /usr/local/bin/brew; do
                    if [ -x "$p" ]; then
                        echo "$p"
                        exit 0
                    fi
                done
                exit 1
                ;;
            version)
                "$1" -version 2>/dev/null | head -1
                ;;
            convert)
                FFMPEG="$1"
                shift
                "$FFMPEG" "$@" &
                FFMPEG_PID=$!
                echo "$FFMPEG_PID" > "$PID_FILE"
                wait "$FFMPEG_PID"
                EXIT_CODE=$?
                rm -f "$PID_FILE"
                exit $EXIT_CODE
                ;;
            cancel)
                if [ -f "$PID_FILE" ]; then
                    kill "$(cat "$PID_FILE")" 2>/dev/null || true
                    rm -f "$PID_FILE"
                fi
                ;;
            install)
                BREW="$1"
                HOMEBREW_NO_AUTO_UPDATE=1 "$BREW" install ffmpeg 2>&1
                ;;
            *)
                echo "Unknown command: $CMD" >&2
                exit 1
                ;;
        esac
        """
    
    // MARK: - Script Status
    
    static func isScriptInstalled() -> Bool {
        guard let dir = scriptDirectory else { return false }
        let url = dir.appendingPathComponent(scriptName)
        if FileManager.default.fileExists(atPath: url.path),
           let content = try? String(contentsOf: url, encoding: .utf8),
           content.contains("# \(scriptVersion)") {
            return true
        }
        return false
    }
    
    @MainActor
    static func installScriptViaPanel() -> Bool {
        guard let dir = scriptDirectory else { return false }
        
        let savePanel = NSSavePanel()
        savePanel.directoryURL = dir
        savePanel.nameFieldStringValue = scriptName
        savePanel.allowedContentTypes = [.shellScript]
        savePanel.message = "MacPowerToys needs to install a helper script for video conversion.\nClick Save to allow."
        savePanel.prompt = "Install"
        savePanel.canCreateDirectories = true
        
        guard savePanel.runModal() == .OK, let url = savePanel.url else {
            return false
        }
        
        do {
            try scriptContent.write(to: url, atomically: true, encoding: .utf8)
        
        // Ensure quarantine attribute is removed so NSUserUnixTask can execute it
        removexattr(url.path, "com.apple.quarantine", 0)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            NSLog("[FFmpegBridge] Script installed via panel to: %@", url.path)
            return true
        } catch {
            NSLog("[FFmpegBridge] Failed to write script via panel: %@", error.localizedDescription)
            return false
        }
    }
    
    // MARK: - Detection (Static, Async)
    
    static func detect() async -> String? {
        do {
            let scriptURL = try ensureScript()
            return await withCheckedContinuation { continuation in
                do {
                    let task = try NSUserUnixTask(url: scriptURL)
                    let outPipe = Pipe()
                    task.standardOutput = outPipe.fileHandleForWriting
                    
                    task.execute(withArguments: ["detect"]) { error in
                        outPipe.fileHandleForWriting.closeFile()
                        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                        let path = String(data: data, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if let error { NSLog("[FFmpegBridge] detect task error: %@", error.localizedDescription) }
                        NSLog("[FFmpegBridge] detect result: %@", path ?? "nil")
                        continuation.resume(returning: (path?.isEmpty == false) ? path : nil)
                    }
                } catch {
                    NSLog("[FFmpegBridge] detect NSUserUnixTask init error: %@", error.localizedDescription)
                    continuation.resume(returning: nil)
                }
            }
        } catch {
            NSLog("[FFmpegBridge] detect ensureScript error: %@", error.localizedDescription)
            return nil
        }
    }
    
    static func detectHomebrew() async -> String? {
        guard let scriptURL = try? ensureScript() else { return nil }
        
        return await withCheckedContinuation { continuation in
            do {
                let task = try NSUserUnixTask(url: scriptURL)
                let outPipe = Pipe()
                task.standardOutput = outPipe.fileHandleForWriting
                
                task.execute(withArguments: ["detect-brew"]) { _ in
                    outPipe.fileHandleForWriting.closeFile()
                    let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                    let path = String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(returning: (path?.isEmpty == false) ? path : nil)
                }
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }
    
    // MARK: - Installation
    
    static func installViaHomebrew(
        brewPath: String,
        outputHandler: @escaping @Sendable (String) -> Void,
        completion: @escaping @Sendable (Bool) -> Void
    ) {
        guard let scriptURL = try? ensureScript() else {
            outputHandler("Failed to set up script runner\n")
            completion(false)
            return
        }
        
        do {
            let task = try NSUserUnixTask(url: scriptURL)
            let outPipe = Pipe()
            task.standardOutput = outPipe.fileHandleForWriting
            task.standardError = outPipe.fileHandleForWriting
            
            outPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }
                outputHandler(line)
            }
            
            task.execute(withArguments: ["install", brewPath]) { error in
                outPipe.fileHandleForWriting.closeFile()
                outPipe.fileHandleForReading.readabilityHandler = nil
                completion(error == nil)
            }
        } catch {
            outputHandler("Failed to start: \(error.localizedDescription)\n")
            completion(false)
        }
    }
    
    // MARK: - Version
    
    func version() async -> String? {
        guard let scriptURL = try? FFmpegBridge.ensureScript() else { return nil }
        
        return await withCheckedContinuation { continuation in
            do {
                let task = try NSUserUnixTask(url: scriptURL)
                let outPipe = Pipe()
                task.standardOutput = outPipe.fileHandleForWriting
                
                task.execute(withArguments: ["version", path]) { _ in
                    outPipe.fileHandleForWriting.closeFile()
                    let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(returning: (output?.isEmpty == false) ? output : nil)
                }
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }
    
    // MARK: - Argument Building
    
    func buildArguments(
        input: URL,
        output: URL,
        format: VideoOutputFormat,
        quality: VideoQualityPreset,
        resolution: ResolutionPreset
    ) -> [String] {
        var args = ["-i", input.path, "-y"]
        
        // Resolution filter
        if let dims = resolution.dimensions {
            args += ["-vf", "scale=\(dims.width):-2"]
        }
        
        switch format {
        case .mp4:
            args += ["-c:v", "libx264", "-crf", "\(quality.ffmpegCRF)", "-preset", "medium", "-c:a", "aac", "-b:a", "192k"]
        case .mov:
            args += ["-c:v", "libx264", "-crf", "\(quality.ffmpegCRF)", "-preset", "medium", "-c:a", "aac", "-b:a", "192k", "-f", "mov"]
        case .m4v:
            args += ["-c:v", "libx264", "-crf", "\(quality.ffmpegCRF)", "-preset", "medium", "-c:a", "aac", "-b:a", "192k", "-f", "mp4"]
        case .mkv:
            args += ["-c:v", "libx264", "-crf", "\(quality.ffmpegCRF)", "-preset", "medium", "-c:a", "aac", "-b:a", "192k"]
        case .webm:
            args += ["-c:v", "libvpx-vp9", "-crf", "\(quality.ffmpegCRF)", "-b:v", "0", "-c:a", "libopus", "-b:a", "128k"]
        case .avi:
            args += ["-c:v", "mpeg4", "-q:v", "\(max(2, quality.ffmpegCRF / 3))", "-c:a", "mp3", "-b:a", "192k"]
        case .flv:
            args += ["-c:v", "libx264", "-crf", "\(quality.ffmpegCRF)", "-c:a", "aac", "-b:a", "128k", "-f", "flv"]
        case .wmv:
            args += ["-c:v", "wmv2", "-q:v", "\(max(2, quality.ffmpegCRF / 3))", "-c:a", "wmav2", "-b:a", "192k"]
        case .threeGP:
            args += ["-c:v", "libx264", "-crf", "\(quality.ffmpegCRF)", "-profile:v", "baseline", "-level", "3.0", "-c:a", "aac", "-b:a", "64k", "-ac", "1", "-ar", "22050", "-f", "3gp"]
        case .gif:
            break
        case .mp3:
            args += ["-vn", "-c:a", "libmp3lame", "-q:a", "\(quality.ffmpegAudioQuality)"]
        case .aac:
            args += ["-vn", "-c:a", "aac", "-b:a", "\(quality.ffmpegAudioBitrate)k"]
        case .wav:
            args += ["-vn", "-c:a", "pcm_s16le"]
        case .flac:
            args += ["-vn", "-c:a", "flac"]
        case .m4a:
            args += ["-vn", "-c:a", "aac", "-b:a", "\(quality.ffmpegAudioBitrate)k"]
        case .ogg:
            args += ["-vn", "-c:a", "libvorbis", "-q:a", "\(quality.ffmpegAudioQuality)"]
        }
        
        args.append(output.path)
        return args
    }
    
    // MARK: - GIF Conversion (Two-Pass)
    
    func buildGIFArguments(input: URL, output: URL, resolution: ResolutionPreset) -> [[String]] {
        let palettePath = NSTemporaryDirectory() + "palette_\(UUID().uuidString).png"
        let scaleFilter: String
        if let dims = resolution.dimensions {
            scaleFilter = "scale=\(dims.width):-1:flags=lanczos"
        } else {
            scaleFilter = "scale=480:-1:flags=lanczos"
        }
        
        let pass1 = ["-i", input.path, "-vf", "\(scaleFilter),palettegen", "-y", palettePath]
        let pass2 = ["-i", input.path, "-i", palettePath, "-lavfi", "\(scaleFilter) [x]; [x][1:v] paletteuse", "-y", output.path]
        return [pass1, pass2]
    }
    
    // MARK: - Conversion Execution
    
    func convert(
        input: URL,
        output: URL,
        arguments: [String],
        duration: TimeInterval,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws {
        guard let scriptURL = try? FFmpegBridge.ensureScript() else {
            throw VideoConverterError.ffmpegNotAvailable
        }
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                let task = try NSUserUnixTask(url: scriptURL)
                let stderrPipe = Pipe()
                task.standardError = stderrPipe.fileHandleForWriting
                
                let timeRegex = try? NSRegularExpression(pattern: "time=(\\d{2}):(\\d{2}):(\\d{2})\\.(\\d{2})")
                
                stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }
                    
                    if let match = timeRegex?.firstMatch(in: line, range: NSRange(location: 0, length: line.utf16.count)) {
                        let hours = Double((line as NSString).substring(with: match.range(at: 1))) ?? 0
                        let minutes = Double((line as NSString).substring(with: match.range(at: 2))) ?? 0
                        let seconds = Double((line as NSString).substring(with: match.range(at: 3))) ?? 0
                        let centiseconds = Double((line as NSString).substring(with: match.range(at: 4))) ?? 0
                        
                        let currentTime = hours * 3600 + minutes * 60 + seconds + centiseconds / 100
                        let progress = duration > 0 ? min(currentTime / duration, 1.0) : 0
                        progressHandler(progress)
                    }
                }
                
                var taskArgs = ["convert", path] + arguments
                
                task.execute(withArguments: taskArgs) { error in
                    stderrPipe.fileHandleForWriting.closeFile()
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    
                    if error != nil {
                        continuation.resume(throwing: VideoConverterError.ffmpegProcessFailed(exitCode: 1))
                    } else {
                        continuation.resume()
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    func convertGIF(
        input: URL,
        output: URL,
        resolution: ResolutionPreset,
        duration: TimeInterval,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws {
        let passes = buildGIFArguments(input: input, output: output, resolution: resolution)
        
        // Pass 1: Generate palette (0–30%)
        try await convert(
            input: input,
            output: output,
            arguments: passes[0],
            duration: duration,
            progressHandler: { p in progressHandler(p * 0.3) }
        )
        
        // Pass 2: Apply palette (30–100%)
        try await convert(
            input: input,
            output: output,
            arguments: passes[1],
            duration: duration,
            progressHandler: { p in progressHandler(0.3 + p * 0.7) }
        )
    }
    
    // MARK: - Cancellation
    
    static func cancelConversion() {
        guard let scriptURL = try? ensureScript() else { return }
        do {
            let task = try NSUserUnixTask(url: scriptURL)
            task.execute(withArguments: ["cancel"]) { _ in }
        } catch { }
    }
}
