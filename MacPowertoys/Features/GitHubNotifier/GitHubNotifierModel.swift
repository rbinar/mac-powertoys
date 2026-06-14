import Foundation
import AppKit
import UserNotifications
import Security

// MARK: - Supporting Types

enum GitHubEventType: String, CaseIterable {
    case pushEvent = "PushEvent"
    case pullRequestEvent = "PullRequestEvent"
    case issuesEvent = "IssuesEvent"
    case issueCommentEvent = "IssueCommentEvent"
    case createEvent = "CreateEvent"
    case deleteEvent = "DeleteEvent"
    case releaseEvent = "ReleaseEvent"
    case watchEvent = "WatchEvent"
    case forkEvent = "ForkEvent"
    case pullRequestReviewEvent = "PullRequestReviewEvent"
    case pullRequestReviewCommentEvent = "PullRequestReviewCommentEvent"

    var displayName: String {
        switch self {
        case .pushEvent: return "Push"
        case .pullRequestEvent: return "Pull Request"
        case .issuesEvent: return "Issue"
        case .issueCommentEvent: return "Issue Comment"
        case .createEvent: return "Create"
        case .deleteEvent: return "Delete"
        case .releaseEvent: return "Release"
        case .watchEvent: return "Star"
        case .forkEvent: return "Fork"
        case .pullRequestReviewEvent: return "PR Review"
        case .pullRequestReviewCommentEvent: return "PR Review Comment"
        }
    }

    var icon: String {
        switch self {
        case .pushEvent: return "arrow.up.circle"
        case .pullRequestEvent: return "arrow.branch"
        case .issuesEvent: return "exclamationmark.circle"
        case .issueCommentEvent: return "bubble.left"
        case .createEvent: return "plus.circle"
        case .deleteEvent: return "minus.circle"
        case .releaseEvent: return "tag.circle"
        case .watchEvent: return "star"
        case .forkEvent: return "tuningfork"
        case .pullRequestReviewEvent: return "checkmark.circle"
        case .pullRequestReviewCommentEvent: return "bubble.left.and.bubble.right"
        }
    }
}

enum WatchItemType: String, Codable {
    case repo
    case organization
}

struct GitHubWatchItem: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    let type: WatchItemType
    var isActive: Bool
}

struct GitHubEventItem: Identifiable, Codable {
    let id: String
    let type: String
    let repoName: String
    let actorLogin: String
    var summary: String
    let htmlURL: String?
    let createdAt: Date
}

enum DeviceFlowStatus {
    case idle
    case requestingCode
    case awaitingVerification(userCode: String, expiresAt: Date)
    case expired
    case error(String)
}

enum TokenStatus {
    case notSet
    case validating
    case valid
    case expired
    case scopeInsufficient
    case invalid
}

// MARK: - GitHubNotifierModel

/// Coordinator/owner for the GitHub Notifier feature. The actual work is split across three
/// owned helpers — `GitHubAuthManager` (device-flow OAuth + Keychain + token validation),
/// `GitHubAPIClient` (URLSession calls, polling, rate-limit headers), and
/// `GitHubEventProcessor` (mapping/filtering/dedup/notifications). This model retains every
/// `@Published` property the View binds to and exposes the same public API as before.
@MainActor
final class GitHubNotifierModel: NSObject, ObservableObject, UNUserNotificationCenterDelegate {

    // MARK: - Settings

    @Published var isEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "gitHubNotifier.isEnabled")
            if isEnabled { startMonitoring() } else { stopMonitoring() }
        }
    }

    @Published var pollingInterval: Int = 60 {
        didSet {
            UserDefaults.standard.set(pollingInterval, forKey: "gitHubNotifier.pollingInterval")
            if isEnabled { rescheduleTimer() }
        }
    }

    @Published var notificationSound: Bool = true {
        didSet {
            UserDefaults.standard.set(notificationSound, forKey: "gitHubNotifier.notificationSound")
        }
    }

    @Published var enabledEventTypes: Set<String> = Set(GitHubEventType.allCases.map { $0.rawValue }) {
        didSet { saveEnabledEventTypes() }
    }

    // MARK: - Persisted State

    @Published var watchItems: [GitHubWatchItem] = [] {
        didSet { saveWatchItems() }
    }

    // MARK: - Runtime State

    @Published private(set) var tokenStatus: TokenStatus = .notSet
    @Published private(set) var githubUsername: String? = nil
    @Published private(set) var tokenScopes: Set<String> = []
    @Published private(set) var events: [GitHubEventItem] = []
    @Published private(set) var isPolling: Bool = false
    @Published private(set) var rateLimitRemaining: Int? = nil
    @Published private(set) var rateLimitReset: Date? = nil
    @Published private(set) var lastPollDate: Date? = nil
    @Published private(set) var availableRepos: [String] = []
    @Published private(set) var availableOrgs: [String] = []
    @Published private(set) var deviceFlowStatus: DeviceFlowStatus = .idle

    var hubStatusText: String {
        guard isEnabled else { return "Disabled" }
        switch tokenStatus {
        case .notSet:
            return "No token"
        case .validating:
            return "Validating…"
        case .expired:
            return "Token expired"
        case .scopeInsufficient:
            return "Insufficient scope"
        case .invalid:
            return "Invalid token"
        case .valid:
            if let remaining = rateLimitRemaining, remaining == 0 { return "Rate limited" }
            if isPolling { return "Polling…" }
            let activeCount = watchItems.filter { $0.isActive }.count
            let itemText = activeCount > 0 ? "\(activeCount) \(activeCount == 1 ? "item" : "items")" : "All events"
            guard let lastPoll = lastPollDate else { return itemText }
            let minutes = Int(Date().timeIntervalSince(lastPoll) / 60)
            if minutes < 1 { return "\(itemText) · just now" }
            return "\(itemText) · \(minutes)m ago"
        }
    }

    // MARK: - Helpers (owned/coordinated)

    private let auth = GitHubAuthManager()
    private let apiClient = GitHubAPIClient()
    private let processor = GitHubEventProcessor()

    // MARK: - Private

    private var pollTimer: Timer?
    private let eventsKey = "gitHubNotifier.events"
    private let watchItemsKey = "gitHubNotifier.watchItems"

    // MARK: - Init

    override init() {
        super.init()
        loadSettings()
        loadWatchItems()
        loadEvents()
        processor.seed(with: events)
        wireHelpers()
        if auth.hasStoredToken() {
            tokenStatus = .valid
        }
        if isEnabled { startMonitoring() }
    }

    /// Connects helper callbacks to this model's `@Published` state.
    ///
    /// The `scopes` argument is treated exactly as the original model did: `nil` means
    /// "leave existing scopes untouched" (e.g. `.validating`, no-token `.notSet`, catch-`.invalid`),
    /// any non-nil set overwrites them. `deleteToken()` sends the empty set, which is the only
    /// path that also clears the username via the `.notSet` branch below.
    private func wireHelpers() {
        auth.onTokenStatusChange = { [weak self] status, username, scopes in
            guard let self else { return }
            self.tokenStatus = status
            if let scopes { self.tokenScopes = scopes }
            switch status {
            case .valid:
                // Original set githubUsername only when a login was parsed (200).
                if let username { self.githubUsername = username }
            case .expired:
                self.githubUsername = nil
            case .notSet:
                // Validation's no-token path leaves username untouched (scopes == nil);
                // deleteToken clears it (scopes == []).
                if scopes != nil { self.githubUsername = nil }
            case .scopeInsufficient, .invalid, .validating:
                break
            }
        }
        auth.onDeviceFlowStatusChange = { [weak self] status in
            self?.deviceFlowStatus = status
        }
        auth.onTokenAuthorized = { [weak self] in
            guard let self, self.isEnabled else { return }
            self.startMonitoring()
        }
        auth.onRateLimitHeaders = { [weak self] response in
            self?.updateRateLimitHeaders(from: response)
        }
        apiClient.onRateLimitHeaders = { [weak self] response in
            self?.updateRateLimitHeaders(from: response)
        }
    }

    // MARK: - Monitoring

    func startMonitoring() {
        guard isEnabled else { return }
        requestNotificationPermission()
        NotificationCenter.default.removeObserver(self, name: NSWorkspace.willSleepNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleSleep), name: NSWorkspace.willSleepNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleWake), name: NSWorkspace.didWakeNotification, object: nil)
        scheduleTimer()
        Task { await fetchEvents() }
    }

    func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
        isPolling = false
        NotificationCenter.default.removeObserver(self, name: NSWorkspace.willSleepNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSWorkspace.didWakeNotification, object: nil)
    }

    @objc private func handleSleep() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    @objc private func handleWake() {
        guard isEnabled else { return }
        scheduleTimer()
        Task { await fetchEvents() }
    }

    private func scheduleTimer() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(pollingInterval), repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.fetchEvents()
            }
        }
    }

    private func rescheduleTimer() {
        guard isEnabled else { return }
        scheduleTimer()
    }

    // MARK: - Watch Items CRUD

    func addWatchItem(name: String, type: WatchItemType) {
        guard !watchItems.contains(where: { $0.name == name && $0.type == type }) else { return }
        watchItems.append(GitHubWatchItem(id: UUID(), name: name, type: type, isActive: true))
    }

    func removeWatchItem(id: UUID) {
        watchItems.removeAll { $0.id == id }
    }

    func toggleWatchItem(id: UUID) {
        guard let index = watchItems.firstIndex(where: { $0.id == id }) else { return }
        watchItems[index].isActive.toggle()
    }

    // MARK: - Token Management (delegated to GitHubAuthManager)

    func saveToken(_ token: String) {
        auth.saveToken(token)
    }

    func deleteToken() {
        auth.deleteToken()
        stopMonitoring()
    }

    func validateToken() async {
        await auth.validateToken()
    }

    // MARK: - Device Flow (delegated to GitHubAuthManager)

    func startDeviceFlow() {
        auth.startDeviceFlow()
    }

    func cancelDeviceFlow() {
        auth.cancelDeviceFlow()
    }

    // MARK: - GitHub API (delegated to GitHubAPIClient)

    func fetchUserRepos() async {
        guard let token = auth.loadToken(), !token.isEmpty else { return }
        let listing = await apiClient.fetchUserRepos(token: token)

        availableRepos = listing.repos
        // Merge orgs derived from repos into availableOrgs (keeps any already fetched)
        let merged = Set(availableOrgs).union(listing.orgs)
        if !listing.orgs.isEmpty {
            availableOrgs = merged.sorted()
        }
    }

    func fetchUserOrgs() async {
        guard let token = auth.loadToken(), !token.isEmpty else { return }
        guard let apiOrgs = await apiClient.fetchUserOrgs(token: token) else { return }
        let merged = Set(availableOrgs).union(apiOrgs)
        availableOrgs = merged.sorted()
    }

    func fetchEvents() async {
        guard isEnabled, !isPolling, tokenStatus == .valid || tokenStatus == .validating else { return }
        guard let token = auth.loadToken(), !token.isEmpty else { return }

        if let remaining = rateLimitRemaining, remaining < 10,
           let reset = rateLimitReset, Date() < reset {
            NSLog("[GitHubNotifier] Rate limit critically low (%d remaining), pausing polling until %@", remaining, reset.description)
            return
        }

        isPolling = true
        defer { isPolling = false }

        if let username = githubUsername {
            let result = await apiClient.fetchReceivedEvents(
                username: username,
                token: token,
                rateLimitRemaining: rateLimitRemaining
            )
            switch result {
            case .events(let json):
                ingest(json)
            case .notModified, .ignored:
                break
            case .unauthorized:
                tokenStatus = .expired
                stopMonitoring()
            case .forbidden(let rateLimited):
                if rateLimited {
                    NSLog("[GitHubNotifier] Rate limited until %@", rateLimitReset?.description ?? "unknown")
                } else {
                    tokenStatus = .scopeInsufficient
                }
            }
        }

        let orgItems = watchItems.filter { $0.isActive && $0.type == .organization }
        for item in orgItems {
            if let json = await apiClient.fetchOrgEvents(org: item.name, token: token) {
                ingest(json)
            }
        }

        let repoItems = watchItems.filter { $0.isActive && $0.type == .repo }
        for item in repoItems {
            if let json = await apiClient.fetchRepoEvents(repo: item.name, token: token) {
                ingest(json)
            }
        }

        lastPollDate = Date()
    }

    /// Runs a raw event payload through the processor and commits the resulting displayed list.
    private func ingest(_ jsonArray: [[String: Any]]) {
        guard let updated = processor.process(
            jsonArray,
            existingEvents: events,
            watchItems: watchItems,
            enabledEventTypes: enabledEventTypes,
            notificationSound: notificationSound
        ) else { return }
        events = updated
        saveEvents()
    }

    // MARK: - Notifications

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                NSLog("[GitHubNotifier] Notification permission error: %@", error.localizedDescription)
            }
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let urlString = userInfo["url"] as? String, let url = URL(string: urlString) {
            DispatchQueue.main.async {
                NSWorkspace.shared.open(url)
            }
        }
        completionHandler()
    }

    // MARK: - Rate Limit Helpers

    private func updateRateLimitHeaders(from response: HTTPURLResponse) {
        if let remainingStr = response.value(forHTTPHeaderField: "X-RateLimit-Remaining"),
           let remaining = Int(remainingStr) {
            rateLimitRemaining = remaining
            if remaining < 100 && pollingInterval < 300 {
                NSLog("[GitHubNotifier] Rate limit low (%d remaining), backing off", remaining)
            }
        }
        if let resetStr = response.value(forHTTPHeaderField: "X-RateLimit-Reset"),
           let resetTimestamp = TimeInterval(resetStr) {
            rateLimitReset = Date(timeIntervalSince1970: resetTimestamp)
        }
    }

    // MARK: - Persistence

    private func loadSettings() {
        let defaults = UserDefaults.standard
        // Assign via the backing store so didSet does NOT fire here; startMonitoring()
        // is called exactly once at the end of init(), after wireHelpers() and the
        // token check have both run.
        _isEnabled = Published(initialValue: defaults.bool(forKey: "gitHubNotifier.isEnabled"))
        if let stored = defaults.value(forKey: "gitHubNotifier.pollingInterval") as? Int {
            pollingInterval = stored
        }
        notificationSound = defaults.object(forKey: "gitHubNotifier.notificationSound") as? Bool ?? true
        loadEnabledEventTypes()
    }

    private func loadEnabledEventTypes() {
        guard let data = UserDefaults.standard.data(forKey: "gitHubNotifier.enabledEventTypes"),
              let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) else { return }
        enabledEventTypes = decoded
    }

    private func saveEnabledEventTypes() {
        if let data = try? JSONEncoder().encode(enabledEventTypes) {
            UserDefaults.standard.set(data, forKey: "gitHubNotifier.enabledEventTypes")
        }
    }

    private func saveWatchItems() {
        if let data = try? JSONEncoder().encode(watchItems) {
            UserDefaults.standard.set(data, forKey: watchItemsKey)
        }
    }

    private func loadWatchItems() {
        guard let data = UserDefaults.standard.data(forKey: watchItemsKey),
              let decoded = try? JSONDecoder().decode([GitHubWatchItem].self, from: data) else { return }
        watchItems = decoded
    }

    private func saveEvents() {
        if let data = try? JSONEncoder().encode(events) {
            UserDefaults.standard.set(data, forKey: eventsKey)
        }
    }

    private func loadEvents() {
        guard let data = UserDefaults.standard.data(forKey: eventsKey),
              let decoded = try? JSONDecoder().decode([GitHubEventItem].self, from: data) else { return }
        events = Array(decoded.prefix(25))
    }
}
