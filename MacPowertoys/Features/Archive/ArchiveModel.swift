import Foundation
import AppKit
import Darwin

struct ArchiveEntry: Identifiable, Equatable {
    let path: String
    let size: Int64
    let isFolder: Bool
    let isEncrypted: Bool
    var id: String { path }
}

enum ArchiveFormat: String, CaseIterable, Identifiable {
    case zip = "ZIP"
    case sevenZip = "7z"
    var id: String { rawValue }
    var typeSwitch: String { self == .zip ? "-tzip" : "-t7z" }
    var fileExtension: String { self == .zip ? "zip" : "7z" }
}

enum ArchiveLevel: String, CaseIterable, Identifiable {
    case fast = "Fast"
    case normal = "Normal"
    case best = "Best"
    var id: String { rawValue }
    var mx: Int {
        switch self {
        case .fast: return 1
        case .normal: return 5
        case .best: return 9
        }
    }
}

/// Holds the running 7zz so it can be cancelled from the main actor.
private final class SevenZipHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var _cancelled = false

    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return _cancelled }

    func set(_ p: Process) {
        lock.lock(); defer { lock.unlock() }
        process = p
        if _cancelled { p.terminate() }
    }
    func cancel() {
        lock.lock(); defer { lock.unlock() }
        _cancelled = true
        process?.terminate()
    }
}

@MainActor
final class ArchiveModel: ObservableObject {
    enum Mode: String, CaseIterable, Identifiable {
        case extract = "Extract"
        case compress = "Compress"
        var id: String { rawValue }
    }

    // MARK: - Settings
    // Nothing is persisted; passwords stay in memory only.

    @Published var mode: Mode = .extract
    @Published var extractPassword = ""
    @Published var compressPassword = ""
    @Published var format: ArchiveFormat = .zip
    @Published var level: ArchiveLevel = .normal

    // MARK: - Runtime State

    @Published private(set) var sevenZipPath: String?
    @Published private(set) var unarPath: String?
    @Published private(set) var lsarPath: String?
    @Published private(set) var archiveURL: URL?
    @Published private(set) var entries: [ArchiveEntry] = []
    @Published private(set) var needsPassword = false
    @Published private(set) var items: [URL] = []
    @Published private(set) var isBusy = false
    @Published private(set) var progress: Double?
    @Published private(set) var statusMessage: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var resultURL: URL?

    // MARK: - Private

    nonisolated static let installCommand = "brew install sevenzip"
    nonisolated static let unarInstallCommand = "brew install unar"
    private nonisolated static let candidates = ["/opt/homebrew/bin/7zz", "/usr/local/bin/7zz"]
    private nonisolated static let unarCandidates = ["/opt/homebrew/bin/unar", "/usr/local/bin/unar"]
    private nonisolated static let lsarCandidates = ["/opt/homebrew/bin/lsar", "/usr/local/bin/lsar"]
    private var handle: SevenZipHandle?
    private var task: Task<Void, Never>?

    var hubStatusText: String { isBusy ? "Working…" : "Ready" }

    /// Extract with a RAR selected goes through unar/lsar; everything else uses 7zz.
    var usesRAR: Bool { mode == .extract && (archiveURL.map { Self.isRAR($0.lastPathComponent) } ?? false) }
    var engineReady: Bool { usesRAR ? (unarPath != nil && lsarPath != nil) : sevenZipPath != nil }
    var missingInstallCommand: String { usesRAR ? Self.unarInstallCommand : Self.installCommand }

    // MARK: - Init

    init() { checkAgain() }

    func checkAgain() {
        sevenZipPath = Self.candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
        unarPath = Self.unarCandidates.first { FileManager.default.isExecutableFile(atPath: $0) }
        lsarPath = Self.lsarCandidates.first { FileManager.default.isExecutableFile(atPath: $0) }
        if archiveURL != nil, entries.isEmpty, !needsPassword, engineReady { loadListing() }
    }

    // MARK: - Pure functions

    /// `x.part07.rar` -> `x.part01.rar`, `x.part7.rar` -> `x.part1.rar`, `x.007` -> `x.001`, `x.r01` -> `x.rar`. Other names are unchanged.
    nonisolated static func firstPartName(_ name: String) -> String {
        if let m = firstMatch(#"^(.*\.part)(\d+)(\.rar)$"#, in: name, options: [.caseInsensitive]) {
            return m[1] + String(repeating: "0", count: max(m[2].count - 1, 0)) + "1" + m[3]
        }
        if let m = firstMatch(#"^(.*\.)(\d{3})$"#, in: name) {
            return m[1] + "001"
        }
        if let m = firstMatch(#"^(.*\.)(r)\d{2}$"#, in: name, options: [.caseInsensitive]) {
            return m[1] + (m[2] == "R" ? "RAR" : "rar")
        }
        return name
    }

    /// `.rar` (including `.partN.rar`) or an old-style volume `.r00`...`.r99`.
    nonisolated static func isRAR(_ name: String) -> Bool {
        firstMatch(#"\.(rar|r\d{2})$"#, in: name, options: [.caseInsensitive]) != nil
    }

    /// Name without part and archive extensions: `a.part01.rar` -> `a`, `b.tar.gz` -> `b`, `c.7z.001` -> `c`.
    nonisolated static func archiveBaseName(_ name: String) -> String {
        var base = name
        if let m = firstMatch(#"^(.*)\.part\d+\.rar$"#, in: base, options: [.caseInsensitive]) {
            base = m[1]
        } else {
            if let m = firstMatch(#"^(.*)\.\d{3}$"#, in: base) { base = m[1] }
            base = (base as NSString).deletingPathExtension
        }
        if base.lowercased().hasSuffix(".tar") { base = (base as NSString).deletingPathExtension }
        return base.isEmpty ? name : base
    }

    /// `url` itself when free, else `name 2.ext`, `name 3.ext`, ...
    nonisolated static func uniqueURL(_ url: URL, exists: (URL) -> Bool) -> URL {
        guard exists(url) else { return url }
        let dir = url.deletingLastPathComponent()
        let ext = url.pathExtension
        let stem = url.deletingPathExtension().lastPathComponent
        var n = 2
        while true {
            let name = ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)"
            let candidate = dir.appendingPathComponent(name)
            if !exists(candidate) { return candidate }
            n += 1
        }
    }

    /// Reading: no `-p`. 7zz then asks on stdin when it needs a password, while a bare `-p` would mean an empty one.
    nonisolated static func listArguments(archive: String) -> [String] {
        ["l", "-slt", "--", archive]
    }

    nonisolated static func testArguments(archive: String) -> [String] {
        ["t", "-bsp1", "--", archive]
    }

    nonisolated static func extractArguments(archive: String, outputDir: String) -> [String] {
        ["x", "-aou", "-bsp1", "-o" + outputDir, "--", archive]
    }

    /// unar/lsar take the password only as an argument (visible in `ps`); accepted for RAR. Never log these.
    nonisolated static func lsarArguments(archive: String, password: String?) -> [String] {
        ["-j"] + passwordArguments(password) + ["--", archive]
    }

    nonisolated static func lsarTestArguments(archive: String, password: String?) -> [String] {
        ["-t"] + passwordArguments(password) + ["--", archive]
    }

    /// `-r` renames instead of overwriting, `-D` adds no containing folder, `-nr` leaves nested archives packed.
    nonisolated static func unarArguments(archive: String, outputDir: String, password: String?) -> [String] {
        ["-q", "-nr", "-r", "-D", "-o", outputDir] + passwordArguments(password) + ["--", archive]
    }

    private nonisolated static func passwordArguments(_ password: String?) -> [String] {
        guard let password, !password.isEmpty else { return [] }
        return ["-p", password]
    }

    /// Creating: a bare `-p` makes 7zz ask on stdin. The password is never an argument.
    nonisolated static func compressArguments(output: String, items: [String], format: ArchiveFormat,
                                              level: ArchiveLevel, usePassword: Bool) -> [String] {
        var args = ["a", format.typeSwitch, "-mx=\(level.mx)", "-bsp1"]
        if usePassword {
            args.append("-p")
            args.append(format == .zip ? "-mem=AES256" : "-mhe=on")
        }
        return args + ["--", output] + items
    }

    /// 7zz rejects non-ASCII ZIP passwords (E_INVALIDARG). 7z accepts them.
    nonisolated static func canUsePassword(_ password: String, format: ArchiveFormat) -> Bool {
        format != .zip || password.allSatisfy(\.isASCII)
    }

    /// Text fed to stdin. `confirm` covers a 7zz that asks twice when creating; a spare line is ignored.
    nonisolated static func passwordInput(_ password: String, confirm: Bool) -> Data {
        Data((confirm ? "\(password)\n\(password)\n" : "\(password)\n").utf8)
    }

    /// Path relative to `base` when the item lives directly in it, so the archive does not store the full path.
    nonisolated static func itemArgument(_ item: URL, base: URL) -> String {
        item.deletingLastPathComponent().standardizedFileURL.path == base.standardizedFileURL.path
            ? item.lastPathComponent : item.path
    }

    /// Parses `7zz l -slt`: a header block, a `----------` line, then one `Key = Value` block per entry.
    nonisolated static func parseListing(_ output: String) -> [ArchiveEntry] {
        var result: [ArchiveEntry] = []
        var inEntries = false
        var current: [String: String] = [:]

        func flush() {
            if let path = current["Path"] {
                let isFolder = current["Folder"] == "+" || (current["Attributes"] ?? "").hasPrefix("D")
                result.append(ArchiveEntry(path: path, size: Int64(current["Size"] ?? "") ?? 0,
                                           isFolder: isFolder, isEncrypted: current["Encrypted"] == "+"))
            }
            current = [:]
        }

        for line in output.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let s = String(line)
            if !inEntries {
                if s == "----------" { inEntries = true }
                continue
            }
            if s.isEmpty { flush(); continue }
            if let r = s.range(of: " = ") { current[String(s[..<r.lowerBound])] = String(s[r.upperBound...]) }
        }
        flush()
        return result
    }

    /// The last `NN%` in a chunk of `-bsp1` output (updates are separated by carriage returns).
    nonisolated static func parseProgress(_ chunk: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: #"(\d{1,3})%"#) else { return nil }
        let ns = chunk as NSString
        guard let match = regex.matches(in: chunk, range: NSRange(location: 0, length: ns.length)).last,
              let value = Int(ns.substring(with: match.range(at: 1))), value <= 100 else { return nil }
        return value
    }

    /// 0 = ok, 1 = warnings. -1 means 7zz could not be started.
    nonisolated static func succeeded(_ status: Int32) -> Bool { status == 0 || status == 1 }

    /// True for output of a failed run that means "password missing or wrong".
    nonisolated static func isPasswordFailure(_ output: String) -> Bool {
        let text = output.lowercased()
        return text.contains("wrong password")
            || text.contains("cannot open encrypted archive")
            || (text.contains("enter password") && text.contains("break signaled")) // asked, but no password given
    }

    /// Entries of `lsar -j`; nil when the text is not an lsar JSON document.
    nonisolated static func parseLsar(_ json: String) -> [ArchiveEntry]? {
        guard let obj = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let contents = obj["lsarContents"] as? [[String: Any]] else { return nil }
        return contents.compactMap { e in
            guard let name = e["XADFileName"] as? String else { return nil }
            return ArchiveEntry(path: name, size: (e["XADFileSize"] as? NSNumber)?.int64Value ?? 0,
                                isFolder: e["XADIsDirectory"] as? Bool == true,
                                isEncrypted: e["XADIsEncrypted"] as? Bool == true)
        }
    }

    enum LsarOutcome: Equatable { case ok, needsPassword, wrongPassword, failed }

    /// Output of `lsar -t` or `lsar -j`. A wrong password on an archive with encrypted names gives JSON with `lsarError` 15.
    nonisolated static func classifyLsar(_ output: String, status: Int32) -> LsarOutcome {
        if status == 0 { return .ok }
        let text = output.lowercased()
        if text.contains("requires a password") { return .needsPassword }
        if text.contains("wrong password") { return .wrongPassword }
        if let obj = try? JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any],
           obj["lsarError"] as? Int == 15 { return .wrongPassword }
        return .failed
    }

    /// Last line of unar/lsar text output; JSON output has no useful line.
    nonisolated static func unarErrorSummary(_ output: String, status: Int32) -> String {
        if !output.hasPrefix("{"),
           let line = output.split(whereSeparator: \.isNewline).last?.trimmingCharacters(in: .whitespaces),
           !line.isEmpty { return line }
        return "unar failed (exit \(status))."
    }

    /// Symlinks to delete: created by this run (not in `preExisting`), inside `dest`, resolving to a target outside it.
    /// `target` is the fully resolved absolute path.
    nonisolated static func unsafeSymlinks(dest: String, preExisting: Set<String>,
                                           found: [(path: String, target: String)]) -> [String] {
        let root = dest.count > 1 && dest.hasSuffix("/") ? String(dest.dropLast()) : dest
        return found.filter { link in
            !preExisting.contains(link.path)
                && link.path.hasPrefix(root + "/")
                && !(link.target == root || link.target.hasPrefix(root + "/"))
        }.map(\.path)
    }

    /// Top-level entries of `dest` before extracting. `unar -r` renames on collision, so everything a run
    /// writes lives under new top-level names and the rest of `dest` (e.g. ~/Downloads) is never walked.
    nonisolated static func snapshotSymlinks(in dest: URL) -> Set<String> {
        topLevel(resolvedPath(dest.path))
    }

    /// Deletes the symlinks this run created under `dest` that point outside it. Returns how many.
    nonisolated static func removeUnsafeLinks(in dest: URL, preExisting: Set<String>) -> Int {
        let root = resolvedPath(dest.path)
        let fm = FileManager.default
        let created = topLevel(root).subtracting(preExisting)
        let links = created.flatMap { item -> [String] in
            let isLink = (try? fm.destinationOfSymbolicLink(atPath: item)) != nil
            return isLink ? [item] : walkSymlinks(item)
        }
        let found: [(path: String, target: String)] = links.compactMap { p in
            guard let raw = try? fm.destinationOfSymbolicLink(atPath: p) else { return nil }
            let absolute = raw.hasPrefix("/") ? raw : (p as NSString).deletingLastPathComponent + "/" + raw
            return (p, resolvedPath(absolute))
        }
        var removed = 0
        for path in unsafeSymlinks(dest: root, preExisting: preExisting, found: found) {
            if (try? fm.removeItem(atPath: path)) != nil { removed += 1 }
        }
        return removed
    }

    private nonisolated static func topLevel(_ root: String) -> Set<String> {
        Set(((try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []).map { root + "/" + $0 })
    }

    private nonisolated static func walkSymlinks(_ root: String) -> [String] {
        guard let e = FileManager.default.enumerator(at: URL(fileURLWithPath: root),
                                                     includingPropertiesForKeys: [.isSymbolicLinkKey], options: []) else { return [] }
        var links: [String] = []
        for case let url as URL in e where (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            links.append(url.path)   // the enumerator does not descend into symlinked directories
        }
        return links
    }

    /// realpath of the longest existing prefix, then the remaining (missing) components resolved lexically.
    nonisolated static func resolvedPath(_ path: String) -> String {
        var existing = path
        var rest: [String] = []
        var parts: [String] = []
        while true {
            if let r = realpath(existing, nil) {
                parts = String(cString: r).split(separator: "/").map(String.init)
                free(r)
                break
            }
            if existing == "/" || existing.isEmpty { break }
            rest.append((existing as NSString).lastPathComponent)
            existing = (existing as NSString).deletingLastPathComponent
        }
        for c in rest.reversed() {
            if c == ".." { _ = parts.popLast() } else if c != "." && !c.isEmpty { parts.append(c) }
        }
        return "/" + parts.joined(separator: "/")
    }

    nonisolated static func errorSummary(_ output: String, status: Int32) -> String {
        for line in output.split(whereSeparator: \.isNewline) where line.hasPrefix("ERROR:") {
            return String(line.dropFirst("ERROR:".count)).trimmingCharacters(in: .whitespaces)
        }
        return "7zz failed (exit \(status))."
    }

    private nonisolated static func firstMatch(_ pattern: String, in text: String,
                                               options: NSRegularExpression.Options = []) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let ns = text as NSString
        guard let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<m.numberOfRanges).map { ns.substring(with: m.range(at: $0)) }
    }

    // MARK: - Running 7zz

    private struct RunResult: Sendable {
        let status: Int32
        let output: String
        let cancelled: Bool
    }

    private nonisolated static func run(exe: String, args: [String], input: Data?, cwd: URL?,
                                        handle: SevenZipHandle, onProgress: @escaping @Sendable (Int) -> Void) -> RunResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: exe)
        process.arguments = args
        process.currentDirectoryURL = cwd
        let out = Pipe()
        let inPipe = Pipe()
        process.standardOutput = out
        process.standardError = out
        process.standardInput = inPipe
        do {
            try process.run()
        } catch {
            NSLog("[Archive] 7zz failed to start: %@", error.localizedDescription)
            return RunResult(status: -1, output: "ERROR: Could not run 7zz.", cancelled: false)
        }
        handle.set(process)

        let writer = inPipe.fileHandleForWriting
        _ = fcntl(writer.fileDescriptor, F_SETNOSIGPIPE, 1)   // 7zz may exit before reading its stdin
        if let input { try? writer.write(contentsOf: input) }
        try? writer.close()

        var collected = Data()
        let reader = out.fileHandleForReading
        while true {
            let chunk = reader.availableData
            if chunk.isEmpty { break }
            collected.append(chunk)
            if let p = parseProgress(String(decoding: chunk, as: UTF8.self)) { onProgress(p) }
        }
        process.waitUntilExit()
        return RunResult(status: process.terminationStatus, output: String(decoding: collected, as: UTF8.self),
                         cancelled: handle.cancelled)
    }

    private func perform(exe: String? = nil, args: [String], input: Data?, cwd: URL? = nil,
                         trackProgress: Bool = true) async -> RunResult? {
        guard let exe = exe ?? sevenZipPath else { return nil }
        let h = SevenZipHandle()
        handle = h
        isBusy = true
        progress = nil
        errorMessage = nil
        statusMessage = nil
        resultURL = nil
        let result = await Task.detached(priority: .userInitiated) {
            Self.run(exe: exe, args: args, input: input, cwd: cwd, handle: h) { p in
                Task { @MainActor [weak self] in
                    if trackProgress, self?.handle === h { self?.progress = Double(p) / 100 }
                }
            }
        }.value
        guard handle === h else { return nil }
        handle = nil
        isBusy = false
        progress = nil
        return result
    }

    func cancel() { handle?.cancel() }

    // MARK: - Extract

    func setArchive(_ url: URL) {
        guard !isBusy else { return }
        let first = url.deletingLastPathComponent().appendingPathComponent(Self.firstPartName(url.lastPathComponent))
        archiveURL = FileManager.default.fileExists(atPath: first.path) ? first : url
        entries = []
        needsPassword = false
        extractPassword = ""
        statusMessage = nil
        errorMessage = nil
        resultURL = nil
        loadListing()
    }

    func loadListing() {
        guard let archive = archiveURL, !isBusy else { return }
        let pw = extractPassword
        if Self.isRAR(archive.lastPathComponent) { loadRARListing(archive, password: pw); return }
        let args = Self.listArguments(archive: archive.path)
        task = Task { [weak self] in
            guard let self,
                  let r = await self.perform(args: args, input: pw.isEmpty ? nil : Self.passwordInput(pw, confirm: false))
            else { return }
            if r.cancelled { return }
            if Self.succeeded(r.status) {
                self.entries = Self.parseListing(r.output)
                self.needsPassword = false
            } else if Self.isPasswordFailure(r.output) {
                self.needsPassword = true
                self.errorMessage = pw.isEmpty ? "This archive needs a password." : "Wrong password. Try again."
            } else {
                self.errorMessage = Self.errorSummary(r.output, status: r.status)
            }
        }
    }

    private func loadRARListing(_ archive: URL, password pw: String) {
        guard let lsar = lsarPath else { return }
        let args = Self.lsarArguments(archive: archive.path, password: pw)
        task = Task { [weak self] in
            guard let self, let r = await self.perform(exe: lsar, args: args, input: nil, trackProgress: false) else { return }
            if r.cancelled { return }
            if r.status == 0 {
                if let list = Self.parseLsar(r.output) {
                    self.entries = list
                    self.needsPassword = false
                } else {
                    self.errorMessage = "Couldn't read this archive."
                }
                return
            }
            switch Self.classifyLsar(r.output, status: r.status) {
            case .needsPassword, .wrongPassword:
                self.needsPassword = true
                self.errorMessage = pw.isEmpty ? "This archive needs a password." : "Wrong password. Try again."
            default:
                // RAR3 with encrypted names reports a wrong password only as a generic read error.
                self.errorMessage = self.needsPassword && !pw.isEmpty
                    ? "Wrong password. Try again." : Self.unarErrorSummary(r.output, status: r.status)
            }
        }
    }

    /// Test first when encrypted (a wrong password still writes junk files), extract, then remove unsafe symlinks.
    private func extractRAR(archive: URL, dest: URL, password pw: String, encrypted: Bool) {
        guard let unar = unarPath, let lsar = lsarPath else { return }
        // Held across the snapshot so a second click cannot start another run.
        isBusy = true
        task = Task { [weak self] in
            guard let self else { return }
            let before = await Task.detached { Self.snapshotSymlinks(in: dest) }.value
            if encrypted {
                let testArgs = Self.lsarTestArguments(archive: archive.path, password: pw)
                guard let t = await self.perform(exe: lsar, args: testArgs, input: nil, trackProgress: false) else { return }
                if t.cancelled {
                    self.statusMessage = "Cancelled."
                    return
                }
                switch Self.classifyLsar(t.output, status: t.status) {
                case .ok:
                    break
                case .needsPassword, .wrongPassword:
                    self.needsPassword = true
                    self.errorMessage = pw.isEmpty ? "This archive needs a password." : "Wrong password. Try again."
                    return
                case .failed:
                    self.errorMessage = Self.unarErrorSummary(t.output, status: t.status)
                    return
                }
            }
            let args = Self.unarArguments(archive: archive.path, outputDir: dest.path, password: pw)
            let r = await self.perform(exe: unar, args: args, input: nil, trackProgress: false)
            self.isBusy = true
            let removed = await Task.detached { Self.removeUnsafeLinks(in: dest, preExisting: before) }.value
            self.isBusy = false
            guard let r else { return }
            if r.cancelled {
                self.statusMessage = "Cancelled."
            } else if r.status == 0 {
                self.statusMessage = "Extracted to \(dest.lastPathComponent)."
                    + (removed > 0 ? " Removed \(removed) unsafe link(s)." : "")
                self.resultURL = dest
            } else {
                self.errorMessage = Self.unarErrorSummary(r.output, status: r.status)
            }
        }
    }

    /// `toFolder`: new folder named after the archive; otherwise next to the archive. `-aou` never overwrites.
    func extract(toFolder: Bool) {
        guard let archive = archiveURL, !isBusy else { return }
        let parent = archive.deletingLastPathComponent()
        let dest = toFolder
            ? Self.uniqueURL(parent.appendingPathComponent(Self.archiveBaseName(archive.lastPathComponent), isDirectory: true),
                             exists: { FileManager.default.fileExists(atPath: $0.path) })
            : parent
        let pw = extractPassword
        let encrypted = entries.contains { $0.isEncrypted }
        if encrypted && pw.isEmpty {
            needsPassword = true
            errorMessage = "This archive needs a password."
            return
        }
        if Self.isRAR(archive.lastPathComponent) {
            extractRAR(archive: archive, dest: dest, password: pw, encrypted: encrypted)
            return
        }
        let input = pw.isEmpty ? nil : Self.passwordInput(pw, confirm: false)
        let args = Self.extractArguments(archive: archive.path, outputDir: dest.path)
        task = Task { [weak self] in
            guard let self else { return }
            // A wrong password still writes junk files, so check it before extracting.
            if encrypted {
                guard let t = await self.perform(args: Self.testArguments(archive: archive.path), input: input) else { return }
                if t.cancelled {
                    self.statusMessage = "Cancelled."
                    return
                }
                if !Self.succeeded(t.status) {
                    if Self.isPasswordFailure(t.output) {
                        self.needsPassword = true
                        self.errorMessage = "Wrong password. Try again."
                    } else {
                        self.errorMessage = Self.errorSummary(t.output, status: t.status)
                    }
                    return
                }
            }
            guard let r = await self.perform(args: args, input: input) else { return }
            if r.cancelled {
                self.statusMessage = "Cancelled."
            } else if Self.succeeded(r.status) {
                self.statusMessage = "Extracted to \(dest.lastPathComponent)."
                self.resultURL = dest
            } else if Self.isPasswordFailure(r.output) {
                self.needsPassword = true
                self.errorMessage = pw.isEmpty ? "This archive needs a password." : "Wrong password. Try again."
            } else {
                self.errorMessage = Self.errorSummary(r.output, status: r.status)
            }
        }
    }

    // MARK: - Compress

    func addItems(_ urls: [URL]) {
        guard !isBusy else { return }
        for url in urls where !items.contains(url) { items.append(url) }
        statusMessage = nil
        errorMessage = nil
        resultURL = nil
    }

    func clearItems() {
        guard !isBusy else { return }
        items = []
        compressPassword = ""
    }

    func compress() {
        guard let first = items.first, !isBusy else { return }
        let base = first.deletingLastPathComponent()
        let isDirectory = (try? first.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        let stem = isDirectory ? first.lastPathComponent : first.deletingPathExtension().lastPathComponent
        let output = Self.uniqueURL(base.appendingPathComponent("\(stem).\(format.fileExtension)"),
                                    exists: { FileManager.default.fileExists(atPath: $0.path) })
        let pw = compressPassword
        guard Self.canUsePassword(pw, format: format) else {
            errorMessage = "ZIP passwords can only use English letters, digits and symbols. Choose 7z for other characters."
            return
        }
        let args = Self.compressArguments(output: output.path, items: items.map { Self.itemArgument($0, base: base) },
                                          format: format, level: level, usePassword: !pw.isEmpty)
        task = Task { [weak self] in
            guard let self,
                  let r = await self.perform(args: args, input: pw.isEmpty ? nil : Self.passwordInput(pw, confirm: true),
                                             cwd: base)
            else { return }
            if r.cancelled {
                // The name was unique when chosen, so this run created the file.
                try? FileManager.default.removeItem(at: output)
                self.statusMessage = "Cancelled."
            } else if Self.succeeded(r.status) {
                self.statusMessage = "Created \(output.lastPathComponent)."
                self.resultURL = output
            } else {
                self.errorMessage = Self.errorSummary(r.output, status: r.status)
            }
        }
    }

    // MARK: - Monitoring

    func stopMonitoring() {
        task?.cancel()
        handle?.cancel()
        extractPassword = ""
        compressPassword = ""
    }
}
