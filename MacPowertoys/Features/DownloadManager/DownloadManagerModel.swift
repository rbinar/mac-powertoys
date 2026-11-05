import Foundation
import AppKit
import Darwin

// MARK: - Value types

struct DownloadPart: Codable, Equatable {
    var start: Int64
    var end: Int64?            // inclusive; nil = unknown length
    var received: Int64 = 0

    var length: Int64? { end.map { $0 - start + 1 } }
    var isComplete: Bool { length.map { received >= $0 } ?? false }
}

struct DownloadValidators: Codable, Equatable {
    var etag: String?
    var lastModified: String?
    var length: Int64?
}

enum DownloadState: String, Codable {
    case downloading, paused, completed, failed
}

struct DownloadItem: Codable, Identifiable, Equatable {
    let id: UUID
    let url: String
    let isVideo: Bool
    var folderPath: String
    var fileName: String
    var tempName: String = ""
    var state: DownloadState
    var totalLength: Int64?
    var validators = DownloadValidators()
    var acceptsRanges = false
    var parts: [DownloadPart] = []
    var videoFraction: Double = 0
    var message: String?

    var receivedBytes: Int64 { parts.reduce(0) { $0 + $1.received } }
    var fraction: Double? {
        if isVideo { return videoFraction }
        guard let total = totalLength, total > 0 else { return state == .completed ? 1 : nil }
        return min(1, Double(receivedBytes) / Double(total))
    }
    var tempPath: String { (folderPath as NSString).appendingPathComponent(tempName) }
    var finalPath: String { (folderPath as NSString).appendingPathComponent(fileName) }
    /// What Cancel may delete. `tempName` is empty for video and before the probe ends, and an empty
    /// component resolves to `folderPath` itself, so it must never reach a delete.
    var partialPaths: [String] {
        (tempName.isEmpty ? [] : [tempPath]) + (isVideo ? [finalPath + ".part"] : [])
    }
}

struct DownloadProbe: Equatable {
    var length: Int64?
    var acceptsRanges: Bool
    var validators: DownloadValidators
    var contentDisposition: String?
}

enum DownloadResumePlan: Equatable {
    case resume(remaining: [Int])
    case restart(reason: String)
}

struct YtDlpProgress: Equatable {
    var fraction: Double
    var speed: String?
}

enum DownloadError: Error, Equatable, LocalizedError {
    case rangeIgnored
    case http(Int)
    case shortRead
    case message(String)

    var errorDescription: String? {
        switch self {
        case .rangeIgnored: return "The server ignored the range request."
        case .http(let code): return "The server replied with HTTP \(code)."
        case .shortRead: return "The connection ended before the file was complete."
        case .message(let text): return text
        }
    }
}

// MARK: - Helpers (off the main actor)

/// A file written at explicit offsets; `pwrite` is safe to call from several connections at once.
private final class PartFile: @unchecked Sendable {
    private let fd: Int32

    init(path: String) throws {
        fd = open(path, O_WRONLY | O_CREAT, 0o644)
        if fd < 0 { throw DownloadError.message("Could not open the partial file.") }
    }

    deinit { close(fd) }

    func write(_ bytes: [UInt8], at offset: Int64) throws {
        var done = 0
        while done < bytes.count {
            let n = bytes[done...].withUnsafeBytes { pwrite(fd, $0.baseAddress, $0.count, off_t(offset) + off_t(done)) }
            if n < 0 { throw DownloadError.message("Could not write to disk.") }
            done += n
        }
    }
}

/// Holds the running yt-dlp so Cancel can terminate it.
private final class ProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    func set(_ p: Process) {
        lock.lock(); defer { lock.unlock() }
        process = p
        if cancelled { p.terminate() }
    }
    func terminate() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
        process?.terminate()
    }
}

// MARK: - Model

@MainActor
final class DownloadManagerModel: ObservableObject {
    // MARK: - Settings

    @Published var connections: Int {
        didSet {
            let clamped = min(8, max(1, connections))
            if clamped != connections { connections = clamped; return }
            UserDefaults.standard.set(connections, forKey: "downloadManager.connections")
        }
    }
    @Published var saveFolderPath: String {
        didSet { UserDefaults.standard.set(saveFolderPath, forKey: "downloadManager.saveFolder") }
    }
    @Published var watchClipboard: Bool {
        didSet {
            UserDefaults.standard.set(watchClipboard, forKey: "downloadManager.watchClipboard")
            if watchClipboard { startClipboardWatch() } else { stopClipboardWatch() }
        }
    }

    // MARK: - Runtime State

    @Published var urlText = ""
    @Published var videoMode = false
    @Published private(set) var inputError: String?
    @Published private(set) var tasks: [DownloadItem]
    @Published private(set) var speedText: [UUID: String] = [:]
    @Published private(set) var clipboardOffer: URL?
    @Published private(set) var ytDlpPath: String?
    @Published private(set) var ffmpegPath: String?

    static let installCommand = "brew install yt-dlp"
    nonisolated static let ytDlpCandidates = ["/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp"]
    nonisolated static let ffmpegCandidates = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]

    /// Smallest range worth its own connection. Tests lower it.
    var minPartSize: Int64 = 1_048_576

    var hubStatusText: String {
        let active = tasks.filter { $0.state == .downloading }.count
        return active == 0 ? "Ready" : "\(active) downloading"
    }

    // MARK: - Private

    private let session: URLSession
    private let storeURL: URL
    private var running: [UUID: (token: UUID, task: Task<Void, Never>)] = [:]
    private var samples: [UUID: (time: Date, bytes: Int64)] = [:]
    private var lastSave = Date.distantPast
    private var ytLastLine: [UUID: String] = [:]
    private var clipboardTimer: Timer?
    private var lastChangeCount = 0
    private var lastOfferedText: String?

    // MARK: - Init

    init(session: URLSession = .shared, storeURL: URL? = nil) {
        let defaults = UserDefaults.standard
        self.session = session
        self.storeURL = storeURL ?? Self.defaultStoreURL
        let stored = defaults.integer(forKey: "downloadManager.connections")
        connections = stored == 0 ? 4 : min(8, max(1, stored))
        saveFolderPath = defaults.string(forKey: "downloadManager.saveFolder")
            ?? (NSHomeDirectory() as NSString).appendingPathComponent("Downloads")
        watchClipboard = defaults.bool(forKey: "downloadManager.watchClipboard")
        tasks = Self.load(from: self.storeURL).map { item in
            var item = item
            if item.state == .downloading { item.state = .paused }
            return item
        }
        refreshTools()
        if watchClipboard { startClipboardWatch() }
    }

    nonisolated static var defaultStoreURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("DownloadManager", isDirectory: true)
            .appendingPathComponent("downloads.json")
    }

    // MARK: - Pure functions

    /// https with a host and no whitespace; anything else is rejected. App Transport Security blocks plain http.
    nonisolated static func validURL(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              let url = URL(string: trimmed),
              url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    /// Splits `totalLength` into up to `connections` (1...8) contiguous ranges of at least `minPartSize` bytes.
    nonisolated static func planParts(totalLength: Int64, connections: Int, minPartSize: Int64 = 1_048_576) -> [DownloadPart] {
        guard totalLength > 0 else { return [DownloadPart(start: 0, end: totalLength - 1)] }
        let wanted = Int64(min(8, max(1, connections)))
        let count = max(1, min(wanted, totalLength / max(1, minPartSize)))
        let base = totalLength / count
        let extra = totalLength % count
        var parts: [DownloadPart] = []
        var start: Int64 = 0
        for i in 0..<count {
            let size = base + (i < extra ? 1 : 0)
            parts.append(DownloadPart(start: start, end: start + size - 1))
            start += size
        }
        return parts
    }

    /// Continue the incomplete parts, or restart when the file changed or ranges are no longer usable.
    nonisolated static func planResume(parts: [DownloadPart], saved: DownloadValidators,
                                       current: DownloadValidators, serverAcceptsRanges: Bool) -> DownloadResumePlan {
        if let a = saved.etag, let b = current.etag, a != b {
            return .restart(reason: "The file changed on the server (ETag). Restarted from the beginning.")
        }
        if let a = saved.lastModified, let b = current.lastModified, a != b {
            return .restart(reason: "The file changed on the server (Last-Modified). Restarted from the beginning.")
        }
        if let a = saved.length, let b = current.length, a != b {
            return .restart(reason: "The file size changed on the server. Restarted from the beginning.")
        }
        let hasProgress = parts.contains { $0.received > 0 }
        if (parts.count > 1 || hasProgress) && !serverAcceptsRanges {
            return .restart(reason: "The server no longer supports resuming. Restarted from the beginning.")
        }
        return .resume(remaining: parts.indices.filter { !parts[$0].isComplete })
    }

    nonisolated static func parseProbe(_ http: HTTPURLResponse) -> DownloadProbe {
        let ranges = http.value(forHTTPHeaderField: "Accept-Ranges")?.lowercased().contains("bytes") ?? false
        let length = http.value(forHTTPHeaderField: "Content-Length").flatMap { Int64($0.trimmingCharacters(in: .whitespaces)) }
        return DownloadProbe(
            length: length,
            acceptsRanges: ranges && length != nil,
            validators: DownloadValidators(etag: http.value(forHTTPHeaderField: "ETag"),
                                           lastModified: http.value(forHTTPHeaderField: "Last-Modified"),
                                           length: length),
            contentDisposition: http.value(forHTTPHeaderField: "Content-Disposition"))
    }

    /// `Content-Disposition` name, else the URL's last path component; always a bare file name.
    nonisolated static func chooseFileName(contentDisposition: String?, url: URL) -> String {
        if let header = contentDisposition, let name = sanitizeFileName(dispositionName(header)) { return name }
        let fromURL = url.lastPathComponent
        return sanitizeFileName(fromURL.removingPercentEncoding ?? fromURL) ?? "download"
    }

    private nonisolated static func dispositionName(_ header: String) -> String? {
        var plain: String?
        var extended: String?
        for param in header.split(separator: ";").dropFirst() {
            guard let eq = param.firstIndex(of: "=") else { continue }
            let key = param[..<eq].trimmingCharacters(in: .whitespaces).lowercased()
            var value = param[param.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if key == "filename*" {
                if let quote = value.range(of: "''") { value = String(value[quote.upperBound...]) }
                extended = value.removingPercentEncoding
            } else if key == "filename" {
                if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") { value = String(value.dropFirst().dropLast()) }
                plain = value
            }
        }
        return extended ?? plain
    }

    private nonisolated static func sanitizeFileName(_ name: String?) -> String? {
        guard let name else { return nil }
        let normalized = name.replacingOccurrences(of: "\\", with: "/")
        var last = (normalized as NSString).lastPathComponent
        last = last.replacingOccurrences(of: ":", with: "_")
        last = last.trimmingCharacters(in: .whitespacesAndNewlines)
        while last.hasPrefix(".") { last.removeFirst() }
        guard !last.isEmpty, !last.contains("/") else { return nil }
        return last
    }

    /// "name.ext" -> "name (1).ext" ... until `exists` is false.
    nonisolated static func uniqueFileName(_ name: String, exists: (String) -> Bool) -> String {
        if !exists(name) { return name }
        let ext = (name as NSString).pathExtension
        let base = (name as NSString).deletingPathExtension
        var n = 1
        while true {
            let candidate = ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)"
            if !exists(candidate) { return candidate }
            n += 1
        }
    }

    /// Parses a `[download]  45.3% of ... at 1.2MiB/s` line.
    nonisolated static func parseYtDlpProgress(_ line: String) -> YtDlpProgress? {
        guard let percent = firstMatch(#"\[download\]\s+(\d+(?:\.\d+)?)%"#, in: line),
              let value = Double(percent) else { return nil }
        return YtDlpProgress(fraction: min(1, value / 100), speed: firstMatch(#"\bat\s+(\S+/s)"#, in: line))
    }

    nonisolated static func parseYtDlpDestination(_ line: String) -> String? {
        if let path = firstMatch(#"^\[download\] Destination: (.+)$"#, in: line) { return path }
        return firstMatch(#"^\[Merger\] Merging formats into "(.+)"$"#, in: line)
    }

    nonisolated static func ytDlpArguments(url: String, folder: String, ffmpegPath: String?) -> [String] {
        let template = folder.replacingOccurrences(of: "%", with: "%%") + "/%(title)s.%(ext)s"
        var args = ["--newline", "--no-playlist", "--no-overwrites", "-o", template]
        if let ffmpegPath { args += ["--ffmpeg-location", ffmpegPath] }
        return args + ["--", url]
    }

    nonisolated static func firstExisting(_ paths: [String], exists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) -> String? {
        paths.first(where: exists)
    }

    private nonisolated static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    // MARK: - Persistence

    nonisolated static func load(from url: URL) -> [DownloadItem] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([DownloadItem].self, from: data)) ?? []
    }

    nonisolated static func save(_ items: [DownloadItem], to url: URL) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(items).write(to: url, options: .atomic)
        } catch {
            NSLog("[DownloadManager] could not save task list: %@", error.localizedDescription)
        }
    }

    private func persist() {
        lastSave = Date()
        Self.save(tasks, to: storeURL)
    }

    // MARK: - Tools

    func refreshTools() {
        ytDlpPath = Self.firstExisting(Self.ytDlpCandidates)
        ffmpegPath = Self.firstExisting(Self.ffmpegCandidates)
    }

    // MARK: - Actions

    func addFromInput() {
        guard let url = Self.validURL(urlText) else {
            inputError = "Only https links are supported."
            return
        }
        if videoMode && ytDlpPath == nil {
            inputError = "yt-dlp is not installed."
            return
        }
        inputError = nil
        urlText = ""
        add(url, video: videoMode)
    }

    func acceptOffer() {
        guard let url = clipboardOffer else { return }
        clipboardOffer = nil
        add(url, video: videoMode && ytDlpPath != nil)
    }

    func dismissOffer() { clipboardOffer = nil }

    private func add(_ url: URL, video: Bool) {
        let name = video ? (url.host ?? "video") : Self.chooseFileName(contentDisposition: nil, url: url)
        let item = DownloadItem(id: UUID(), url: url.absoluteString, isVideo: video,
                                folderPath: saveFolderPath, fileName: name, state: .downloading)
        tasks.insert(item, at: 0)
        persist()
        start(item.id)
    }

    func pause(_ id: UUID) {
        guard let index = index(of: id), tasks[index].state == .downloading else { return }
        running[id]?.task.cancel()
        running[id] = nil
        tasks[index].state = .paused
        speedText[id] = nil
        persist()
    }

    func resume(_ id: UUID) {
        guard let index = index(of: id), tasks[index].state == .paused || tasks[index].state == .failed else { return }
        tasks[index].state = .downloading
        tasks[index].message = nil
        persist()
        start(id)
    }

    /// Stops the transfer and removes only the partial data; a finished file is never touched.
    func cancel(_ id: UUID) {
        guard let index = index(of: id) else { return }
        let item = tasks[index]
        running[id]?.task.cancel()
        running[id] = nil
        if item.state != .completed {
            for path in item.partialPaths { try? FileManager.default.removeItem(atPath: path) }
        }
        remove(id)
    }

    func remove(_ id: UUID) {
        tasks.removeAll { $0.id == id }
        speedText[id] = nil
        samples[id] = nil
        persist()
    }

    func revealPath(_ item: DownloadItem) -> String {
        FileManager.default.fileExists(atPath: item.finalPath) ? item.finalPath : item.folderPath
    }

    // MARK: - Running

    private func index(of id: UUID) -> Int? { tasks.firstIndex { $0.id == id } }

    private func start(_ id: UUID) {
        guard running[id] == nil else { return }
        let token = UUID()
        let task = Task { [weak self] in
            guard let self else { return }
            await self.perform(id, token: token)
        }
        running[id] = (token, task)
    }

    private func perform(_ id: UUID, token: UUID) async {
        do {
            if tasks.first(where: { $0.id == id })?.isVideo == true {
                try await runVideo(id)
            } else {
                try await runHTTP(id)
            }
            if !Task.isCancelled { markState(id, .completed) }
        } catch {
            if !Task.isCancelled {
                NSLog("[DownloadManager] download failed: %@", error.localizedDescription)
                markState(id, .failed, message: error.localizedDescription)
            }
        }
        if running[id]?.token == token { running[id] = nil }
    }

    private func markState(_ id: UUID, _ state: DownloadState, message: String? = nil) {
        guard let index = index(of: id), tasks[index].state == .downloading else { return }
        tasks[index].state = state
        if let message { tasks[index].message = message }
        if state == .completed { tasks[index].videoFraction = 1 }
        speedText[id] = nil
        samples[id] = nil
        persist()
    }

    private func update(_ id: UUID, _ change: (inout DownloadItem) -> Void) {
        guard let index = index(of: id) else { return }
        change(&tasks[index])
    }

    // MARK: HTTP

    private func runHTTP(_ id: UUID) async throws {
        guard let item = tasks.first(where: { $0.id == id }), let url = URL(string: item.url) else {
            throw DownloadError.message("Invalid URL.")
        }
        let probe = try await Self.probe(session: session, url: url)
        try Task.checkCancellation()

        if item.parts.isEmpty {
            let name = Self.uniqueFileName(Self.chooseFileName(contentDisposition: probe.contentDisposition, url: url)) {
                FileManager.default.fileExists(atPath: (item.folderPath as NSString).appendingPathComponent($0))
            }
            update(id) {
                $0.fileName = name
                $0.tempName = ".\(name).\($0.id.uuidString.prefix(8)).mpdownload"
            }
            try freshPlan(id, probe)
        } else {
            switch Self.planResume(parts: item.parts, saved: item.validators, current: probe.validators,
                                   serverAcceptsRanges: probe.acceptsRanges) {
            case .restart(let reason):
                update(id) { $0.message = reason }
                try freshPlan(id, probe)
            case .resume:
                if item.receivedBytes > 0 && !FileManager.default.fileExists(atPath: item.tempPath) {
                    update(id) { $0.message = "The partial file is missing. Restarted from the beginning." }
                    try freshPlan(id, probe)
                }
            }
        }

        do {
            try await transfer(id, url: url)
        } catch DownloadError.rangeIgnored {
            // The server answered a range request with the whole body: start over on one plain connection.
            update(id) {
                $0.acceptsRanges = false
                $0.message = "The server ignored range requests. Using one connection."
                $0.parts = [DownloadPart(start: 0, end: $0.totalLength.map { $0 - 1 })]
            }
            guard let current = tasks.first(where: { $0.id == id }),
                  FileManager.default.createFile(atPath: current.tempPath, contents: nil) else {
                throw DownloadError.message("Could not reset the partial file.")
            }
            persist()
            try await transfer(id, url: url)
        }

        guard let done = tasks.first(where: { $0.id == id }) else { return }
        let size = done.parts.reduce(Int64(0)) { $0 + $1.received }
        if let total = done.totalLength, total != size { throw DownloadError.shortRead }
        let finalName = Self.uniqueFileName(done.fileName) {
            FileManager.default.fileExists(atPath: (done.folderPath as NSString).appendingPathComponent($0))
        }
        let destination = (done.folderPath as NSString).appendingPathComponent(finalName)
        try FileManager.default.moveItem(atPath: done.tempPath, toPath: destination)
        update(id) { $0.fileName = finalName }
    }

    /// New part layout for the probed server, with an empty partial file.
    private func freshPlan(_ id: UUID, _ probe: DownloadProbe) throws {
        let count = connections
        let minSize = minPartSize
        update(id) { item in
            item.totalLength = probe.length
            item.acceptsRanges = probe.acceptsRanges
            item.validators = probe.validators
            if probe.acceptsRanges, let length = probe.length {
                item.parts = Self.planParts(totalLength: length, connections: count, minPartSize: minSize)
            } else {
                item.parts = [DownloadPart(start: 0, end: probe.length.map { $0 - 1 })]
            }
        }
        guard let item = tasks.first(where: { $0.id == id }),
              FileManager.default.createFile(atPath: item.tempPath, contents: nil) else {
            throw DownloadError.message("Could not create the partial file in the save folder.")
        }
        persist()
    }

    private func transfer(_ id: UUID, url: URL) async throws {
        guard let item = tasks.first(where: { $0.id == id }) else { return }
        let file = try PartFile(path: item.tempPath)
        let session = self.session
        let single = item.parts.count == 1
        let report: @Sendable (Int, Int64) -> Void = { [weak self] part, received in
            Task { @MainActor in self?.applyProgress(id, part: part, received: received) }
        }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for (i, part) in item.parts.enumerated() where !part.isComplete {
                let needsRange = !(single && part.start == 0 && part.received == 0)
                group.addTask {
                    try await Self.downloadPart(session: session, url: url, index: i, part: part,
                                                needsRange: needsRange, file: file, report: report)
                }
            }
            try await group.waitForAll()
        }
        // A part of unknown length is now known.
        update(id) { item in
            for i in item.parts.indices where item.parts[i].end == nil {
                item.parts[i].end = item.parts[i].start + item.parts[i].received - 1
            }
        }
    }

    private func applyProgress(_ id: UUID, part: Int, received: Int64) {
        guard let index = index(of: id), tasks[index].parts.indices.contains(part) else { return }
        tasks[index].parts[part].received = max(tasks[index].parts[part].received, received)
        guard tasks[index].state == .downloading else { return }
        let bytes = tasks[index].receivedBytes
        let now = Date()
        if let sample = samples[id] {
            let dt = now.timeIntervalSince(sample.time)
            if dt >= 1 {
                speedText[id] = Self.speedString(Double(bytes - sample.bytes) / dt)
                samples[id] = (now, bytes)
            }
        } else {
            samples[id] = (now, bytes)
        }
        if now.timeIntervalSince(lastSave) > 2 { persist() }
    }

    nonisolated static func speedString(_ bytesPerSecond: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(max(0, bytesPerSecond)), countStyle: .file) + "/s"
    }

    private nonisolated static func probe(session: URLSession, url: URL) async throws -> DownloadProbe {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return DownloadProbe(length: nil, acceptsRanges: false, validators: DownloadValidators(), contentDisposition: nil)
        }
        return parseProbe(http)
    }

    /// Streams one range (or the whole body) into the partial file at its own offsets.
    private nonisolated static func downloadPart(session: URLSession, url: URL, index: Int, part: DownloadPart,
                                                 needsRange: Bool, file: PartFile,
                                                 report: @escaping @Sendable (Int, Int64) -> Void) async throws {
        var received = part.received
        let from = part.start + part.received
        var lastReport = Date()
        var request = URLRequest(url: url)
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        if needsRange {
            request.setValue("bytes=\(from)-\(part.end.map(String.init) ?? "")", forHTTPHeaderField: "Range")
        }
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else { throw DownloadError.message("Unexpected response.") }
            if needsRange {
                if http.statusCode == 200 { throw DownloadError.rangeIgnored }
                guard http.statusCode == 206 else { throw DownloadError.http(http.statusCode) }
                if let contentRange = http.value(forHTTPHeaderField: "Content-Range"),
                   !contentRange.lowercased().hasPrefix("bytes \(from)-") {
                    throw DownloadError.rangeIgnored
                }
            } else {
                guard (200..<300).contains(http.statusCode) else { throw DownloadError.http(http.statusCode) }
            }

            let limit = part.length
            var buffer: [UInt8] = []
            buffer.reserveCapacity(65_536)

            func flushBuffer() throws {
                if let limit, received + Int64(buffer.count) > limit { buffer.removeLast(buffer.count - Int(limit - received)) }
                guard !buffer.isEmpty else { return }
                try file.write(buffer, at: part.start + received)
                received += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                if Date().timeIntervalSince(lastReport) >= 0.25 {
                    report(index, received)
                    lastReport = Date()
                }
            }

            for try await byte in bytes {
                buffer.append(byte)
                let full = buffer.count >= 65_536
                let reachesLimit = limit.map { received + Int64(buffer.count) >= $0 } ?? false
                if full || reachesLimit {
                    try flushBuffer()
                    if reachesLimit { break }
                }
            }
            try flushBuffer()
            if let limit, received < limit { throw DownloadError.shortRead }
            report(index, received)
        } catch {
            report(index, received)
            throw error
        }
    }

    // MARK: Video

    private func runVideo(_ id: UUID) async throws {
        guard let item = tasks.first(where: { $0.id == id }) else { return }
        guard let tool = ytDlpPath else { throw DownloadError.message("yt-dlp is not installed.") }
        let args = Self.ytDlpArguments(url: item.url, folder: item.folderPath, ffmpegPath: ffmpegPath)
        let box = ProcessBox()
        let status: Int32 = try await withTaskCancellationHandler {
            try await Task.detached {
                try await Self.runProcess(tool, arguments: args, box: box) { line in
                    Task { @MainActor [weak self] in self?.handleYtDlpLine(id, line) }
                }
            }.value
        } onCancel: {
            box.terminate()
        }
        try Task.checkCancellation()
        if status != 0 {
            throw DownloadError.message(ytLastLine[id] ?? "yt-dlp exited with status \(status).")
        }
    }

    private func handleYtDlpLine(_ id: UUID, _ line: String) {
        if let progress = Self.parseYtDlpProgress(line) {
            update(id) { $0.videoFraction = progress.fraction }
            speedText[id] = progress.speed
        } else if let path = Self.parseYtDlpDestination(line) {
            update(id) { $0.fileName = (path as NSString).lastPathComponent }
        } else if !line.isEmpty {
            ytLastLine[id] = line
        }
    }

    private nonisolated static func runProcess(_ path: String, arguments: [String], box: ProcessBox,
                                               onLine: @escaping @Sendable (String) -> Void) async throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            throw DownloadError.message("Could not start yt-dlp.")
        }
        box.set(process)
        for try await line in pipe.fileHandleForReading.bytes.lines { onLine(line) }
        process.waitUntilExit()
        return process.terminationStatus
    }

    // MARK: - Clipboard link prompt

    private func startClipboardWatch() {
        lastChangeCount = NSPasteboard.general.changeCount
        clipboardTimer?.invalidate()
        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkPasteboard() }
        }
    }

    private func stopClipboardWatch() {
        clipboardTimer?.invalidate()
        clipboardTimer = nil
        clipboardOffer = nil
    }

    private func checkPasteboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount
        guard let text = pb.string(forType: .string), let url = Self.validURL(text),
              text != lastOfferedText else { return }
        lastOfferedText = text
        clipboardOffer = url
    }

    // MARK: - Monitoring

    func stopMonitoring() {
        stopClipboardWatch()
        for (id, entry) in running {
            entry.task.cancel()
            update(id) { if $0.state == .downloading { $0.state = .paused } }
        }
        running = [:]
        persist()
    }
}
