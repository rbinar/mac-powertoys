import SwiftUI

struct GitHubNotifierView: View {
    let onBack: () -> Void
    @EnvironmentObject var model: GitHubNotifierModel

    @State private var tokenInput = ""
    @State private var repoSearchText = ""
    @State private var isFetchingRepos = false
    @State private var showPATInput = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button { onBack() } label: {
                    Label("Back", systemImage: "chevron.left")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
                Text("GitHub Notifier")
                    .font(.system(.headline, design: .rounded))
                Spacer()
                Toggle("", isOn: $model.isEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.mini)
            }
            Divider()

            if !model.isEnabled {
                Text("Enable to start monitoring GitHub events.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        tokenSection
                        if model.tokenStatus == .valid {
                            watchItemsSection
                        }
                        eventFiltersSection
                        settingsSection
                        if !model.events.isEmpty {
                            recentEventsSection
                        }
                    }
                }
            }
        }
        .padding(16)
    }

    // MARK: - Token Section

    @ViewBuilder
    private var tokenSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Authentication")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)

            switch model.tokenStatus {
            case .notSet:
                tokenNotSetView
            case .validating:
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Validating token...")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            case .valid:
                tokenValidView
            case .expired:
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text("Token expired or revoked.")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.yellow)
                    }
                    tokenNotSetView
                }
            case .scopeInsufficient:
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text("Token missing required scopes. Needs 'repo' and 'read:org'.")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.yellow)
                    }
                    HStack(spacing: 12) {
                        Button("Remove Token") {
                            model.deleteToken()
                        }
                        .buttonStyle(.plain)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.red)
                        Button("Re-authenticate") {
                            model.deleteToken()
                            model.startDeviceFlow()
                        }
                        .buttonStyle(.plain)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.blue)
                    }
                }
            case .invalid:
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                        Text("Invalid token or network error.")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.red)
                    }
                    tokenNotSetView
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.14)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.18), lineWidth: 1))
    }

    @ViewBuilder
    private var tokenNotSetView: some View {
        VStack(alignment: .leading, spacing: 8) {
            deviceFlowSection
            if showPATInput {
                tokenInputView
                Button("Hide") { showPATInput = false }
                    .buttonStyle(.plain)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.tertiary)
            } else {
                Button("Use a personal access token instead") { showPATInput = true }
                    .buttonStyle(.plain)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private var deviceFlowSection: some View {
        if case .requestingCode = model.deviceFlowStatus {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Requesting code from GitHub\u{2026}")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        } else if case .awaitingVerification(let userCode, _) = model.deviceFlowStatus {
            deviceFlowAwaitingView(userCode: userCode)
        } else if case .expired = model.deviceFlowStatus {
            VStack(alignment: .leading, spacing: 6) {
                Label("Authorization code expired. Please try again.", systemImage: "clock.badge.xmark")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.yellow)
                loginWithGitHubButton
            }
        } else if case .error(let msg) = model.deviceFlowStatus {
            VStack(alignment: .leading, spacing: 6) {
                Label(msg, systemImage: "xmark.circle")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.red)
                loginWithGitHubButton
            }
        } else {
            loginWithGitHubButton
        }
    }

    @ViewBuilder
    private var loginWithGitHubButton: some View {
        Button {
            model.startDeviceFlow()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "person.badge.key")
                Text("Login with GitHub")
            }
            .font(.system(.subheadline, design: .rounded))
            .fontWeight(.medium)
            .foregroundStyle(.blue)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func deviceFlowAwaitingView(userCode: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(.green)
                    .font(.system(.caption))
                Text("GitHub opened in your browser.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Enter this code on GitHub:")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Text(userCode)
                        .font(.system(.title3, design: .monospaced))
                        .fontWeight(.bold)
                        .tracking(4)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(userCode, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(.caption))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text("Waiting for authorization\u{2026}")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Button("Cancel") { model.cancelDeviceFlow() }
                .buttonStyle(.plain)
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var tokenInputView: some View {
        VStack(alignment: .leading, spacing: 6) {
            SecureField("GitHub Personal Access Token", text: $tokenInput)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))
            HStack {
                Button("Save") {
                    model.saveToken(tokenInput)
                    tokenInput = ""
                }
                .buttonStyle(.plain)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.blue)
                .disabled(tokenInput.isEmpty)
                Spacer()
                Text("Create a token at github.com/settings/tokens")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private var tokenValidView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                if let username = model.githubUsername {
                    Text("@\(username)")
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.medium)
                }
                Spacer()
                Button("Remove Token") {
                    model.deleteToken()
                }
                .buttonStyle(.plain)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.red)
            }

            if let remaining = model.rateLimitRemaining {
                Text(rateLimitDisplayText(remaining: remaining))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(rateLimitDisplayColor(remaining: remaining))
            }
        }
    }

    // MARK: - Watch Items Section

    @ViewBuilder
    private var watchItemsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Repositories & Organizations")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button {
                    isFetchingRepos = true
                    Task {
                        await model.fetchUserRepos()
                        await model.fetchUserOrgs()
                        isFetchingRepos = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        if isFetchingRepos {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text("Fetch Repos & Orgs")
                    }
                    .font(.system(.caption, design: .rounded))
                }
                .buttonStyle(.plain)
                .disabled(isFetchingRepos)
            }

            if !model.availableRepos.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Search repos...", text: $repoSearchText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.caption, design: .rounded))

                    ScrollView {
                        VStack(spacing: 3) {
                            ForEach(filteredRepos, id: \.self) { repoName in
                                repoRow(for: repoName)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .frame(maxHeight: 150)
                }
            }

            if !model.availableOrgs.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Organizations")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.tertiary)

                    ScrollView {
                        VStack(spacing: 3) {
                            ForEach(model.availableOrgs, id: \.self) { orgName in
                                orgRow(for: orgName)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .frame(maxHeight: 100)
                }
            }

            if !model.watchItems.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Watching")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.tertiary)

                    ForEach(model.watchItems) { item in
                        watchItemRow(for: item)
                    }
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.14)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.18), lineWidth: 1))
    }

    @ViewBuilder
    private func repoRow(for repoName: String) -> some View {
        let isWatched = model.watchItems.contains { $0.name == repoName && $0.type == .repo }
        HStack(spacing: 6) {
            Toggle("", isOn: Binding(
                get: { isWatched },
                set: { enabled in
                    if enabled {
                        model.addWatchItem(name: repoName, type: .repo)
                    } else if let item = model.watchItems.first(where: { $0.name == repoName && $0.type == .repo }) {
                        model.removeWatchItem(id: item.id)
                    }
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.mini)

            VStack(alignment: .leading, spacing: 1) {
                Text(repoName.components(separatedBy: "/").last ?? repoName)
                    .font(.system(.caption, design: .rounded))
                    .lineLimit(1)
                Text(repoName)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()
        }
    }

    @ViewBuilder
    private func orgRow(for orgName: String) -> some View {
        let isWatched = model.watchItems.contains { $0.name == orgName && $0.type == .organization }
        HStack(spacing: 6) {
            Toggle("", isOn: Binding(
                get: { isWatched },
                set: { enabled in
                    if enabled {
                        model.addWatchItem(name: orgName, type: .organization)
                    } else if let item = model.watchItems.first(where: { $0.name == orgName && $0.type == .organization }) {
                        model.removeWatchItem(id: item.id)
                    }
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.mini)

            Image(systemName: "building.2")
                .font(.system(.caption))
                .foregroundStyle(.secondary)

            Text(orgName)
                .font(.system(.caption, design: .rounded))
                .lineLimit(1)

            Spacer()
        }
    }

    @ViewBuilder
    private func watchItemRow(for item: GitHubWatchItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: item.type == .repo ? "chevron.left.forwardslash.chevron.right" : "building.2")
                .font(.system(.caption))
                .foregroundStyle(.secondary)
                .frame(width: 14, alignment: .center)

            Text(item.name)
                .font(.system(.caption, design: .rounded))
                .lineLimit(1)

            Spacer()

            Toggle("", isOn: Binding(
                get: { item.isActive },
                set: { _ in model.toggleWatchItem(id: item.id) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.mini)

            Button {
                model.removeWatchItem(id: item.id)
            } label: {
                Image(systemName: "minus.circle")
                    .foregroundStyle(.red.opacity(0.8))
            }
            .buttonStyle(.plain)
            .font(.system(.caption))
        }
    }

    private var filteredRepos: [String] {
        guard !repoSearchText.isEmpty else { return model.availableRepos }
        return model.availableRepos.filter { $0.localizedCaseInsensitiveContains(repoSearchText) }
    }

    // MARK: - Event Filters Section

    @ViewBuilder
    private var eventFiltersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Event Filters")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(GitHubEventType.allCases, id: \.rawValue) { eventType in
                    eventFilterRow(for: eventType)
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.14)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.18), lineWidth: 1))
    }

    @ViewBuilder
    private func eventFilterRow(for eventType: GitHubEventType) -> some View {
        let isOn = model.enabledEventTypes.contains(eventType.rawValue)
        HStack(spacing: 5) {
            Image(systemName: eventType.icon)
                .font(.system(.caption2))
                .foregroundStyle(isOn ? .primary : .tertiary)
                .frame(width: 12, alignment: .center)
            Text(eventType.displayName)
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(isOn ? .primary : .tertiary)
                .lineLimit(1)
            Spacer()
            Toggle("", isOn: Binding(
                get: { isOn },
                set: { enabled in
                    if enabled {
                        model.enabledEventTypes.insert(eventType.rawValue)
                    } else {
                        model.enabledEventTypes.remove(eventType.rawValue)
                    }
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.mini)
        }
    }

    // MARK: - Settings Section

    @ViewBuilder
    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Settings")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)

            HStack {
                Text("Polling Interval")
                    .font(.system(.subheadline, design: .rounded))
                Spacer()
                Picker("Polling Interval", selection: $model.pollingInterval) {
                    Text("1 min").tag(60)
                    Text("2 min").tag(120)
                    Text("5 min").tag(300)
                    Text("10 min").tag(600)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .controlSize(.mini)
            }

            HStack {
                Text("Notification Sound")
                    .font(.system(.subheadline, design: .rounded))
                Spacer()
                Toggle("", isOn: $model.notificationSound)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.mini)
            }

            HStack {
                Button {
                    Task { await model.fetchEvents() }
                } label: {
                    HStack(spacing: 4) {
                        if model.isPolling {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text("Poll Now")
                    }
                    .font(.system(.caption, design: .rounded))
                }
                .buttonStyle(.plain)
                .disabled(model.isPolling)

                Spacer()

                if let lastPoll = model.lastPollDate {
                    Text("Last polled: \(relativeTime(from: lastPoll))")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.14)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.18), lineWidth: 1))
    }

    // MARK: - Recent Events Section

    @ViewBuilder
    private var recentEventsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Events")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(model.events) { event in
                        eventCard(for: event)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 200)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.14)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.18), lineWidth: 1))
    }

    @ViewBuilder
    private func eventCard(for event: GitHubEventItem) -> some View {
        let eventType = GitHubEventType(rawValue: event.type)
        Button {
            if let urlString = event.htmlURL, let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: eventType?.icon ?? "bell")
                    .font(.system(.caption))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, alignment: .center)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(event.repoName)
                            .font(.system(.caption, design: .rounded))
                            .fontWeight(.semibold)
                            .lineLimit(1)
                        Text("· \(event.actorLogin)")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Text(event.summary)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Text(relativeTime(from: event.createdAt))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func rateLimitDisplayText(remaining: Int) -> String {
        var text = "\(remaining)/5000 requests"
        if let resetDate = model.rateLimitReset {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            text += " · Resets at \(formatter.string(from: resetDate))"
        }
        return text
    }

    private func rateLimitDisplayColor(remaining: Int) -> Color {
        if remaining < 10 { return .red }
        if remaining < 100 { return .yellow }
        return .secondary
    }

    private func relativeTime(from date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        return "\(hours / 24)d ago"
    }
}
