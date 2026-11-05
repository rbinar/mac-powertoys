import SwiftUI

// MARK: - PaletteCommand

/// A module action exposed in the Quick Launch command palette.
struct PaletteCommand: Identifiable {
    enum Group: String, CaseIterable {
        case screenTools = "Screen Tools"
        case modes = "Modes"
        case tools = "Tools"
    }

    let id: String            // stable, e.g. "screenRuler.start"
    let title: String
    let subtitle: String
    let symbol: String        // SF Symbol
    let group: Group
    let shortcut: String?     // display only
    let keywords: [String]
    let isOn: (() -> Bool)?   // Modes only
    let run: () -> Void       // Screen Tools: start immediately; Modes: toggle
    var screen: ((_ onBack: @escaping () -> Void) -> AnyView)? // Tools: the module's view (filled in by the registry); also used by ⌘↩ for every command
    var screenWidth: CGFloat? = nil // set = wide palette-style screen: this width, no header, Esc closes the panel

    init(
        id: String,
        title: String,
        subtitle: String,
        symbol: String,
        group: Group,
        shortcut: String? = nil,
        keywords: [String] = [],
        isOn: (() -> Bool)? = nil,
        run: @escaping () -> Void = {},
        screen: ((_ onBack: @escaping () -> Void) -> AnyView)? = nil,
        screenWidth: CGFloat? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.group = group
        self.shortcut = shortcut
        self.keywords = keywords
        self.isOn = isOn
        self.run = run
        self.screen = screen
        self.screenWidth = screenWidth
    }
}

// MARK: - Palette rows

enum PaletteItem: Identifiable {
    case command(PaletteCommand, rowID: String)
    case entry(LaunchEntry)

    var id: String {
        switch self {
        case .command(_, let rowID): return rowID
        case .entry(let entry): return "entry." + entry.id.uuidString
        }
    }
}

struct PaletteSection: Identifiable {
    let id: String
    let title: String?
    let items: [PaletteItem]
}
