import SwiftUI
import AppKit
import ServiceManagement

struct FeatureCardView<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: String
    let action: () -> Void
    @ViewBuilder let content: Content
    
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                action()
            } label: {
                HStack {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                content
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isHovered ? AnyShapeStyle(.quaternary.opacity(0.85)) : AnyShapeStyle(.quaternary.opacity(0.45)))
        )
        .overlay {
            if contrast == .increased {
                RoundedRectangle(cornerRadius: 16).strokeBorder(.separator, lineWidth: 1)
            }
        }
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}

struct CompactFeatureCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: String
    let icon: String
    let statusText: String
    let isEnabled: Binding<Bool>?
    let action: () -> Void
    
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Color.primary.opacity(0.14))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(Color.primary.opacity(0.18), lineWidth: 0.8)
                    )
                Spacer()
                if let binding = isEnabled {
                    // Layout placeholder only; the real toggle is overlaid below, outside the button.
                    Toggle("Enable \(title)", isOn: binding)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .controlSize(.small)
                        .hidden()
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary) // style-ok decorative chevron
                }
            }
            
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .lineLimit(1)
            
            Text(statusText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(statusText)")
        .overlay(alignment: .topTrailing) {
            if let binding = isEnabled {
                Toggle("Enable \(title)", isOn: binding)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(height: 28)
                    .padding(10)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isHovered ? AnyShapeStyle(.quaternary.opacity(0.85)) : AnyShapeStyle(.quaternary.opacity(0.45)))
        )
        .overlay {
            if contrast == .increased {
                RoundedRectangle(cornerRadius: 14).strokeBorder(.separator, lineWidth: 1)
            }
        }
        .accessibilityElement(children: .contain)
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}

struct ContentView: View {
    enum Route: Hashable {
        case module(String)
        case group(String)
        case settings
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject var registry: ModuleRegistry
    @State private var route: Route? = nil

    var body: some View {
        Group {
            if let route {
                screen(for: route)
            } else {
                featureHub
            }
        }
        .padding(12)
        .onReceive(NotificationCenter.default.publisher(for: ModuleNotifications.show)) { note in
            guard let id = note.object as? String, registry.module(id) != nil else { return }
            go(.module(id))
            NSApp.activate(ignoringOtherApps: true)
        }
        .onReceive(registry.objectWillChange) { _ in
            // objectWillChange fires before the mutation; check on the next main-queue turn.
            DispatchQueue.main.async { resetRouteIfGone() }
        }
    }

    private func resetRouteIfGone() {
        switch route {
        case .module(let id) where registry.module(id) == nil: route = nil
        case .group(let id) where groupItem(id) == nil: route = nil
        default: break
        }
    }

    // MARK: - Navigation

    private func go(_ route: Route?) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) {
            self.route = route
        }
    }

    // MARK: - Feature Hub (main menu)

    @ViewBuilder
    private func cardView(_ item: HubItem) -> some View {
        switch item {
        case .module(let id):
            if let module = registry.module(id) {
                module.card { go(.module(id)) }
            }
        case .group(let group, let ids):
            GroupCardView(group: group, children: ids.compactMap { registry.module($0) }, open: { go(.group(group.id)) })
        }
    }

    private var featureHub: some View {
        let items = registry.hubItems
        // Modules with a custom card are full width, above the 2-column grid.
        let fullWidth = items.filter { item in
            if case .module(let id) = item { return registry.meta(id)?.isFullWidth ?? false }
            return false
        }
        let gridItems = items.filter { item in !fullWidth.contains { $0.id == item.id } }
        return VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text("Mac PowerToys")
                    .font(.headline)
            }

            Divider()

            ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 6) {

            AccessibilityBanner()

            ForEach(fullWidth) { cardView($0) }

            // Feature grid — two cards per row, order defined by `ModuleCatalog.all`
            ForEach(Array(stride(from: 0, to: gridItems.count, by: 2)), id: \.self) { rowStart in
                HStack(spacing: 6) {
                    cardView(gridItems[rowStart])
                    if rowStart + 1 < gridItems.count {
                        cardView(gridItems[rowStart + 1])
                    } else {
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
            }

            } // VStack inside ScrollView
            } // ScrollView

            Divider()

            // Footer
            HStack {
                LaunchAtLoginToggle()
                Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button { go(.settings) } label: { Image(systemName: "gearshape") }
                    .buttonStyle(.borderless)
                    .help("Modules")
                    .accessibilityLabel("Modules")
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("Quit", systemImage: "power")
                        .labelStyle(.titleAndIcon)
                }
                .keyboardShortcut("q")
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Screens

    @ViewBuilder
    private func screen(for route: Route) -> some View {
        switch route {
        case .settings:
            ModulesSettingsView(onBack: { go(nil) })
        case .module(let id):
            if let module = registry.module(id) {
                // Grouped modules go back to their group screen.
                let back: Route? = registry.meta(id)?.group.map { .group($0.id) }
                module.screen { go(back) }
            }
        case .group(let groupID):
            if let (group, ids) = groupItem(groupID) {
                GroupHubView(
                    group: group,
                    children: ids.compactMap { id in
                        guard let meta = registry.meta(id), let loaded = registry.module(id) else { return nil }
                        return (meta: meta, loaded: loaded)
                    },
                    onBack: { go(nil) },
                    open: { go(.module($0)) }
                )
            }
        }
    }

    private func groupItem(_ groupID: String) -> (HubGroup, [String])? {
        for item in registry.hubItems {
            if case .group(let group, let ids) = item, group.id == groupID { return (group, ids) }
        }
        return nil
    }
}

// MARK: - Accessibility Banner

private struct AccessibilityBanner: View {
    @State private var isTrusted = AXIsProcessTrusted()
    @State private var timer: Timer?

    var body: some View {
        Group {
            if !isTrusted {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.multicolor)
                    Text("Global shortcuts need Accessibility permission")
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("Grant…") {
                        let promptedKey = "accessibilityBanner.promptShown"
                        if UserDefaults.standard.bool(forKey: promptedKey) {
                            // The system prompt was already shown once; send the user to System Settings.
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                NSWorkspace.shared.open(url)
                            }
                        } else {
                            UserDefaults.standard.set(true, forKey: promptedKey)
                            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
                            _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
                        }
                    }
                    .controlSize(.small)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
            }
        }
        .onAppear {
            isTrusted = AXIsProcessTrusted()
            startTimerIfNeeded()
        }
        .onDisappear { stopTimer() }
    }

    private func startTimerIfNeeded() {
        stopTimer()
        guard !isTrusted else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            Task { @MainActor in
                isTrusted = AXIsProcessTrusted()
                if isTrusted { stopTimer() }
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - Launch at Login

private struct LaunchAtLoginToggle: View {
    @State private var isOn = false

    var body: some View {
        Toggle("Launch at Login", isOn: Binding(
            get: { isOn },
            set: { newValue in
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                    isOn = newValue
                } catch {
                    NSLog("[App] Launch at login failed: %@", error.localizedDescription)
                    isOn = SMAppService.mainApp.status == .enabled
                }
            }
        ))
        .toggleStyle(.switch)
        .controlSize(.small)
        .font(.caption)
        .onAppear { isOn = SMAppService.mainApp.status == .enabled }
    }
}
