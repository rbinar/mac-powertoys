import Foundation

// MARK: - GitHubAPIClient

/// Owns all GitHub REST calls: repo/org listing and event polling, including ETag caching
/// and rate-limit header surfacing. Networking only — the client never mutates UI state;
/// it returns decoded JSON to the caller and forwards rate-limit headers via a callback.
@MainActor
final class GitHubAPIClient {

    // MARK: - Callbacks

    /// Forwards every `HTTPURLResponse` so the owner can update rate-limit state.
    var onRateLimitHeaders: ((HTTPURLResponse) -> Void)?

    // MARK: - Private

    private var eTagCache: [String: String] = [:]

    // MARK: - Request Building

    static func buildRequest(url: URL, token: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("MacPowerToys/1.0", forHTTPHeaderField: "User-Agent")
        return request
    }

    // MARK: - Repos & Orgs

    /// Result of a repo listing: the full sorted repo names plus any org logins derived from them.
    struct RepoListing {
        var repos: [String]
        var orgs: Set<String>
    }

    func fetchUserRepos(token: String) async -> RepoListing {
        var page = 1
        var allRepos: [String] = []
        var orgSet: Set<String> = []

        while true {
            let urlString = "https://api.github.com/user/repos?per_page=100&sort=updated&affiliation=owner,collaborator,organization_member&page=\(page)"
            guard let url = URL(string: urlString) else { break }
            let request = GitHubAPIClient.buildRequest(url: url, token: token)

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { break }
                onRateLimitHeaders?(httpResponse)

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

        return RepoListing(repos: allRepos.sorted(), orgs: orgSet)
    }

    /// Returns org logins from /user/orgs, or `nil` if the call failed (caller keeps repo-derived orgs).
    func fetchUserOrgs(token: String) async -> [String]? {
        guard let url = URL(string: "https://api.github.com/user/orgs?per_page=100") else { return nil }

        let request = GitHubAPIClient.buildRequest(url: url, token: token)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                // Fallback: derive orgs from already-fetched repos
                NSLog("[GitHubNotifier] /user/orgs failed, falling back to repo-derived org list")
                return nil
            }
            onRateLimitHeaders?(httpResponse)

            if let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                return json.compactMap { $0["login"] as? String }
            }
            return nil
        } catch {
            NSLog("[GitHubNotifier] Failed to fetch orgs: %@", error.localizedDescription)
            return nil
        }
    }

    // MARK: - Events

    /// Outcome of an event fetch, mapped to the caller's behavioral cases.
    enum EventFetchResult {
        /// New JSON payload to process (HTTP 200).
        case events([[String: Any]])
        /// Not modified (HTTP 304) or no parseable payload — nothing to do.
        case notModified
        /// Token rejected (HTTP 401) — caller should mark expired and stop monitoring.
        case unauthorized
        /// Forbidden (HTTP 403). `rateLimited` is true when remaining == 0, else scope issue.
        case forbidden(rateLimited: Bool)
        /// Any other / unhandled outcome (logged, no state change).
        case ignored
    }

    private func fetchEventsResponse(endpoint: String, token: String) async throws -> (statusCode: Int, data: Data)? {
        guard let url = URL(string: endpoint) else { return nil }

        var request = GitHubAPIClient.buildRequest(url: url, token: token)
        if let etag = eTagCache[endpoint] {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { return nil }

        onRateLimitHeaders?(httpResponse)

        if let newEtag = httpResponse.value(forHTTPHeaderField: "ETag") {
            eTagCache[endpoint] = newEtag
        }

        return (statusCode: httpResponse.statusCode, data: data)
    }

    /// Fetches the authenticated user's received events. Returns a behavioral result.
    /// `rateLimitRemaining` is only consulted to disambiguate the 403 case.
    func fetchReceivedEvents(username: String, token: String, rateLimitRemaining: Int?) async -> EventFetchResult {
        let endpoint = "https://api.github.com/users/\(username)/received_events?per_page=50"

        do {
            guard let result = try await fetchEventsResponse(endpoint: endpoint, token: token) else { return .ignored }

            switch result.statusCode {
            case 200:
                if let json = try? JSONSerialization.jsonObject(with: result.data) as? [[String: Any]] {
                    return .events(json)
                }
                return .notModified
            case 304:
                return .notModified
            case 401:
                return .unauthorized
            case 403:
                return .forbidden(rateLimited: rateLimitRemaining == 0)
            default:
                NSLog("[GitHubNotifier] Unexpected status %d for received_events", result.statusCode)
                return .ignored
            }
        } catch {
            let nsError = error as NSError
            if nsError.code != NSURLErrorCancelled {
                NSLog("[GitHubNotifier] fetchReceivedEvents error: %@", error.localizedDescription)
            }
            return .ignored
        }
    }

    /// Fetches events for a single repo. Returns the JSON payload on HTTP 200, else nil.
    func fetchRepoEvents(repo: String, token: String) async -> [[String: Any]]? {
        let encoded = repo.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? repo
        let endpoint = "https://api.github.com/repos/\(encoded)/events?per_page=30"

        do {
            guard let result = try await fetchEventsResponse(endpoint: endpoint, token: token) else { return nil }

            if result.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: result.data) as? [[String: Any]] {
                return json
            }
            return nil
        } catch {
            NSLog("[GitHubNotifier] fetchRepoEvents error for %@: %@", repo, error.localizedDescription)
            return nil
        }
    }

    /// Fetches events for a single org. Returns the JSON payload on HTTP 200, else nil.
    func fetchOrgEvents(org: String, token: String) async -> [[String: Any]]? {
        let endpoint = "https://api.github.com/orgs/\(org)/events?per_page=30"

        do {
            guard let result = try await fetchEventsResponse(endpoint: endpoint, token: token) else { return nil }

            if result.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: result.data) as? [[String: Any]] {
                return json
            }
            return nil
        } catch {
            NSLog("[GitHubNotifier] fetchOrgEvents error for %@: %@", org, error.localizedDescription)
            return nil
        }
    }
}
