import SwiftUI
import AppKit
import Combine

// MARK: - QuickLaunchPanelController

class QuickLaunchPanelController {
    private var panel: NSPanel?
    private var model: QuickLaunchModel
    private var clickMonitor: Any?
    private var keyMonitor: Any?
    private var screenObserver: AnyCancellable?
    private var resignKeyObserver: NSObjectProtocol?

    @MainActor
    init(model: QuickLaunchModel) {
        self.model = model
        screenObserver = model.$activeScreen
            .map { $0 != nil }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] showingScreen in
                self?.applyLayout(showingScreen: showingScreen)
            }
    }

    func showPanel() {
        if panel == nil {
            createPanel()
        }
        positionPanel()
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
        installMonitors()
    }

    func hidePanelWindow() {
        panel?.orderOut(nil)
        removeMonitors()
    }

    func hidePanel() {
        panel?.orderOut(nil)
        removeMonitors()
        Task { @MainActor in
            self.model.hidePanel()
        }
    }

    func cleanup() {
        if let resizeObserver { NotificationCenter.default.removeObserver(resizeObserver) }
        resizeObserver = nil
        if let resignKeyObserver { NotificationCenter.default.removeObserver(resignKeyObserver) }
        resignKeyObserver = nil
        removeMonitors()
        panel?.orderOut(nil)
        panel = nil
    }

    // MARK: - Private

    private class KeyablePanel: NSPanel {
        override var canBecomeKey: Bool { true }
    }

    private func createPanel() {
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 56),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: true
        )
        panel.level = .floating
        panel.isMovableByWindowBackground = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true

        let contentView = QuickLaunchPanelContent(model: model)
        let hostingView = NSHostingView(rootView: contentView)
        panel.contentView = hostingView

        self.panel = panel

        // The list panel's height follows its content; keep its top edge where
        // positionPanel() put it so the search field doesn't jump while typing.
        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.pinTopEdge() }
        }

        // Close the palette when it loses key status (e.g. ⌘Tab to another app).
        resignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            // Defer so NSApp.isActive / the new key window have settled.
            DispatchQueue.main.async { self?.closeIfFocusLost() }
        }
    }

    /// Ignores key loss caused by our own sheets/alerts/modal panels, and by windows a module screen
    /// opens while the app stays active; a hidden panel needs no second close.
    private func closeIfFocusLost() {
        guard let panel, panel.isVisible, !panel.isKeyWindow,
              panel.attachedSheet == nil, NSApp.modalWindow == nil else { return }
        let showingScreen = MainActor.assumeIsolated { model.activeScreen != nil }
        if showingScreen && NSApp.isActive { return }
        hidePanel()
    }

    /// Top edge for the list panel: chosen so the panel at its tallest (search + 420 pt list + footer)
    /// sits in the vertical middle of the screen.
    private var listTopY: CGFloat?
    private static let tallestListHeight: CGFloat = 56 + 420 + 30
    private var resizeObserver: NSObjectProtocol?

    @MainActor
    private func pinTopEdge() {
        guard let panel, let top = listTopY, model.activeScreen == nil else { return }
        let f = panel.frame
        if abs(f.maxY - top) > 0.5 {
            panel.setFrameOrigin(NSPoint(x: f.origin.x, y: top - f.height))
        }
        panel.invalidateShadow()
    }

    /// Module screens use a 380 x up-to-640 pt panel (the views are designed for a 340 pt popover).
    private func applyLayout(showingScreen: Bool) {
        guard let panel else { return }
        if showingScreen {
            let old = panel.frame
            let visible = (panel.screen ?? NSScreen.main)?.visibleFrame ?? old
            let width: CGFloat = 380
            let height = min(640, visible.height - 40)
            let y = visible.midY - height / 2
            panel.setFrame(NSRect(x: visible.midX - width / 2, y: y, width: width, height: height), display: true)
            panel.invalidateShadow()
        } else {
            panel.setContentSize(NSSize(width: 680, height: 56))
            positionPanel()
            panel.invalidateShadow()
        }
    }

    private func positionPanel() {
        guard let panel, let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let panelWidth: CGFloat = 680
        let x = screenFrame.midX - panelWidth / 2
        let top = min(screenFrame.maxY - 20, screenFrame.midY + Self.tallestListHeight / 2)
        listTopY = top
        panel.setFrameOrigin(NSPoint(x: x, y: top - panel.frame.height))
    }

    private func installMonitors() {
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            guard let panel = self?.panel else { return }
            let clickLocation = NSEvent.mouseLocation
            if !panel.frame.contains(clickLocation) {
                Task { @MainActor in
                    self?.hidePanel()
                }
            }
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let isCommand = event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command)
            // Local monitors run on the main thread.
            let showingScreen = MainActor.assumeIsolated { self.model.activeScreen != nil }
            switch event.keyCode {
            case 53: // Escape
                Task { @MainActor in
                    if showingScreen { self.model.closeScreen() } else { self.hidePanel() }
                }
                return nil
            case 33 where isCommand && showingScreen: // ⌘[
                Task { @MainActor in self.model.closeScreen() }
                return nil
            case 125 where !showingScreen: // Down Arrow
                Task { @MainActor in self.model.moveSelectionDown() }
                return nil
            case 126 where !showingScreen: // Up Arrow
                Task { @MainActor in self.model.moveSelectionUp() }
                return nil
            case 36 where !showingScreen: // Return
                Task { @MainActor in
                    if isCommand { self.model.openSelectedScreen() } else { self.model.launchSelected() }
                }
                return nil
            default:
                return event
            }
        }
    }

    private func removeMonitors() {
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }
}

// MARK: - QuickLaunchPanelContent

struct QuickLaunchPanelContent: View {
    @ObservedObject var model: QuickLaunchModel
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        Group {
            if let command = model.activeScreen {
                moduleScreen(command)
            } else {
                paletteList
            }
        }
        .background(
            VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.separator.opacity(0.5), lineWidth: 0.5)
        )
        // On the very first show the view appears before the panel is key; focus on the next tick.
        .onAppear { DispatchQueue.main.async { isSearchFocused = true } }
        .onChange(of: model.isPanelVisible) { visible in
            if visible { isSearchFocused = true }
        }
        .onChange(of: model.activeScreen == nil) { showingList in
            if showingList { isSearchFocused = true }
        }
    }

    // MARK: - Module screen

    private func moduleScreen(_ command: PaletteCommand) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    model.closeScreen()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text(command.title)
                            .font(.system(.headline, design: .rounded))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            command.screen?({ model.closeScreen() })
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: 380)
        .frame(maxHeight: .infinity)
    }

    // MARK: - Palette list

    private var paletteList: some View {
        VStack(spacing: 0) {
            searchBar

            if model.sections.isEmpty {
                if !model.searchText.isEmpty {
                    Divider()
                        .padding(.horizontal, 16)
                    Text("No Results")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 16)
                }
            } else {
                Divider()
                    .padding(.horizontal, 16)
                resultsList
                Divider()
                    .padding(.horizontal, 16)
                Text("↑↓ navigate · ↩ run · ⌘↩ settings · esc close")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 6)
            }
        }
        .frame(width: 680)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.title2)
                .foregroundStyle(.secondary)

            TextField("Search commands, apps, shortcuts...", text: $model.searchText)
                .font(.system(size: 22))
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var resultsList: some View {
        let sections = model.sections
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(sections.enumerated()), id: \.element.id) { sectionIndex, section in
                        let base = sections.prefix(sectionIndex).reduce(0) { $0 + $1.items.count }
                        if let title = section.title {
                            Text(title.uppercased())
                                .font(.system(.caption2, design: .rounded).weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8)
                                .padding(.top, 8)
                                .padding(.bottom, 2)
                        }
                        ForEach(Array(section.items.enumerated()), id: \.element.id) { offset, item in
                            row(item: item, index: base + offset)
                                .id(item.id)
                        }
                    }
                }
                .padding(.horizontal, 8)
            }
            .frame(maxHeight: 420)
            .onChange(of: model.selectedIndex) { index in
                let items = model.flatItems
                if items.indices.contains(index) {
                    proxy.scrollTo(items[index].id)
                }
            }
        }
    }

    @ViewBuilder
    private func row(item: PaletteItem, index: Int) -> some View {
        switch item {
        case .command(let command, _):
            commandRow(command, index: index, item: item)
        case .entry(let entry):
            entryRow(entry: entry, index: index, item: item)
        }
    }

    private func commandRow(_ command: PaletteCommand, index: Int, item: PaletteItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: command.symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(tint(for: command.group))
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 6).fill(tint(for: command.group).opacity(0.15)))

            VStack(alignment: .leading, spacing: 2) {
                Text(command.title)
                    .font(.system(.body, design: .rounded))
                    .lineLimit(1)
                Text(command.subtitle)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let isOn = command.isOn {
                let on = isOn()
                HStack(spacing: 4) {
                    Circle()
                        .fill(on ? Color.green : Color.secondary)
                        .frame(width: 6, height: 6)
                    Text(on ? "On" : "Off")
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.secondary.opacity(0.18)))
            }

            if let shortcut = command.shortcut {
                Text(shortcut)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.1)))
            }
        }
        .modifier(RowChrome(selected: model.selectedIndex == index) { model.activate(item) })
    }

    private func tint(for group: PaletteCommand.Group) -> Color {
        switch group {
        case .screenTools: return .blue
        case .modes: return .green
        case .tools: return .orange
        }
    }

    private func entryRow(entry: LaunchEntry, index: Int, item: PaletteItem) -> some View {
        HStack(spacing: 12) {
            entryIcon(for: entry)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.system(.body, design: .rounded))
                    .lineLimit(1)
                Text(entry.subtitle)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if model.selectedIndex == index {
                Text("↩")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
        }
        .modifier(RowChrome(selected: model.selectedIndex == index) { model.activate(item) })
    }

    @ViewBuilder
    private func entryIcon(for entry: LaunchEntry) -> some View {
        switch entry.action {
        case .app(let path):
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .aspectRatio(contentMode: .fit)
        case .file:
            Image(systemName: "doc.fill")
                .font(.title2)
                .foregroundStyle(.blue)
        case .folder:
            Image(systemName: "folder.fill")
                .font(.title2)
                .foregroundStyle(.blue)
        case .url:
            if let faviconData = entry.faviconData, let nsImage = NSImage(data: faviconData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "globe")
                    .font(.title2)
                    .foregroundStyle(.blue)
            }
        case .shellCommand:
            Image(systemName: "terminal.fill")
                .font(.title2)
                .foregroundStyle(.green)
        }
    }
}

// MARK: - RowChrome

private struct RowChrome: ViewModifier {
    let selected: Bool
    let onTap: () -> Void

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selected ? Color.accentColor.opacity(0.22) : .clear)
            )
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction(.default, onTap)
    }
}

// MARK: - VisualEffectBackground

struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
