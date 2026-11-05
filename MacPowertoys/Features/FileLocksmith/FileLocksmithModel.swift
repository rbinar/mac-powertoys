import Foundation
import Darwin

struct LockingProcess: Identifiable, Equatable {
    let pid: Int32
    let name: String
    let user: String
    var id: Int32 { pid }
}

/// Holds the running lsof so `stopMonitoring()` can cancel it from the main actor.
private final class LsofHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var _cancelled = false
    private var _timedOut = false

    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return _cancelled }
    var timedOut: Bool { lock.lock(); defer { lock.unlock() }; return _timedOut }

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
    func timeout() {
        lock.lock(); defer { lock.unlock() }
        _timedOut = true
        process?.terminate()
    }
}

@MainActor
final class FileLocksmithModel: ObservableObject {
    // MARK: - Runtime State

    @Published private(set) var targetURL: URL?
    @Published private(set) var processes: [LockingProcess] = []
    @Published private(set) var hasResult = false
    @Published private(set) var isScanning = false
    @Published private(set) var errorMessage: String?
    /// Processes that were sent SIGTERM and were still present on the following refresh.
    @Published private(set) var stubbornPIDs: Set<Int32> = []

    // MARK: - Private

    private static let lsofTimeout: TimeInterval = 10
    private var handle: LsofHandle?
    private var scanTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var termSent: Set<Int32> = []

    var hubStatusText: String {
        guard hasResult else { return "Ready" }
        return processes.count == 1 ? "1 process" : "\(processes.count) processes"
    }

    // MARK: - Parsing / safety (pure)

    /// Parses `lsof -F pcuL` output. A `p` line starts a record; duplicate pids collapse to the first.
    nonisolated static func parse(_ output: String) -> [LockingProcess] {
        var result: [LockingProcess] = []
        var seen = Set<Int32>()
        var pid: Int32?
        var name = ""
        var login: String?
        var uid: String?

        func flush() {
            guard let p = pid, !seen.contains(p) else { return }
            seen.insert(p)
            let user = login ?? uid.map { "uid \($0)" } ?? "unknown"
            result.append(LockingProcess(pid: p, name: name.isEmpty ? "Unknown" : name, user: user))
        }

        for line in output.split(whereSeparator: \.isNewline) {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())
            switch tag {
            case "p":
                flush()
                pid = Int32(value); name = ""; login = nil; uid = nil
            case "c": name = value
            case "u": uid = value
            case "L": login = value
            default: break
            }
        }
        flush()
        return result
    }

    nonisolated static func isSafeToSignal(pid: Int32, ownPID: Int32 = getpid()) -> Bool {
        pid > 1 && pid != ownPID
    }

    // MARK: - Target / scan

    func setTarget(_ url: URL) {
        targetURL = url
        termSent = []
        stubbornPIDs = []
        hasResult = false
        processes = []
        refresh()
    }

    func refresh() {
        guard let url = targetURL else { return }
        scanTask?.cancel()
        handle?.cancel()
        let newHandle = LsofHandle()
        handle = newHandle
        isScanning = true
        errorMessage = nil
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        let path = url.path

        scanTask = Task { [weak self] in
            let outcome = await Task.detached(priority: .userInitiated) {
                Self.runLsof(path: path, isDirectory: isDirectory, handle: newHandle)
            }.value
            guard let self, !Task.isCancelled, self.handle === newHandle else { return }
            self.isScanning = false
            switch outcome {
            case .success(let found):
                self.processes = found
                self.hasResult = true
                let present = Set(found.map(\.pid))
                self.termSent = self.termSent.intersection(present)
                self.stubbornPIDs = self.termSent
            case .failure(let message):
                self.errorMessage = message
            case .cancelled:
                break
            }
        }
    }

    private enum LsofOutcome: Sendable {
        case success([LockingProcess])
        case failure(String)
        case cancelled
    }

    private nonisolated static func runLsof(path: String, isDirectory: Bool, handle: LsofHandle) -> LsofOutcome {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = isDirectory
            ? ["+c", "0", "-F", "pcuL", "+D", path]
            : ["+c", "0", "-F", "pcuL", "--", path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            NSLog("[FileLocksmith] lsof failed to start: %@", error.localizedDescription)
            return .failure("Could not run lsof.")
        }
        handle.set(process)
        let timer = DispatchWorkItem { handle.timeout() }
        DispatchQueue.global().asyncAfter(deadline: .now() + lsofTimeout, execute: timer)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timer.cancel()

        if handle.cancelled { return .cancelled }
        if handle.timedOut { return .failure("lsof timed out after 10 seconds.") }
        // lsof exits 1 when nothing is found.
        guard process.terminationStatus == 0 || process.terminationStatus == 1 else {
            return .failure("lsof failed (exit \(process.terminationStatus)).")
        }
        return .success(parse(String(decoding: data, as: UTF8.self)))
    }

    // MARK: - Signals

    /// Sends the signal and refreshes afterwards. Callers must have confirmed with the user.
    func signal(_ process: LockingProcess, force: Bool) {
        guard Self.isSafeToSignal(pid: process.pid) else {
            errorMessage = "Refusing to signal PID \(process.pid)."
            return
        }
        if kill(process.pid, force ? SIGKILL : SIGTERM) != 0 {
            NSLog("[FileLocksmith] kill failed for pid %d: errno %d", process.pid, errno)
            errorMessage = "Could not quit \(process.name) (PID \(process.pid))."
            return
        }
        if !force { termSent.insert(process.pid) }
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    // MARK: - Monitoring

    func stopMonitoring() {
        scanTask?.cancel()
        refreshTask?.cancel()
        handle?.cancel()
        handle = nil
        isScanning = false
    }
}
