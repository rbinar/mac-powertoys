import Foundation
import AppKit
import Combine
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
    var faviconData: Data?
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

    guard hotKeyID.signature == QuickLaunchHotKey.signature else { return OSStatus(eventNotHandledErr) }
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

    // MARK: - Command Palette State

    /// Module commands, set by the module registry.
    var commands: [PaletteCommand] = [] {
        didSet { performSearch() }
    }
    @Published private(set) var recentCommandIDs: [String] = UserDefaults.standard.stringArray(forKey: "quickLaunch.recentCommands") ?? []
    @Published private(set) var sections: [PaletteSection] = []
    /// Non-nil while the panel shows a module's screen instead of the list.
    @Published private(set) var activeScreen: PaletteCommand? = nil
    static let maxRecentCommands = 5

    var flatItems: [PaletteItem] { sections.flatMap(\.items) }

    // MARK: - Private Properties

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    static let maxVisibleResults = 8

    private var scanTimer: Timer?
    private(set) var panelController: QuickLaunchPanelController?
    private var paletteRequests = Set<AnyCancellable>()

    // MARK: - Lifecycle

    init() {
        loadEntries()
        registerCarbonHotKey()
        scanApplications()
        startScanTimer()
        panelController = QuickLaunchPanelController(model: self)
        observePaletteRequests()
    }

    func stopMonitoring() {
        unregisterCarbonHotKey()
        stopScanTimer()
        panelController?.cleanup()
        paletteRequests.removeAll()

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

    /// Other modules ask the palette to open one of their screens (ModuleNotifications.openPaletteScreen / hidePalette).
    private func observePaletteRequests() {
        NotificationCenter.default.publisher(for: ModuleNotifications.openPaletteScreen)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let id = note.object as? String else { return }
                MainActor.assumeIsolated { self?.openPaletteScreen(commandID: id) }
            }
            .store(in: &paletteRequests)
        NotificationCenter.default.publisher(for: ModuleNotifications.hidePalette)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.hidePanel() } }
            .store(in: &paletteRequests)
    }

    func openPaletteScreen(commandID: String) {
        guard let command = commands.first(where: { $0.id == commandID }), command.screen != nil else { return }
        openScreen(of: command)  // before showPanel so the panel opens at the screen's size
        if !isPanelVisible { showPanel() }
    }

    func hidePanel() {
        guard isPanelVisible else { return }
        isPanelVisible = false
        activeScreen = nil
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

        // Preserve frecency accumulated since the last scan by merging useCount/lastUsedAt
        // from the current indexedApps into the freshly-scanned entries (matched by app path).
        let frecencyByPath: [String: (useCount: Int, lastUsedAt: Date?)] = Dictionary(
            uniqueKeysWithValues: indexedApps.compactMap { entry -> (String, (Int, Date?))? in
                guard case .app(let path) = entry.action else { return nil }
                return (path, (entry.useCount, entry.lastUsedAt))
            }
        )
        for index in entries.indices {
            if case .app(let path) = entries[index].action,
               let frecency = frecencyByPath[path] {
                entries[index].useCount = frecency.useCount
                entries[index].lastUsedAt = frecency.lastUsedAt
            }
        }

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
            let allEntries = customEntries + indexedApps
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
        buildSections()
    }

    private func buildSections() {
        var result: [PaletteSection] = []
        let query = searchText

        if query.isEmpty {
            // Modes that are currently on, so they can be switched off quickly.
            let active = commands.filter { $0.group == .modes && ($0.isOn?() ?? false) }
            if !active.isEmpty {
                result.append(PaletteSection(
                    id: "active", title: "Active",
                    items: active.map { .command($0, rowID: "active." + $0.id) }
                ))
            }
            let recents = recentCommandIDs.compactMap { id in commands.first { $0.id == id } }
            if !recents.isEmpty {
                result.append(PaletteSection(
                    id: "recent", title: "Recent",
                    items: recents.map { .command($0, rowID: "recent." + $0.id) }
                ))
            }
            for group in PaletteCommand.Group.allCases {
                let groupCommands = commands.filter { $0.group == group }
                if !groupCommands.isEmpty {
                    result.append(PaletteSection(
                        id: "group." + group.rawValue, title: group.rawValue,
                        items: groupCommands.map { .command($0, rowID: $0.id) }
                    ))
                }
            }
            if !searchResults.isEmpty {
                result.append(PaletteSection(id: "shortcuts", title: "My Shortcuts", items: searchResults.map { .entry($0) }))
            }
        } else {
            var scored: [(command: PaletteCommand, score: Int)] = []
            for command in commands {
                let candidates = [command.title, command.subtitle] + command.keywords
                if let best = candidates.compactMap({ fuzzyScore(query, against: $0) }).max() {
                    scored.append((command, best))
                }
            }
            // sorted(by:) is not stable; break ties by original order.
            let ordered = scored.enumerated().sorted { lhs, rhs in
                if lhs.element.score != rhs.element.score { return lhs.element.score > rhs.element.score }
                return lhs.offset < rhs.offset
            }.map(\.element.command)
            if !ordered.isEmpty {
                result.append(PaletteSection(
                    id: "commands", title: "Commands",
                    items: ordered.prefix(Self.maxVisibleResults).map { .command($0, rowID: $0.id) }
                ))
            }
            if !searchResults.isEmpty {
                result.append(PaletteSection(id: "results", title: nil, items: searchResults.map { .entry($0) }))
            }
        }
        sections = result
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

    private func sendErrorNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = "Quick Launch — \(title)"
        content.body = body
        content.sound = .default
        content.threadIdentifier = "quickLaunch"
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            UNUserNotificationCenter.current().add(request) { _ in }
        }
    }

    // MARK: - Favicon

    private func fetchFavicon(for entryId: UUID, urlString: String) {
        guard let url = URL(string: urlString), let host = url.host else { return }
        guard let faviconURL = URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=64") else { return }

        Task.detached { [weak self] in
            do {
                let (data, response) = try await URLSession.shared.data(from: faviconURL)
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200,
                      !data.isEmpty,
                      NSImage(data: data) != nil else { return }

                await MainActor.run {
                    self?.updateFavicon(data, for: entryId)
                }
            } catch {
                NSLog("[QuickLaunch] Failed to fetch favicon: %@", error.localizedDescription)
            }
        }
    }

    private func updateFavicon(_ data: Data, for entryId: UUID) {
        guard let index = customEntries.firstIndex(where: { $0.id == entryId }) else { return }
        customEntries[index].faviconData = data
        saveEntries()
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

        if case .url(let urlString) = action {
            fetchFavicon(for: entry.id, urlString: urlString)
        }
    }

    func updateEntry(_ entry: LaunchEntry) {
        if let index = customEntries.firstIndex(where: { $0.id == entry.id }) {
            customEntries[index] = entry
            saveEntries()

            if case .url(let urlString) = entry.action, entry.faviconData == nil {
                fetchFavicon(for: entry.id, urlString: urlString)
            }
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
            for entry in customEntries {
                if case .url(let urlString) = entry.action, entry.faviconData == nil {
                    fetchFavicon(for: entry.id, urlString: urlString)
                }
            }
        } catch {
            NSLog("[QuickLaunch] Failed to decode entries: %@", String(describing: error))
        }
    }

    // MARK: - Command Execution

    func runCommand(_ command: PaletteCommand) {
        recordRecent(command.id)

        switch command.group {
        case .screenTools:
            hidePanel()
            // Let the panel disappear before overlays / screenshots are created.
            DispatchQueue.main.async { command.run() }
        case .modes:
            let selectedID = flatItems.indices.contains(selectedIndex) ? flatItems[selectedIndex].id : nil
            command.run()
            buildSections()
            if let selectedID, let index = flatItems.firstIndex(where: { $0.id == selectedID }) {
                selectedIndex = index
            }
            objectWillChange.send()
        case .tools:
            openScreen(of: command)
        }
    }

    /// Switches the panel to the command's module screen (⌘↩ on any command).
    func openScreen(of command: PaletteCommand) {
        guard command.screen != nil else { return }
        activeScreen = command
    }

    func closeScreen() {
        activeScreen = nil
    }

    private func recordRecent(_ id: String) {
        recentCommandIDs.removeAll { $0 == id }
        recentCommandIDs.insert(id, at: 0)
        recentCommandIDs = Array(recentCommandIDs.prefix(Self.maxRecentCommands))
        UserDefaults.standard.set(recentCommandIDs, forKey: "quickLaunch.recentCommands")
        buildSections()
    }

    // MARK: - Keyboard Navigation

    func moveSelectionUp() {
        guard !flatItems.isEmpty else { return }
        selectedIndex = max(0, selectedIndex - 1)
    }

    func moveSelectionDown() {
        let count = flatItems.count
        guard count > 0 else { return }
        selectedIndex = min(count - 1, selectedIndex + 1)
    }

    func activate(_ item: PaletteItem) {
        switch item {
        case .command(let command, _): runCommand(command)
        case .entry(let entry): launchEntry(entry)
        }
    }

    func launchSelected() {
        let items = flatItems
        guard selectedIndex >= 0, selectedIndex < items.count else { return }
        activate(items[selectedIndex])
    }

    func openSelectedScreen() {
        let items = flatItems
        guard selectedIndex >= 0, selectedIndex < items.count,
              case .command(let command, _) = items[selectedIndex] else { return }
        openScreen(of: command)
    }
}
