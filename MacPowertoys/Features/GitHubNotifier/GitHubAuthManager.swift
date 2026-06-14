import Foundation
import AppKit

// MARK: - KeychainHelper

/// Secure storage for the GitHub PAT/OAuth token. Secrets never go in UserDefaults or source.
struct KeychainHelper {
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

// MARK: - GitHubAuthManager

/// Owns device-flow OAuth, Keychain token storage, and token validation.
///
/// The manager performs the network/keychain work and reports results back to its owner
/// through closure callbacks; all `@Published` UI state continues to live on
/// `GitHubNotifierModel` so the View bindings are unaffected.
@MainActor
final class GitHubAuthManager {

    // MARK: - Callbacks

    /// Invoked whenever the token status changes.
    ///
    /// `username` is a value only when one was resolved (HTTP 200); otherwise `nil`.
    /// `scopes` is `nil` to mean "leave existing scopes untouched", a value to overwrite them,
    /// and the empty set to explicitly clear them (token deleted). This mirrors the original
    /// model exactly: validation set scopes only when the `X-OAuth-Scopes` header was present,
    /// `.validating` never touched scopes, and `deleteToken()` cleared them.
    var onTokenStatusChange: ((TokenStatus, _ username: String?, _ scopes: Set<String>?) -> Void)?
    /// Invoked whenever the device-flow status changes so the View can react.
    var onDeviceFlowStatusChange: ((DeviceFlowStatus) -> Void)?
    /// Invoked after a token is obtained/validated so the owner can (re)start monitoring.
    var onTokenAuthorized: (() -> Void)?
    /// Forwards rate-limit headers seen during auth/validation requests.
    var onRateLimitHeaders: ((HTTPURLResponse) -> Void)?

    // MARK: - State

    private(set) var deviceFlowStatus: DeviceFlowStatus = .idle {
        didSet { onDeviceFlowStatusChange?(deviceFlowStatus) }
    }

    // MARK: - Private

    private var deviceFlowPollingTask: Task<Void, Never>?
    private let gitHubOAuthClientIDInfoKey = "GitHubOAuthClientID"

    // MARK: - Token Storage

    func hasStoredToken() -> Bool {
        KeychainHelper.load() != nil
    }

    func loadToken() -> String? {
        KeychainHelper.load()
    }

    /// Stores a token, then validates it asynchronously. Reports `.validating`/`.invalid` immediately.
    func saveToken(_ token: String) {
        onTokenStatusChange?(.validating, nil, nil)
        if KeychainHelper.save(token) {
            Task { await validateToken() }
        } else {
            onTokenStatusChange?(.invalid, nil, nil)
        }
    }

    func deleteToken() {
        cancelDeviceFlow()
        _ = KeychainHelper.delete()
        onTokenStatusChange?(.notSet, nil, [])
    }

    // MARK: - Token Validation

    func validateToken() async {
        guard let token = KeychainHelper.load(), !token.isEmpty else {
            // Original: only tokenStatus = .notSet; scopes left untouched.
            onTokenStatusChange?(.notSet, nil, nil)
            return
        }

        guard let url = URL(string: "https://api.github.com/user") else { return }
        let request = GitHubAPIClient.buildRequest(url: url, token: token)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return }

            onRateLimitHeaders?(httpResponse)

            // Mirror original: scopes are overwritten only when the header is present.
            var scopes: Set<String>? = nil
            if let scopesHeader = httpResponse.value(forHTTPHeaderField: "X-OAuth-Scopes") {
                scopes = Set(scopesHeader.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
            }

            switch httpResponse.statusCode {
            case 200:
                var login: String? = nil
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let value = json["login"] as? String {
                    login = value
                }
                onTokenStatusChange?(.valid, login, scopes)
            case 401:
                onTokenStatusChange?(.expired, nil, scopes)
            case 403:
                // GitHub returns 403 for BOTH insufficient scope AND rate limiting.
                // Mirror GitHubAPIClient's disambiguation (forbidden(rateLimited:)):
                // a 403 with X-RateLimit-Remaining == "0" is a transient rate-limit, not a
                // scope problem — the token is still valid, so don't flag it (which would
                // wrongly prompt the user to delete a good token). Only treat 403 as a
                // scope problem when there's remaining quota (remaining > 0).
                if httpResponse.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0" {
                    NSLog("[GitHubNotifier] Token validation rate limited (HTTP 403, X-RateLimit-Remaining == 0); leaving token status valid")
                    onTokenStatusChange?(.valid, nil, scopes)
                } else {
                    onTokenStatusChange?(.scopeInsufficient, nil, scopes)
                }
            default:
                onTokenStatusChange?(.invalid, nil, scopes)
            }
        } catch {
            NSLog("[GitHubNotifier] Token validation failed: %@", error.localizedDescription)
            // Original catch: tokenStatus = .invalid; scopes left untouched.
            onTokenStatusChange?(.invalid, nil, nil)
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
                  let expiresIn = json["expires_in"] as? Int else {
                deviceFlowStatus = .error("Failed to get authorization code from GitHub")
                return
            }
            let pollInterval = json["interval"] as? Int ?? 5

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
                // An in-flight request can complete between cancellation and the next loop
                // check; bail before acting on it so a cancelled poll can't save a token /
                // set .idle after the flow was torn down.
                guard !Task.isCancelled else { return }
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

                if let accessToken = json["access_token"] as? String, !accessToken.isEmpty {
                    if KeychainHelper.save(accessToken) {
                        deviceFlowStatus = .idle
                        await validateToken()
                        onTokenAuthorized?()
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
}
