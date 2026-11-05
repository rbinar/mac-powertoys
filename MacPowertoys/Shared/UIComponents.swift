import SwiftUI

/// Module screen header: the whole "‹ Title" area is one Back button (≥28 pt tall), ⌘[ goes back,
/// and an optional trailing slot holds the module's on/off switch or extra controls.
struct FeatureHeader<Trailing: View>: View {
    let title: String
    let onBack: () -> Void
    var escapeGoesBack = true                // false while the screen shows its own Esc-cancel form
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onBack) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
                .frame(minHeight: 28)
                .padding(.trailing, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("[", modifiers: .command)
            .help("Back")
            .accessibilityLabel("Back")
            .accessibilityHint(title)
            .background {
                // Esc also goes back; a button holds only one shortcut, so this one is invisible.
                if escapeGoesBack {
                    Button("Back", action: onBack)
                        .keyboardShortcut(.cancelAction)
                        .opacity(0)
                        .accessibilityHidden(true)
                }
            }

            Spacer(minLength: 0)

            trailing
        }
    }
}

extension FeatureHeader where Trailing == EmptyView {
    init(title: String, onBack: @escaping () -> Void) {
        self.init(title: title, onBack: onBack) { EmptyView() }
    }
}

/// Small grouped-section title used inside module screens.
struct SectionHeader: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
    }
}

/// The one card background used inside module screens.
struct CardBackground: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.45)))
            .overlay {
                if contrast == .increased {
                    RoundedRectangle(cornerRadius: 10).strokeBorder(.separator, lineWidth: 1)
                }
            }
    }
}

extension View {
    func cardBackground() -> some View { modifier(CardBackground()) }
}
