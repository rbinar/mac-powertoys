import SwiftUI
import AppKit

/// Selection/search state of the palette screen. A reference type so the key monitor always sees current values.
@MainActor
final class ClipboardPaletteState: ObservableObject {
    @Published var query = "" {
        didSet { selectedID = nil }
    }
    @Published var selectedID: UUID?

    func items(_ model: ClipboardManagerModel) -> [ClipboardItem] {
        ClipboardManagerModel.ordered(model.clipboardItems, matching: query)
    }

    func selected(_ model: ClipboardManagerModel) -> ClipboardItem? {
        let items = items(model)
        return items.first { $0.id == selectedID } ?? items.first
    }

    func move(_ delta: Int, _ model: ClipboardManagerModel) {
        let items = items(model)
        guard !items.isEmpty else { return }
        let current = items.firstIndex { $0.id == selected(model)?.id } ?? 0
        selectedID = items[min(items.count - 1, max(0, current + delta))].id
    }
}

/// Clipboard history as a Quick Launch palette screen: search, list on the left, preview on the right.
/// ↑/↓ select, ↩ (or ⇧↩, identical because history holds plain text only) pastes into the previous app.
struct ClipboardPaletteView: View {
    static let width: CGFloat = 680

    @EnvironmentObject var model: ClipboardManagerModel
    @StateObject private var state = ClipboardPaletteState()
    @FocusState private var searchFocused: Bool
    @State private var keyMonitor: Any?

    var body: some View {
        VStack(spacing: 0) {
            if model.isEnabled {
                searchBar
                Divider()
                content
                Divider()
                Text("↑↓ navigate · ↩ paste · esc close")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                disabledRow
            }
        }
        .frame(width: Self.width)
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear {
            DispatchQueue.main.async { searchFocused = true }
            installKeyMonitor()
        }
        .onDisappear(perform: removeKeyMonitor)
    }

    // MARK: - Parts

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.title2)
                .foregroundStyle(.secondary)
            TextField("Search clipboard history…", text: $state.query)
                .font(.system(size: 22))
                .textFieldStyle(.plain)
                .focused($searchFocused)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var content: some View {
        let items = state.items(model)
        if items.isEmpty {
            Text(model.clipboardItems.isEmpty ? "Clipboard history is empty" : "No Results")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let selected = state.selected(model)
            HStack(spacing: 0) {
                list(items, selectedID: selected?.id)
                    .frame(width: 280)
                Divider()
                preview(selected)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func list(_ items: [ClipboardItem], selectedID: UUID?) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(items) { item in
                        row(item, selected: item.id == selectedID)
                            .id(item.id)
                    }
                }
                .padding(8)
            }
            .onChange(of: selectedID) { id in
                if let id { proxy.scrollTo(id) }
            }
        }
    }

    private func row(_ item: ClipboardItem, selected: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: item.type == .image ? "photo" : "text.alignleft")
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(rowTitle(item))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.accentColor)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Color.accentColor.opacity(0.22) : .clear))
        .contentShape(Rectangle())
        .onTapGesture { paste(item) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(.default) { paste(item) }
    }

    private func rowTitle(_ item: ClipboardItem) -> String {
        guard item.type == .text, let text = item.textContent else { return "Image" }
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        return line.trimmingCharacters(in: .whitespaces).isEmpty ? "(whitespace)" : line
    }

    @ViewBuilder
    private func preview(_ item: ClipboardItem?) -> some View {
        if let item {
            if item.type == .text, let text = item.textContent {
                ScrollView {
                    Text(text)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                }
            } else if let url = item.imageURL, let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(14)
            }
        }
    }

    private var disabledRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.on.clipboard")
                .foregroundStyle(.secondary)
            Text("Clipboard history is off")
            Spacer()
            Button("Enable") { model.isEnabled = true }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Actions

    private func paste(_ item: ClipboardItem) {
        model.paste(item) {
            NotificationCenter.default.post(name: ModuleNotifications.hidePalette, object: nil)
        }
    }

    /// Return and arrow keys never reach the SwiftUI text field; Esc is handled by the Quick Launch panel.
    private func installKeyMonitor() {
        removeKeyMonitor()
        let state = state, model = model
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated {
                guard model.isEnabled else { return event }
                switch event.keyCode {
                case 125: state.move(1, model); return nil
                case 126: state.move(-1, model); return nil
                case 36, 76:
                    if let item = state.selected(model) {
                        model.paste(item) {
                            NotificationCenter.default.post(name: ModuleNotifications.hidePalette, object: nil)
                        }
                    }
                    return nil
                default: return event
                }
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}
