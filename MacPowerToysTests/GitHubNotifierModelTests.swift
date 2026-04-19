import XCTest
@testable import MacPowerToys

@MainActor
final class GitHubNotifierModelTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        let defaults = UserDefaults.standard
        ["gitHubNotifier.isEnabled", "gitHubNotifier.pollingInterval",
         "gitHubNotifier.notificationSound", "gitHubNotifier.watchItems",
         "gitHubNotifier.events", "gitHubNotifier.enabledEventTypes"].forEach {
            defaults.removeObject(forKey: $0)
        }
    }

    // MARK: - hubStatusText

    func testHubStatusTextWhenDisabled() {
        let model = GitHubNotifierModel()
        // isEnabled loads as false (cleared in setUp)
        XCTAssertEqual(model.hubStatusText, "Disabled")
    }

    func testHubStatusTextWhenNoToken() {
        let model = GitHubNotifierModel()
        // deleteToken sets tokenStatus = .notSet and clears Keychain
        model.deleteToken()
        // Enable without a valid token; fetchEvents bails early (tokenStatus != .valid)
        model.isEnabled = true
        XCTAssertEqual(model.hubStatusText, "No token")
    }

    // NOTE: testHubStatusTextWhenEnabled is omitted.
    // tokenStatus is @Published private(set) and can only reach .valid through
    // KeychainHelper.save() + async validateToken() (network required).
    // This cannot be unit-tested reliably without mocking URLSession.

    // MARK: - Watch Items

    func testAddWatchItem() {
        let model = GitHubNotifierModel()
        model.addWatchItem(name: "owner/repo", type: .repo)
        XCTAssertEqual(model.watchItems.count, 1)
        XCTAssertEqual(model.watchItems.first?.name, "owner/repo")
    }

    func testAddWatchItemDuplicate() {
        let model = GitHubNotifierModel()
        model.addWatchItem(name: "owner/repo", type: .repo)
        model.addWatchItem(name: "owner/repo", type: .repo)
        XCTAssertEqual(model.watchItems.count, 1)
    }

    func testRemoveWatchItem() {
        let model = GitHubNotifierModel()
        model.addWatchItem(name: "owner/repo", type: .repo)
        let id = model.watchItems.first!.id
        model.removeWatchItem(id: id)
        XCTAssertTrue(model.watchItems.isEmpty)
    }

    func testToggleWatchItem() {
        let model = GitHubNotifierModel()
        model.addWatchItem(name: "owner/repo", type: .repo)
        // Items are created with isActive = true
        let id = model.watchItems.first!.id
        model.toggleWatchItem(id: id)
        XCTAssertEqual(model.watchItems.first?.isActive, false)
    }

    // MARK: - Codable Round-Trips

    func testGitHubEventItemCodable() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let original = GitHubEventItem(
            id: "event-abc-123",
            type: "PushEvent",
            repoName: "owner/repo",
            actorLogin: "testuser",
            summary: "Pushed 2 commits to main",
            htmlURL: "https://github.com/owner/repo/commit/abc123",
            createdAt: date
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GitHubEventItem.self, from: encoded)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.type, original.type)
        XCTAssertEqual(decoded.repoName, original.repoName)
        XCTAssertEqual(decoded.actorLogin, original.actorLogin)
        XCTAssertEqual(decoded.summary, original.summary)
        XCTAssertEqual(decoded.htmlURL, original.htmlURL)
        XCTAssertEqual(decoded.createdAt.timeIntervalSince1970,
                       original.createdAt.timeIntervalSince1970,
                       accuracy: 0.001)
    }

    func testGitHubWatchItemCodable() throws {
        let original = GitHubWatchItem(id: UUID(), name: "myorg/myrepo", type: .repo, isActive: true)

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GitHubWatchItem.self, from: encoded)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.type, original.type)
        XCTAssertEqual(decoded.isActive, original.isActive)
    }

    func testWatchItemTypeRoundTrip() throws {
        let repoEncoded = try JSONEncoder().encode(WatchItemType.repo)
        let repoDecoded = try JSONDecoder().decode(WatchItemType.self, from: repoEncoded)
        XCTAssertEqual(repoDecoded, .repo)

        let orgEncoded = try JSONEncoder().encode(WatchItemType.organization)
        let orgDecoded = try JSONDecoder().decode(WatchItemType.self, from: orgEncoded)
        XCTAssertEqual(orgDecoded, .organization)
    }

    // MARK: - GitHubEventType

    func testGitHubEventTypeDisplayName() {
        XCTAssertEqual(GitHubEventType.pushEvent.displayName, "Push")
        XCTAssertEqual(GitHubEventType.pullRequestEvent.displayName, "Pull Request")
        XCTAssertEqual(GitHubEventType.issuesEvent.displayName, "Issue")
    }

    func testGitHubEventTypeIcon() {
        GitHubEventType.allCases.forEach {
            XCTAssertFalse($0.icon.isEmpty, "\($0.rawValue) icon SF symbol name must not be empty")
        }
    }

    // MARK: - enabledEventTypes

    func testEnabledEventTypesDefaultAllOpen() {
        let model = GitHubNotifierModel()
        XCTAssertEqual(model.enabledEventTypes.count, GitHubEventType.allCases.count)
    }
}
