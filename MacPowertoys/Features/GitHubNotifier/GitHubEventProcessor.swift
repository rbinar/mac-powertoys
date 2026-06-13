import Foundation
import UserNotifications

// MARK: - GitHubEventProcessor

/// Owns event mapping, watch/type filtering, de-duplication, the bounded `seenEventIDs` set,
/// and local-notification delivery. It is purely model-side logic (no networking, no UI state):
/// the owner feeds it raw JSON plus the current filter context, and it returns the new displayed
/// `events` list while emitting one notification per newly seen event.
@MainActor
final class GitHubEventProcessor {

    // MARK: - Tuning

    /// Hard ceiling on remembered event IDs so the set cannot grow without limit over long sessions.
    private static let seenCap = 1000
    /// Maximum number of events kept in the displayed/persisted list.
    static let maxDisplayedEvents = 25

    // MARK: - Dedup State

    private var seenEventIDs: Set<String> = []

    private static let iso8601Formatter = ISO8601DateFormatter()

    // MARK: - Seeding

    /// Re-seed the seen set from already-persisted events on launch so visible events are never re-notified.
    func seed(with events: [GitHubEventItem]) {
        seenEventIDs = Set(events.map { $0.id })
    }

    // MARK: - Processing

    /// Filters/maps a raw JSON event array, sends notifications for newly seen events, and returns
    /// the updated displayed list (capped, URL-deduped). Returns `nil` when there is nothing new,
    /// so the owner can skip persisting unchanged state.
    ///
    /// - Parameters:
    ///   - jsonArray: raw GitHub event JSON objects.
    ///   - existingEvents: the currently displayed events to merge into.
    ///   - watchItems: active watch filters; when non-empty, only matching events pass.
    ///   - enabledEventTypes: raw event-type strings the user has enabled.
    ///   - notificationSound: whether delivered notifications should play a sound.
    func process(
        _ jsonArray: [[String: Any]],
        existingEvents: [GitHubEventItem],
        watchItems: [GitHubWatchItem],
        enabledEventTypes: Set<String>,
        notificationSound: Bool
    ) -> [GitHubEventItem]? {
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
                createdAt = GitHubEventProcessor.iso8601Formatter.date(from: createdStr) ?? Date()
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

        guard !newEvents.isEmpty else { return nil }

        newEvents.sort { $0.createdAt > $1.createdAt }

        for item in newEvents {
            sendNotification(for: item, notificationSound: notificationSound)
            seenEventIDs.insert(item.id)
        }

        // Aynı URL'ye sahip (aynı issue/PR) olayları grupla ve sadece en güncel olanı tut
        let combined = newEvents + existingEvents
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

        let result = Array(deduped.prefix(GitHubEventProcessor.maxDisplayedEvents))

        // Bound seenEventIDs so it cannot grow without limit over long-running sessions.
        // Trade-off: IDs older than the cap window may eventually be evicted and could
        // produce a duplicate notification if the GitHub API resurfaces them — acceptable
        // given the 1000-ID ceiling far exceeds practical polling rates.
        // We always retain IDs for the events currently displayed (at most 25) so that
        // visible events are never re-notified.
        if seenEventIDs.count > GitHubEventProcessor.seenCap {
            let pinnedIDs = Set(result.map { $0.id })
            let overflow = seenEventIDs.subtracting(pinnedIDs)
            seenEventIDs = pinnedIDs.union(overflow.prefix(GitHubEventProcessor.seenCap - pinnedIDs.count))
        }

        return result
    }

    // MARK: - Summaries

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

    private func sendNotification(for event: GitHubEventItem, notificationSound: Bool) {
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
}
