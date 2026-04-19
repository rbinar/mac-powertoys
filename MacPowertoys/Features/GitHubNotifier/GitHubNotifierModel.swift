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

// MARK: - KeychainHelper

private struct KeychainHelper {
    private static let service = "com.rbinar.MacPowerToys.GitHubNotifier"
    private static let account = "github-pat"

    static func save(_ token: String) -> Bool {
        guard let data = token.data(using: .utf8) else { return false }

        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess {
            NSLog("[GitHubNotifier] Failed to save token to Keychain: %d", status)
            return false
        }
        return true
    }

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            NSLog("[GitHubNotifier] Failed to delete token from Keychain: %d", status)
            return false
        }
        return true
    }
}

// MARK: - GitHubNotifierModel

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

    // MARK: - Private

    private var pollTimer: Timer?
    private var seenEventIDs: Set<String> = []
    private var eTagCache: [String: String] = [:]
    private var deviceFlowPollingTask: Task<Void, Never>?
    private let eventsKey = "gitHubNotifier.events"
    private let watchItemsKey = "gitHubNotifier.watchItems"
    private let gitHubOAuthClientIDInfoKey = "GitHubOAuthClientID"
    private static let iso8601Formatter = ISO8601DateFormatter()

    // MARK: - Init

    override init() {
        super.init()
        loadSettings()
        loadWatchItems()
        loadEvents()
        seenEventIDs = Set(events.map { $0.id })
        if KeychainHelper.load() != nil {
            tokenStatus = .valid
        }
        if isEnabled { startMonitoring() }
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

    // MARK: - Token Management

    func saveToken(_ token: String) {
        tokenStatus = .validating
        if KeychainHelper.save(token) {
            Task { await validateToken() }
        } else {
            tokenStatus = .invalid
        }
    }

    func deleteToken() {
        cancelDeviceFlow()
        _ = KeychainHelper.delete()
        tokenStatus = .notSet
        githubUsername = nil
        tokenScopes = []
        stopMonitoring()
    }

    func validateToken() async {
        guard let token = KeychainHelper.load(), !token.isEmpty else {
            tokenStatus = .notSet
            return
        }

        guard let url = URL(string: "https://api.github.com/user") else { return }
        let request = buildRequest(url: url, token: token)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return }

            updateRateLimitHeaders(from: httpResponse)

            if let scopesHeader = httpResponse.value(forHTTPHeaderField: "X-OAuth-Scopes") {
                tokenScopes = Set(scopesHeader.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
            }

            switch httpResponse.statusCode {
            case 200:
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let login = json["login"] as? String {
                    githubUsername = login
                }
                tokenStatus = .valid
            case 401:
                tokenStatus = .expired
                githubUsername = nil
            case 403:
                tokenStatus = .scopeInsufficient
            default:
                tokenStatus = .invalid
            }
        } catch {
            NSLog("[GitHubNotifier] Token validation failed: %@", error.localizedDescription)
            tokenStatus = .invalid
        }
    }

    // MARK: - Device Flow

    func startDeviceFlow() {
        cancelDeviceFlow()
        deviceFlowStatus = .requestingCode
        deviceFlowPollingTask = Task { await runDeviceFlow() }
    }

    func cancelDeviceFlow() {
        deviceFlowPollingTask?.cancel()
        deviceFlowPollingTask = nil
        if case .awaitingVerification = deviceFlowStatus { deviceFlowStatus = .idle }
        if case .requestingCode = deviceFlowStatus { deviceFlowStatus = .idle }
    }

    private func runDeviceFlow() async {
        guard let clientID = configuredGitHubOAuthClientID() else { return }
        guard let url = URL(string: "https://github.com/login/device/code") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "client_id": clientID,
            "scope": "repo read:org"
        ])

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let deviceCode = json["device_code"] as? String,
                  let userCode = json["user_code"] as? String,
                  let verificationURI = json["verification_uri"] as? String,
                  let expiresIn = json["expires_in"] as? Int,
                  let pollInterval = json["interval"] as? Int else {
                deviceFlowStatus = .error("Failed to get authorization code from GitHub")
                return
            }

            let expiresAt = Date().addingTimeInterval(TimeInterval(expiresIn))
            deviceFlowStatus = .awaitingVerification(userCode: userCode, expiresAt: expiresAt)
            if let vUri = URL(string: verificationURI) {
                NSWorkspace.shared.open(vUri)
            }
            await pollForDeviceToken(deviceCode: deviceCode, clientID: clientID, interval: pollInterval, expiresAt: expiresAt)
        } catch {
            if (error as NSError).code != NSURLErrorCancelled {
                deviceFlowStatus = .error("Network error: \(error.localizedDescription)")
            }
        }
    }

    private func pollForDeviceToken(deviceCode: String, clientID: String, interval: Int, expiresAt: Date) async {
        guard let url = URL(string: "https://github.com/login/oauth/access_token") else { return }
        var currentInterval = interval

        while Date() < expiresAt {
            guard !Task.isCancelled else { return }
            try? await Task.sleep(nanoseconds: UInt64(currentInterval) * 1_000_000_000)
            guard !Task.isCancelled else { return }

            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.httpBody = try? JSONSerialization.data(withJSONObject: [
                "client_id": clientID,
                "device_code": deviceCode,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code"
            ])

            do {
                let (data, _) = try await URLSession.shared.data(for: req)
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

                if let accessToken = json["access_token"] as? String, !accessToken.isEmpty {
                    if KeychainHelper.save(accessToken) {
                        deviceFlowStatus = .idle
                        await validateToken()
                        if isEnabled { startMonitoring() }
                    } else {
                        deviceFlowStatus = .error("Failed to save token securely")
                    }
                    return
                }

                if let errorCode = json["error"] as? String {
                    switch errorCode {
                    case "authorization_pending": continue
                    case "slow_down":
                        currentInterval += 5
                        continue
                    case "expired_token":
                        deviceFlowStatus = .expired
                        return
                    case "access_denied":
                        deviceFlowStatus = .error("Access denied by user")
                        return
                    default:
                        deviceFlowStatus = .error(errorCode)
                        return
                    }
                }
            } catch {
                if (error as NSError).code == NSURLErrorCancelled { return }
            }
        }

        deviceFlowStatus = .expired
    }

    // MARK: - GitHub API

    func fetchUserRepos() async {
        guard let token = KeychainHelper.load(), !token.isEmpty else { return }
        var page = 1
        var allRepos: [String] = []
        var orgSet: Set<String> = []

        while true {
            let urlString = "https://api.github.com/user/repos?per_page=100&sort=updated&affiliation=owner,collaborator,organization_member&page=\(page)"
            guard let url = URL(string: urlString) else { break }
            let request = buildRequest(url: url, token: token)

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { break }
                updateRateLimitHeaders(from: httpResponse)

                guard let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]], !json.isEmpty else { break }
                for repo in json {
                    if let fullName = repo["full_name"] as? String {
                        allRepos.append(fullName)
                    }
                    if let owner = repo["owner"] as? [String: Any],
                       let ownerLogin = owner["login"] as? String,
                       let ownerType = owner["type"] as? String,
                       ownerType == "Organization" {
                        orgSet.insert(ownerLogin)
                    }
                }
                if json.count < 100 { break }
                page += 1
            } catch {
                NSLog("[GitHubNotifier] Failed to fetch repos page %d: %@", page, error.localizedDescription)
                break
            }
        }

        availableRepos = allRepos.sorted()
        // Merge orgs derived from repos into availableOrgs (keeps any already fetched)
        let merged = Set(availableOrgs).union(orgSet)
        if !orgSet.isEmpty {
            availableOrgs = merged.sorted()
        }
    }

    func fetchUserOrgs() async {
        guard let token = KeychainHelper.load(), !token.isEmpty else { return }
        guard let url = URL(string: "https://api.github.com/user/orgs?per_page=100") else { return }

        let request = buildRequest(url: url, token: token)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                // Fallback: derive orgs from already-fetched repos
                NSLog("[GitHubNotifier] /user/orgs failed, falling back to repo-derived org list")
                return
            }
            updateRateLimitHeaders(from: httpResponse)

            if let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                let apiOrgs = json.compactMap { $0["login"] as? String }
                let merged = Set(availableOrgs).union(apiOrgs)
                availableOrgs = merged.sorted()
            }
        } catch {
            NSLog("[GitHubNotifier] Failed to fetch orgs: %@", error.localizedDescription)
        }
    }

    func fetchEvents() async {
        guard isEnabled, tokenStatus == .valid || tokenStatus == .validating else { return }
        guard let token = KeychainHelper.load(), !token.isEmpty else { return }

        if let remaining = rateLimitRemaining, remaining < 10 {
            NSLog("[GitHubNotifier] Rate limit critically low (%d remaining), pausing polling", remaining)
            return
        }

        isPolling = true
        defer { isPolling = false }

        if let username = githubUsername {
            await fetchReceivedEvents(username: username, token: token)
        }

        let orgItems = watchItems.filter { $0.isActive && $0.type == .organization }
        for item in orgItems {
            await fetchOrgEvents(org: item.name, token: token)
        }

        let repoItems = watchItems.filter { $0.isActive && $0.type == .repo }
        for item in repoItems {
            await fetchRepoEvents(repo: item.name, token: token)
        }

        lastPollDate = Date()
    }

    private func fetchEventsResponse(endpoint: String, token: String) async throws -> (statusCode: Int, data: Data)? {
        guard let url = URL(string: endpoint) else { return nil }

        var request = buildRequest(url: url, token: token)
        if let etag = eTagCache[endpoint] {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { return nil }

        updateRateLimitHeaders(from: httpResponse)

        if let newEtag = httpResponse.value(forHTTPHeaderField: "ETag") {
            eTagCache[endpoint] = newEtag
        }

        return (statusCode: httpResponse.statusCode, data: data)
    }

    private func fetchReceivedEvents(username: String, token: String) async {
        let endpoint = "https://api.github.com/users/\(username)/received_events?per_page=50"

        do {
            guard let result = try await fetchEventsResponse(endpoint: endpoint, token: token) else { return }

            switch result.statusCode {
            case 200:
                if let json = try? JSONSerialization.jsonObject(with: result.data) as? [[String: Any]] {
                    processEvents(json)
                }
            case 304:
                break
            case 401:
                tokenStatus = .expired
                stopMonitoring()
            case 403:
                if let remaining = rateLimitRemaining, remaining == 0 {
                    NSLog("[GitHubNotifier] Rate limited until %@", rateLimitReset?.description ?? "unknown")
                } else {
                    tokenStatus = .scopeInsufficient
                }
            default:
                NSLog("[GitHubNotifier] Unexpected status %d for received_events", result.statusCode)
            }
        } catch {
            let nsError = error as NSError
            if nsError.code != NSURLErrorCancelled {
                NSLog("[GitHubNotifier] fetchReceivedEvents error: %@", error.localizedDescription)
            }
        }
    }

    private func fetchRepoEvents(repo: String, token: String) async {
        let encoded = repo.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? repo
        let endpoint = "https://api.github.com/repos/\(encoded)/events?per_page=30"

        do {
            guard let result = try await fetchEventsResponse(endpoint: endpoint, token: token) else { return }

            if result.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: result.data) as? [[String: Any]] {
                processEvents(json)
            }
        } catch {
            NSLog("[GitHubNotifier] fetchRepoEvents error for %@: %@", repo, error.localizedDescription)
        }
    }

    private func fetchOrgEvents(org: String, token: String) async {
        let endpoint = "https://api.github.com/orgs/\(org)/events?per_page=30"

        do {
            guard let result = try await fetchEventsResponse(endpoint: endpoint, token: token) else { return }

            if result.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: result.data) as? [[String: Any]] {
                processEvents(json)
            }
        } catch {
            NSLog("[GitHubNotifier] fetchOrgEvents error for %@: %@", org, error.localizedDescription)
        }
    }

    private func processEvents(_ jsonArray: [[String: Any]]) {
        var newEvents: [GitHubEventItem] = []

        for json in jsonArray {
            guard let eventID = json["id"] as? String,
                  let eventType = json["type"] as? String,
                  !seenEventIDs.contains(eventID) else { continue }

            let repoName = (json["repo"] as? [String: Any])?["name"] as? String ?? "unknown/repo"

            if !watchItems.isEmpty {
                let isWatched = watchItems.contains { item in
                    item.isActive && (
                        (item.type == .repo && repoName == item.name) ||
                        (item.type == .organization && repoName.hasPrefix(item.name + "/"))
                    )
                }
                if !isWatched { continue }
            }

            guard enabledEventTypes.contains(eventType) else { continue }

            let actorLogin = (json["actor"] as? [String: Any])?["login"] as? String ?? "unknown"
            let payload = json["payload"] as? [String: Any] ?? [:]
            let summary = buildSummary(eventType: eventType, repoName: repoName, actor: actorLogin, payload: payload)
            let htmlURL = extractHTMLURL(eventType: eventType, repoName: repoName, payload: payload)

            var createdAt = Date()
            if let createdStr = json["created_at"] as? String {
                createdAt = GitHubNotifierModel.iso8601Formatter.date(from: createdStr) ?? Date()
            }

            newEvents.append(GitHubEventItem(
                id: eventID,
                type: eventType,
                repoName: repoName,
                actorLogin: actorLogin,
                summary: summary,
                htmlURL: htmlURL,
                createdAt: createdAt
            ))
        }

        guard !newEvents.isEmpty else { return }

        newEvents.sort { $0.createdAt > $1.createdAt }

        for item in newEvents {
            sendNotification(for: item)
            seenEventIDs.insert(item.id)
        }

        // Aynı URL'ye sahip (aynı issue/PR) olayları grupla ve sadece en güncel olanı tut
        let combined = newEvents + events
        var uniqueURLSet = Set<String>()
        var deduped: [GitHubEventItem] = []
        
        for event in combined {
            if let url = event.htmlURL, !url.isEmpty {
                if !uniqueURLSet.contains(url) {
                    uniqueURLSet.insert(url)
                    deduped.append(event)
                }
            } else {
                deduped.append(event)
            }
        }

        events = Array(deduped.prefix(25))
        saveEvents()
    }

    private func buildSummary(eventType: String, repoName: String, actor: String, payload: [String: Any]) -> String {
        switch eventType {
        case "PushEvent":
            let commits = (payload["commits"] as? [[String: Any]])?.count ?? 0
            let branch = (payload["ref"] as? String)?.replacingOccurrences(of: "refs/heads/", with: "") ?? "main"
            return "\(actor) pushed \(commits) commit\(commits == 1 ? "" : "s") to \(branch)"
        case "PullRequestEvent":
            let action = payload["action"] as? String ?? "updated"
            let prTitle = (payload["pull_request"] as? [String: Any])?["title"] as? String ?? "a pull request"
            return "\(actor) \(action) PR: \(prTitle)"
        case "IssuesEvent":
            let action = payload["action"] as? String ?? "updated"
            let issueTitle = (payload["issue"] as? [String: Any])?["title"] as? String ?? "an issue"
            return "\(actor) \(action) issue: \(issueTitle)"
        case "IssueCommentEvent":
            let issueTitle = (payload["issue"] as? [String: Any])?["title"] as? String ?? "an issue"
            return "\(actor) commented on: \(issueTitle)"
        case "CreateEvent":
            let refType = payload["ref_type"] as? String ?? "branch"
            let ref = payload["ref"] as? String ?? ""
            return "\(actor) created \(refType)\(ref.isEmpty ? "" : ": \(ref)")"
        case "DeleteEvent":
            let refType = payload["ref_type"] as? String ?? "branch"
            let ref = payload["ref"] as? String ?? ""
            return "\(actor) deleted \(refType)\(ref.isEmpty ? "" : ": \(ref)")"
        case "ReleaseEvent":
            let tag = (payload["release"] as? [String: Any])?["tag_name"] as? String ?? ""
            return "\(actor) released \(tag.isEmpty ? "a new version" : tag)"
        case "WatchEvent":
            return "\(actor) starred \(repoName)"
        case "ForkEvent":
            return "\(actor) forked \(repoName)"
        case "PullRequestReviewEvent":
            let prTitle = (payload["pull_request"] as? [String: Any])?["title"] as? String ?? "a pull request"
            let state = (payload["review"] as? [String: Any])?["state"] as? String ?? "reviewed"
            return "\(actor) \(state) PR: \(prTitle)"
        case "PullRequestReviewCommentEvent":
            let prTitle = (payload["pull_request"] as? [String: Any])?["title"] as? String ?? "a pull request"
            return "\(actor) commented on PR: \(prTitle)"
        default:
            return "\(actor) triggered \(eventType)"
        }
    }

    private func extractHTMLURL(eventType: String, repoName: String, payload: [String: Any]) -> String? {
        switch eventType {
        case "PushEvent":
            return "https://github.com/\(repoName)/commits"
        case "PullRequestEvent":
            return (payload["pull_request"] as? [String: Any])?["html_url"] as? String
        case "IssuesEvent":
            return (payload["issue"] as? [String: Any])?["html_url"] as? String
        case "IssueCommentEvent":
            return (payload["comment"] as? [String: Any])?["html_url"] as? String
        case "ReleaseEvent":
            return (payload["release"] as? [String: Any])?["html_url"] as? String
        case "ForkEvent":
            return (payload["forkee"] as? [String: Any])?["html_url"] as? String
        case "PullRequestReviewEvent", "PullRequestReviewCommentEvent":
            return (payload["pull_request"] as? [String: Any])?["html_url"] as? String
        default:
            return "https://github.com/\(repoName)"
        }
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

    private func sendNotification(for event: GitHubEventItem) {
        let content = UNMutableNotificationContent()
        content.title = event.repoName
        content.body = event.summary
        content.threadIdentifier = event.repoName

        if notificationSound {
            content.sound = .default
        }

        if let urlString = event.htmlURL {
            content.userInfo = ["url": urlString]
        }

        let request = UNNotificationRequest(identifier: "github-\(event.id)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                NSLog("[GitHubNotifier] Failed to schedule notification: %@", error.localizedDescription)
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

    private func configuredGitHubOAuthClientID() -> String? {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: gitHubOAuthClientIDInfoKey) as? String else {
            NSLog("[GitHubNotifier] Missing %@ in Info.plist", gitHubOAuthClientIDInfoKey)
            deviceFlowStatus = .error("GitHub OAuth is not configured (missing GitHubOAuthClientID).")
            return nil
        }

        let clientID = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientID.isEmpty else {
            NSLog("[GitHubNotifier] Empty %@ in Info.plist", gitHubOAuthClientIDInfoKey)
            deviceFlowStatus = .error("GitHub OAuth is not configured (empty GitHubOAuthClientID).")
            return nil
        }

        return clientID
    }

    private func buildRequest(url: URL, token: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("MacPowerToys/1.0", forHTTPHeaderField: "User-Agent")
        return request
    }

    // MARK: - Persistence

    private func loadSettings() {
        let defaults = UserDefaults.standard
        isEnabled = defaults.bool(forKey: "gitHubNotifier.isEnabled")
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
