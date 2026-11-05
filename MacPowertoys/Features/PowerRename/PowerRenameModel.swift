import Foundation

struct RenameOptions: Equatable {
    var search = ""
    var replace = ""
    var useRegex = false
    var caseSensitive = false
    var numbering = false
    var includeExtension = false
}

struct RenameRow: Identifiable, Equatable {
    enum Status: Equatable {
        case changed, unchanged
        case conflict(String)
    }
    let url: URL
    let newName: String
    let status: Status
    var id: String { url.path }
    var oldName: String { url.lastPathComponent }
}

struct RenamePlan: Equatable {
    var rows: [RenameRow] = []
    var regexError: String?
    var hasConflict: Bool {
        rows.contains { if case .conflict = $0.status { return true } else { return false } }
    }
    var changedCount: Int { rows.filter { $0.status == .changed }.count }
    var canApply: Bool { regexError == nil && !hasConflict && changedCount > 0 }
}

struct RenameMove: Equatable {
    let from: URL
    let to: URL
}

struct RenameFailure: Error, Equatable {
    let message: String
}

@MainActor
final class PowerRenameModel: ObservableObject {
    // MARK: - Runtime State

    @Published var search = "" { didSet { refreshPlan() } }
    @Published var replace = "" { didSet { refreshPlan() } }
    @Published var useRegex = false { didSet { refreshPlan() } }
    @Published var caseSensitive = false { didSet { refreshPlan() } }
    @Published var numbering = false { didSet { refreshPlan() } }
    @Published var includeExtension = false { didSet { refreshPlan() } }
    @Published private(set) var files: [URL] = []
    @Published private(set) var plan = RenamePlan()
    @Published private(set) var message: String?
    @Published private(set) var lastBatch: [RenameMove] = []

    // MARK: - Private

    private var options: RenameOptions {
        RenameOptions(search: search, replace: replace, useRegex: useRegex, caseSensitive: caseSensitive,
                      numbering: numbering, includeExtension: includeExtension)
    }

    var hubStatusText: String {
        files.isEmpty ? "Ready" : (files.count == 1 ? "1 file" : "\(files.count) files")
    }

    // MARK: - Planning (pure)

    nonisolated static func plan(urls: [URL], options: RenameOptions,
                                 exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> RenamePlan {
        var regex: NSRegularExpression?
        if !options.search.isEmpty {
            let pattern = options.useRegex ? options.search : NSRegularExpression.escapedPattern(for: options.search)
            do {
                regex = try NSRegularExpression(pattern: pattern, options: options.caseSensitive ? [] : [.caseInsensitive])
            } catch {
                return RenamePlan(rows: urls.map { RenameRow(url: $0, newName: $0.lastPathComponent, status: .unchanged) },
                                  regexError: "Invalid regular expression")
            }
        }

        var newNames: [String] = []
        var emptyStem: [Bool] = []
        for (index, url) in urls.enumerated() {
            let name = url.lastPathComponent
            guard let regex else { newNames.append(name); emptyStem.append(false); continue }
            let ext = options.includeExtension ? "" : (name as NSString).pathExtension
            let stem = options.includeExtension ? name : (name as NSString).deletingPathExtension
            var replacement = options.replace
            if options.numbering { replacement = replacement.replacingOccurrences(of: "{n}", with: String(index + 1)) }
            let template = options.useRegex ? replacement : NSRegularExpression.escapedTemplate(for: replacement)
            let newStem = regex.stringByReplacingMatches(in: stem, range: NSRange(stem.startIndex..., in: stem), withTemplate: template)
            emptyStem.append(newStem.isEmpty)
            newNames.append(ext.isEmpty ? newStem : newStem + "." + ext)
        }

        func key(_ url: URL, _ name: String) -> String {
            url.deletingLastPathComponent().standardizedFileURL.path + "\n" + name.lowercased()
        }
        let oldKeys = Set(urls.map { key($0, $0.lastPathComponent) })
        var finalCounts: [String: Int] = [:]
        for (url, name) in zip(urls, newNames) { finalCounts[key(url, name), default: 0] += 1 }

        var rows: [RenameRow] = []
        for (i, url) in urls.enumerated() {
            let name = newNames[i]
            let status: RenameRow.Status
            if name == url.lastPathComponent {
                status = .unchanged
            } else if name.isEmpty || emptyStem[i] {
                status = .conflict("Empty name")
            } else if name.contains("/") {
                status = .conflict("Name contains /")
            } else if finalCounts[key(url, name), default: 0] > 1 {
                status = .conflict("Duplicate name")
            } else if !oldKeys.contains(key(url, name)) && exists(url.deletingLastPathComponent().appendingPathComponent(name)) {
                status = .conflict("Already exists")
            } else {
                status = .changed
            }
            rows.append(RenameRow(url: url, newName: name, status: status))
        }
        return RenamePlan(rows: rows, regexError: nil)
    }

    // MARK: - Applying

    /// Renames via temporary names so chains, swaps and case-only renames work. On failure everything
    /// already moved is rolled back.
    nonisolated static func apply(_ moves: [RenameMove]) throws {
        let fm = FileManager.default
        var done: [RenameMove] = []
        func move(_ from: URL, _ to: URL) throws {
            try fm.moveItem(at: from, to: to)
            done.append(RenameMove(from: from, to: to))
        }
        do {
            var temps: [(temp: URL, move: RenameMove)] = []
            for m in moves {
                let temp = m.from.deletingLastPathComponent().appendingPathComponent(".powerrename-\(UUID().uuidString)")
                try move(m.from, temp)
                temps.append((temp, m))
            }
            for t in temps { try move(t.temp, t.move.to) }
        } catch {
            var rollbackFailures = 0
            for m in done.reversed() {
                do { try fm.moveItem(at: m.to, to: m.from) } catch { rollbackFailures += 1 }
            }
            var text = "Rename failed: \(error.localizedDescription). Changes were rolled back."
            if rollbackFailures > 0 { text = "Rename failed: \(error.localizedDescription). \(rollbackFailures) file(s) could not be restored." }
            throw RenameFailure(message: text)
        }
    }

    // MARK: - Files

    func addFiles(_ urls: [URL]) {
        for url in urls where !files.contains(where: { $0.path == url.path }) { files.append(url) }
        message = nil
        refreshPlan()
    }

    func clear() {
        files = []
        message = nil
        refreshPlan()
    }

    func applyRename() {
        guard plan.canApply else { return }
        let moves = plan.rows.filter { $0.status == .changed }.map {
            RenameMove(from: $0.url, to: $0.url.deletingLastPathComponent().appendingPathComponent($0.newName))
        }
        do {
            try Self.apply(moves)
        } catch {
            let text = (error as? RenameFailure)?.message ?? error.localizedDescription
            NSLog("[PowerRename] %@", text)
            message = text
            refreshPlan()
            return
        }
        let renamed = Dictionary(uniqueKeysWithValues: moves.map { ($0.from.path, $0.to) })
        files = files.map { renamed[$0.path] ?? $0 }
        lastBatch = moves
        message = "Renamed \(moves.count) file(s)."
        search = ""
    }

    func undo() {
        let fm = FileManager.default
        let present = lastBatch.filter { fm.fileExists(atPath: $0.to.path) }
        let missing = lastBatch.count - present.count
        do {
            try Self.apply(present.map { RenameMove(from: $0.to, to: $0.from) })
        } catch {
            message = (error as? RenameFailure)?.message ?? error.localizedDescription
            return
        }
        let restored = Dictionary(uniqueKeysWithValues: present.map { ($0.to.path, $0.from) })
        files = files.map { restored[$0.path] ?? $0 }
        lastBatch = []
        refreshPlan()
        message = missing > 0 ? "Undone \(present.count); \(missing) file(s) had moved and were skipped."
                              : "Undone \(present.count) file(s)."
    }

    private func refreshPlan() {
        plan = Self.plan(urls: files, options: options)
    }

    // MARK: - Monitoring

    func stopMonitoring() {}
}
