import SwiftUI
import AppKit

// MARK: - QuickLaunchPanelController

class QuickLaunchPanelController {
    private var panel: NSPanel?
    private var model: QuickLaunchModel
    private var clickMonitor: Any?
    private var keyMonitor: Any?

    init(model: QuickLaunchModel) {
        self.model = model
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
    }

    private func positionPanel() {
        guard let panel, let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let panelWidth: CGFloat = 680
        let x = screenFrame.midX - panelWidth / 2
        let y = screenFrame.origin.y + screenFrame.height * 0.65
        panel.setFrameOrigin(NSPoint(x: x, y: y))
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
            switch event.keyCode {
            case 53: // Escape
                Task { @MainActor in self.hidePanel() }
                return nil
            case 125: // Down Arrow
                Task { @MainActor in self.model.moveSelectionDown() }
                return nil
            case 126: // Up Arrow
                Task { @MainActor in self.model.moveSelectionUp() }
                return nil
            case 36: // Return
                Task { @MainActor in self.model.launchSelected() }
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
        VStack(spacing: 0) {
            searchBar

            if !model.searchResults.isEmpty {
                Divider()
                    .padding(.horizontal, 12)
                resultsList
            }
        }
        .frame(width: 680)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        .onAppear { isSearchFocused = true }
        .onChange(of: model.isPanelVisible) { visible in
            if visible { isSearchFocused = true }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.title2)
                .foregroundStyle(.secondary)

            TextField("Search apps, files, commands...", text: $model.searchText)
                .font(.system(size: 20, weight: .light, design: .rounded))
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var resultsList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(model.searchResults.prefix(QuickLaunchModel.maxVisibleResults).enumerated()), id: \.element.id) { index, entry in
                    resultRow(entry: entry, index: index)
                }
            }
        }
        .frame(maxHeight: 352)
    }

    private func resultRow(entry: LaunchEntry, index: Int) -> some View {
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

            if index == 0 {
                Text("↩")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(model.selectedIndex == index ? .white.opacity(0.14) : .clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            model.launchEntry(entry)
        }
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
            Image(systemName: "globe")
                .font(.title2)
                .foregroundStyle(.blue)
        case .shellCommand:
            Image(systemName: "terminal.fill")
                .font(.title2)
                .foregroundStyle(.green)
        }
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
