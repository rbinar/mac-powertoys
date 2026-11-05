import SwiftUI
import AppKit

/// Selection state of the palette screen. A reference type so the key monitor always sees current values.
@MainActor
final class AdvancedPasteState: ObservableObject {
    @Published var selection: PasteTransform = .plainText

    func result(_ transform: PasteTransform, _ model: AdvancedPasteModel) -> String? {
        AdvancedPasteModel.apply(transform, to: model.source, locale: .current)
    }

    /// The chosen transform, or the first one that applies when it does not (e.g. clipboard changed).
    func selected(_ model: AdvancedPasteModel) -> PasteTransform? {
        if result(selection, model) != nil { return selection }
        return PasteTransform.allCases.first { result($0, model) != nil }
    }

    func move(_ delta: Int, _ model: AdvancedPasteModel) {
        let available = PasteTransform.allCases.filter { result($0, model) != nil }
        guard !available.isEmpty else { return }
        let current = available.firstIndex { $0 == selected(model) } ?? 0
        selection = available[min(available.count - 1, max(0, current + delta))]
    }
}

/// Advanced Paste as a Quick Launch palette screen: transforms on the left, result preview on the right.
/// ↑/↓ select, ↩ writes the result as plain text and pastes it into the previous app.
struct AdvancedPastePaletteView: View {
    static let width: CGFloat = 680

    @EnvironmentObject var model: AdvancedPasteModel
    @StateObject private var state = AdvancedPasteState()
    @State private var keyMonitor: Any?

    var body: some View {
        VStack(spacing: 0) {
            if let text = model.source.text, !text.isEmpty {
                content
                Divider()
                Text("↑↓ navigate · ↩ paste · esc close")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                Text("Clipboard has no text")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .frame(width: Self.width)
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear {
            model.refreshSource()
            installKeyMonitor()
        }
        .onDisappear(perform: removeKeyMonitor)
    }

    private var content: some View {
        let selected = state.selected(model)
        return HStack(spacing: 0) {
            VStack(spacing: 0) {
                ForEach(PasteTransform.allCases, id: \.self) { transform in
                    row(transform, selected: transform == selected)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(width: 240)
            Divider()
            ScrollView {
                Text(selected.flatMap { state.result($0, model) } ?? "")
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minHeight: 280)
    }

    private func row(_ transform: PasteTransform, selected: Bool) -> some View {
        let available = state.result(transform, model) != nil
        return HStack(spacing: 8) {
            Image(systemName: transform.symbol)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(transform.title)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .opacity(available ? 1 : 0.4)
        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Color.accentColor.opacity(0.22) : .clear))
        .contentShape(Rectangle())
        .onTapGesture {
            guard available else { return }
            state.selection = transform
            pasteSelected()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func pasteSelected() {
        guard let transform = state.selected(model), let result = state.result(transform, model) else { return }
        model.paste(result) {
            NotificationCenter.default.post(name: ModuleNotifications.hidePalette, object: nil)
        }
    }

    /// Return and arrow keys are taken here; Esc is handled by the Quick Launch panel.
    private func installKeyMonitor() {
        removeKeyMonitor()
        let state = state, model = model
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated {
                switch event.keyCode {
                case 125: state.move(1, model); return nil
                case 126: state.move(-1, model); return nil
                case 36, 76:
                    if let transform = state.selected(model), let result = state.result(transform, model) {
                        model.paste(result) {
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
