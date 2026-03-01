import Foundation
import AppKit
import Carbon.HIToolbox
import UserNotifications

// MARK: - Data Models

enum LaunchAction: Codable, Equatable {
    case app(path: String)
    case file(path: String)
    case folder(path: String)
    case url(urlString: String)
    case shellCommand(command: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case path
        case urlString
        case command
    }

    private enum ActionType: String, Codable {
        case app, file, folder, url, shellCommand
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ActionType.self, forKey: .type)
        switch type {
        case .app:
            let path = try container.decode(String.self, forKey: .path)
            self = .app(path: path)
        case .file:
            let path = try container.decode(String.self, forKey: .path)
            self = .file(path: path)
        case .folder:
            let path = try container.decode(String.self, forKey: .path)
            self = .folder(path: path)
        case .url:
            let urlString = try container.decode(String.self, forKey: .urlString)
            self = .url(urlString: urlString)
        case .shellCommand:
            let command = try container.decode(String.self, forKey: .command)
            self = .shellCommand(command: command)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .app(let path):
            try container.encode(ActionType.app, forKey: .type)
            try container.encode(path, forKey: .path)
        case .file(let path):
            try container.encode(ActionType.file, forKey: .type)
            try container.encode(path, forKey: .path)
        case .folder(let path):
            try container.encode(ActionType.folder, forKey: .type)
            try container.encode(path, forKey: .path)
        case .url(let urlString):
            try container.encode(ActionType.url, forKey: .type)
            try container.encode(urlString, forKey: .urlString)
        case .shellCommand(let command):
            try container.encode(ActionType.shellCommand, forKey: .type)
            try container.encode(command, forKey: .command)
        }
    }
}

struct LaunchEntry: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var subtitle: String
    var action: LaunchAction
    var keywords: [String]
    var isCustom: Bool
    let createdAt: Date
    var lastUsedAt: Date?
    var useCount: Int
}

private struct QuickLaunchHotKey {
    static let signature = OSType(0x514C4348)
    static let togglePanelID: UInt32 = 1
    static let keyCode: UInt32 = UInt32(kVK_Space)
    static let modifiers: UInt32 = UInt32(controlKey | optionKey)
}

// MARK: - Carbon Hotkey Handler

private func quickLaunchHotKeyHandler(nextHandler: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let userData, let event else { return OSStatus(eventNotHandledErr) }
    let model = Unmanaged<QuickLaunchModel>.fromOpaque(userData).takeUnretainedValue()

    var hotKeyID = EventHotKeyID()
    GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)

    switch hotKeyID.id {
    case QuickLaunchHotKey.togglePanelID:
        Task { @MainActor in
            model.togglePanel()
        }
        return noErr
    default:
        return OSStatus(eventNotHandledErr)
    }
}

// MARK: - QuickLaunchModel

@MainActor
final class QuickLaunchModel: ObservableObject {

    // MARK: - Published Properties

    @Published var customEntries: [LaunchEntry] = []
    @Published var indexedApps: [LaunchEntry] = []
    @Published var searchText: String = "" {
        didSet { performSearch() }
    }
    @Published private(set) var searchResults: [LaunchEntry] = []
    @Published var selectedIndex: Int = 0
    @Published var isPanelVisible: Bool = false
    @Published var isAddingEntry: Bool = false
    @Published var editingEntry: LaunchEntry? = nil

    // MARK: - Private Properties

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    static let maxVisibleResults = 8

    private var scanTimer: Timer?
    private var clickMonitor: Any?
    private var appDeactivationObserver: Any?
    private(set) var panelController: QuickLaunchPanelController?

    // MARK: - Lifecycle

    init() {
        loadEntries()
        registerCarbonHotKey()
        scanApplications()
        startScanTimer()
        requestNotificationPermission()
        panelController = QuickLaunchPanelController(model: self)
    }

    func stopMonitoring() {
        unregisterCarbonHotKey()
        stopScanTimer()
        panelController?.cleanup()

        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
        if let appDeactivationObserver {
            NotificationCenter.default.removeObserver(appDeactivationObserver)
            self.appDeactivationObserver = nil
        }
    }

    // MARK: - Hotkey Registration

    private func registerCarbonHotKey() {
        guard hotKeyRef == nil else { return }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), quickLaunchHotKeyHandler, 1, &eventType, selfPtr, &eventHandlerRef)

        var hotKeyID = EventHotKeyID(signature: QuickLaunchHotKey.signature, id: QuickLaunchHotKey.togglePanelID)
        RegisterEventHotKey(QuickLaunchHotKey.keyCode, QuickLaunchHotKey.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    private func unregisterCarbonHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    // MARK: - Panel Control

    func togglePanel() {
        if isPanelVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    func showPanel() {
        isPanelVisible = true
        if indexedApps.isEmpty {
            scanApplications()
        }
        performSearch()
        panelController?.showPanel()
    }

    func hidePanel() {
        guard isPanelVisible else { return }
        isPanelVisible = false
        searchText = ""
        selectedIndex = 0
        panelController?.hidePanelWindow()
    }

    // MARK: - App Indexing

    func scanApplications() {
        var entries: [LaunchEntry] = []
        let fileManager = FileManager.default

        let appDirectories = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications")
        ]

        for directory in appDirectories {
            guard let items = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey]) else { continue }

            for item in items {
                if item.pathExtension == "app" {
                    if let entry = createAppEntry(from: item) {
                        entries.append(entry)
                    }
                } else {
                    let isDirectory = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                    if isDirectory {
                        guard let subItems = try? fileManager.contentsOfDirectory(at: item, includingPropertiesForKeys: [.isDirectoryKey]) else { continue }
                        for subItem in subItems where subItem.pathExtension == "app" {
                            if let entry = createAppEntry(from: subItem) {
                                entries.append(entry)
                            }
                        }
                    }
                }
            }
        }

        entries.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        indexedApps = entries
    }

    private func createAppEntry(from url: URL) -> LaunchEntry? {
        let bundle = Bundle(url: url)
        let info = bundle?.infoDictionary
        let displayName = info?["CFBundleDisplayName"] as? String
            ?? info?["CFBundleName"] as? String
            ?? url.deletingPathExtension().lastPathComponent

        var keywords: [String] = displayName.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        if let bundleID = bundle?.bundleIdentifier {
            keywords += bundleID.components(separatedBy: ".").filter { !$0.isEmpty }
        }

        return LaunchEntry(
            id: UUID(),
            name: displayName,
            subtitle: url.path,
            action: .app(path: url.path),
            keywords: keywords,
            isCustom: false,
            createdAt: Date(),
            lastUsedAt: nil,
            useCount: 0
        )
    }

    private func startScanTimer() {
        stopScanTimer()
        scanTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.scanApplications()
            }
        }
    }

    private func stopScanTimer() {
        scanTimer?.invalidate()
        scanTimer = nil
    }

    // MARK: - Search Engine

    private func performSearch() {
        if searchText.isEmpty {
            let sortedCustom = customEntries.sorted { frecencyScore(for: $0) > frecencyScore(for: $1) }
            searchResults = Array(sortedCustom.prefix(Self.maxVisibleResults))
        } else {
            let allEntries = customEntries
            let query = searchText

            var scored: [(entry: LaunchEntry, score: Int)] = []
            for entry in allEntries {
                var bestScore: Int?

                if let nameScore = fuzzyScore(query, against: entry.name) {
                    bestScore = nameScore
                }
                for keyword in entry.keywords {
                    if let keywordScore = fuzzyScore(query, against: keyword) {
                        if bestScore == nil || keywordScore > bestScore! {
                            bestScore = keywordScore
                        }
                    }
                }

                if let score = bestScore {
                    scored.append((entry, score))
                }
            }

            scored.sort { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return frecencyScore(for: lhs.entry) > frecencyScore(for: rhs.entry)
            }

            searchResults = Array(scored.prefix(Self.maxVisibleResults).map(\.entry))
        }
        selectedIndex = 0
    }

    func fuzzyScore(_ query: String, against candidate: String) -> Int? {
        let queryLower = query.lowercased()
        let candidateLower = candidate.lowercased()
        let candidateChars = Array(candidateLower)
        let originalChars = Array(candidate)

        var score = 0
        var candidateIndex = 0
        var previousMatchIndex = -2

        for queryChar in queryLower {
            var matched = false
            while candidateIndex < candidateChars.count {
                if candidateChars[candidateIndex] == queryChar {
                    let isWordBoundary = candidateIndex == 0
                        || candidateChars[candidateIndex - 1] == " "
                        || candidateChars[candidateIndex - 1] == "-"
                        || candidateChars[candidateIndex - 1] == "."
                        || (originalChars[candidateIndex].isUppercase && !originalChars[max(0, candidateIndex - 1)].isUppercase)

                    if isWordBoundary {
                        score += 3
                    } else if candidateIndex == previousMatchIndex + 1 {
                        score += 2
                    } else {
                        score += 1
                    }

                    previousMatchIndex = candidateIndex
                    candidateIndex += 1
                    matched = true
                    break
                }
                candidateIndex += 1
            }
            if !matched { return nil }
        }

        return score
    }

    private func frecencyScore(for entry: LaunchEntry) -> Double {
        let countFactor = 1.0 + log2(Double(entry.useCount) + 1)
        let recencyFactor: Double

        if let lastUsed = entry.lastUsedAt {
            let elapsed = Date().timeIntervalSince(lastUsed)
            if elapsed < 86400 {
                recencyFactor = 1.0
            } else if elapsed < 604800 {
                recencyFactor = 0.8
            } else if elapsed < 2_592_000 {
                recencyFactor = 0.5
            } else {
                recencyFactor = 0.3
            }
        } else {
            recencyFactor = 0.3
        }

        return countFactor * recencyFactor
    }

    // MARK: - Launch Execution

    func launchEntry(_ entry: LaunchEntry) {
        recordUsage(entry.id)

        switch entry.action {
        case .app(let path):
            let appURL = URL(fileURLWithPath: path)
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(at: appURL, configuration: config) { [weak self] _, error in
                if let error {
                    Task { @MainActor in
                        self?.sendErrorNotification(title: "Launch Failed", body: error.localizedDescription)
                    }
                }
            }

        case .file(let path):
            NSWorkspace.shared.open(URL(fileURLWithPath: path))

        case .folder(let path):
            NSWorkspace.shared.open(URL(fileURLWithPath: path))

        case .url(let urlString):
            if let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }

        case .shellCommand(let command):
            executeShellCommand(command)
        }

        hidePanel()
    }

    private func executeShellCommand(_ command: String) {
        Task.detached { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", command]
            let errorPipe = Pipe()
            process.standardError = errorPipe
            process.standardOutput = FileHandle.nullDevice

            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus != 0 {
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                    await self?.sendErrorNotification(
                        title: "Command Failed",
                        body: String(errorMessage.prefix(200))
                    )
                }
            } catch {
                await self?.sendErrorNotification(
                    title: "Command Failed",
                    body: error.localizedDescription
                )
            }
        }
    }

    // MARK: - Error Notifications

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func sendErrorNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = "Quick Launch — \(title)"
        content.body = body
        content.sound = .default
        content.threadIdentifier = "quickLaunch"
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    // MARK: - Entry Management

    func addEntry(name: String, action: LaunchAction, keywords: [String]) {
        let entry = LaunchEntry(
            id: UUID(),
            name: name,
            subtitle: subtitleForAction(action),
            action: action,
            keywords: keywords,
            isCustom: true,
            createdAt: Date(),
            lastUsedAt: nil,
            useCount: 0
        )
        customEntries.insert(entry, at: 0)
        saveEntries()
    }

    func updateEntry(_ entry: LaunchEntry) {
        if let index = customEntries.firstIndex(where: { $0.id == entry.id }) {
            customEntries[index] = entry
            saveEntries()
        }
    }

    func deleteEntry(_ entry: LaunchEntry) {
        customEntries.removeAll { $0.id == entry.id }
        saveEntries()
    }

    private func recordUsage(_ id: UUID) {
        if let index = customEntries.firstIndex(where: { $0.id == id }) {
            customEntries[index].useCount += 1
            customEntries[index].lastUsedAt = Date()
            saveEntries()
        } else if let index = indexedApps.firstIndex(where: { $0.id == id }) {
            indexedApps[index].useCount += 1
            indexedApps[index].lastUsedAt = Date()
        }
    }

    func subtitleForAction(_ action: LaunchAction) -> String {
        switch action {
        case .app(let path):
            return URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        case .file(let path):
            return path
        case .folder(let path):
            return path
        case .url(let urlString):
            return urlString
        case .shellCommand(let command):
            return String(command.prefix(50))
        }
    }

    // MARK: - Persistence

    private func saveEntries() {
        do {
            let data = try JSONEncoder().encode(customEntries)
            UserDefaults.standard.set(data, forKey: "quickLaunch.customEntries")
        } catch {
            NSLog("[QuickLaunch] Failed to encode entries: %@", String(describing: error))
        }
    }

    private func loadEntries() {
        guard let data = UserDefaults.standard.data(forKey: "quickLaunch.customEntries") else { return }
        do {
            customEntries = try JSONDecoder().decode([LaunchEntry].self, from: data)
        } catch {
            NSLog("[QuickLaunch] Failed to decode entries: %@", String(describing: error))
        }
    }

    // MARK: - Keyboard Navigation

    func moveSelectionUp() {
        guard !searchResults.isEmpty else { return }
        selectedIndex = max(0, selectedIndex - 1)
    }

    func moveSelectionDown() {
        guard !searchResults.isEmpty else { return }
        let visibleCount = min(searchResults.count, Self.maxVisibleResults)
        selectedIndex = min(visibleCount - 1, selectedIndex + 1)
    }

    func launchSelected() {
        guard !searchResults.isEmpty, selectedIndex >= 0, selectedIndex < searchResults.count else { return }
        launchEntry(searchResults[selectedIndex])
    }
}
