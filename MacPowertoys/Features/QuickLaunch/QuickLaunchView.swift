import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct QuickLaunchView: View {
    @EnvironmentObject var model: QuickLaunchModel
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Divider()

            hotkeyInfo

            Divider()

            statsRow

            Divider()

            customEntriesSection

            Spacer()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button { onBack() } label: {
                Label("Back", systemImage: "chevron.left")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.plain)

            Text("Quick Launch")
                .font(.system(.headline, design: .rounded))

            Spacer()
        }
    }

    // MARK: - Hotkey Info

    private var hotkeyInfo: some View {
        HStack {
            Text("Activation Shortcut")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer()
            Text("⌃⌥ Space")
                .font(.system(.caption, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.white.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.white.opacity(0.18), lineWidth: 0.8)
                )
        }
    }

    // MARK: - Stats

    private var statsRow: some View {
        HStack {
            Label("\(model.indexedApps.count) apps", systemImage: "app.badge")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)

            Text("·")
                .foregroundStyle(.quaternary)

            Label("\(model.customEntries.count) shortcuts", systemImage: "star.fill")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Custom Entries

    private var customEntriesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Custom Shortcuts")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    model.isAddingEntry = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if model.isAddingEntry {
                EntryFormView(model: model, entry: nil)
            }

            if let editing = model.editingEntry {
                EntryFormView(model: model, entry: editing)
            }

            if model.customEntries.isEmpty && !model.isAddingEntry {
                Text("No custom shortcuts yet.\nAdd one to quickly launch apps, files, URLs, or commands.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(model.customEntries) { entry in
                            CustomEntryRow(entry: entry)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        }
    }

}

// MARK: - Custom Entry Row

struct CustomEntryRow: View {
    @EnvironmentObject var model: QuickLaunchModel
    let entry: LaunchEntry
    @State private var isHovered = false
    @State private var showDeleteConfirm = false

    var body: some View {
        HStack(spacing: 10) {
            actionIcon(for: entry)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.system(.caption, design: .rounded))
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(entry.subtitle)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            if isHovered {
                HStack(spacing: 6) {
                    Button { model.editingEntry = entry } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Edit")

                    Button { showDeleteConfirm = true } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundStyle(.red.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .help("Delete")
                }
                .transition(.opacity)
            }

            actionTypeBadge(for: entry.action)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? .white.opacity(0.12) : .white.opacity(0.07))
        )
        .onHover { hovering in isHovered = hovering }
        .contextMenu {
            Button("Edit") {
                model.editingEntry = entry
            }
            Button("Delete", role: .destructive) {
                showDeleteConfirm = true
            }
        }
        .alert("Delete Shortcut", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                model.deleteEntry(entry)
            }
        } message: {
            Text("Are you sure you want to delete \"\(entry.name)\"?")
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func actionIcon(for entry: LaunchEntry) -> some View {
        switch entry.action {
        case .app(let path):
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .aspectRatio(contentMode: .fit)
        case .file:
            Image(systemName: "doc.fill")
                .foregroundStyle(.blue)
        case .folder:
            Image(systemName: "folder.fill")
                .foregroundStyle(.orange)
        case .url:
            if let faviconData = entry.faviconData, let nsImage = NSImage(data: faviconData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "globe")
                    .foregroundStyle(.blue)
            }
        case .shellCommand:
            Image(systemName: "terminal.fill")
                .foregroundStyle(.green)
        }
    }

    private func actionTypeBadge(for action: LaunchAction) -> some View {
        let label: String
        switch action {
        case .app: label = "App"
        case .file: label = "File"
        case .folder: label = "Folder"
        case .url: label = "URL"
        case .shellCommand: label = "Shell"
        }
        return Text(label)
            .font(.system(size: 9, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(.white.opacity(0.1))
            )
    }
}

// MARK: - Entry Form

struct EntryFormView: View {
    @ObservedObject var model: QuickLaunchModel
    let entry: LaunchEntry?

    @State private var name: String = ""
    @State private var actionType: ActionTypeOption = .app
    @State private var pathOrValue: String = ""
    @State private var keywordsText: String = ""
    @State private var validationError: String?

    enum ActionTypeOption: String, CaseIterable {
        case app = "App"
        case file = "File"
        case folder = "Folder"
        case url = "URL"
        case shellCommand = "Shell Command"
    }

    private var isEditing: Bool { entry != nil }
    private var canSave: Bool { !name.isEmpty && !pathOrValue.isEmpty }
    private var showBrowseButton: Bool {
        actionType == .app || actionType == .file || actionType == .folder
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Shortcut Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .rounded))

            Picker("Type", selection: $actionType) {
                ForEach(ActionTypeOption.allCases, id: \.self) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.menu)
            .font(.system(.caption, design: .rounded))
            .controlSize(.mini)

            HStack(spacing: 6) {
                TextField(placeholderForType, text: $pathOrValue)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .rounded))

                if showBrowseButton {
                    Button("Browse") { browseFile() }
                        .buttonStyle(.plain)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.blue)
                }
            }

            TextField("Keywords (comma separated)", text: $keywordsText)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .rounded))

            if let validationError {
                Text(validationError)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { cancel() }
                    .buttonStyle(.plain)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)

                Button(isEditing ? "Update" : "Save") { save() }
                    .buttonStyle(.plain)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.blue)
                    .disabled(!canSave)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.white.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.white.opacity(0.18), lineWidth: 0.8)
        )
        .onAppear {
            if let entry {
                name = entry.name
                keywordsText = entry.keywords.joined(separator: ", ")
                switch entry.action {
                case .app(let path): actionType = .app; pathOrValue = path
                case .file(let path): actionType = .file; pathOrValue = path
                case .folder(let path): actionType = .folder; pathOrValue = path
                case .url(let urlString): actionType = .url; pathOrValue = urlString
                case .shellCommand(let command): actionType = .shellCommand; pathOrValue = command
                }
            }
        }
    }

    private var placeholderForType: String {
        switch actionType {
        case .app: return "/Applications/App.app"
        case .file: return "/path/to/file"
        case .folder: return "/path/to/folder"
        case .url: return "https://..."
        case .shellCommand: return "echo hello"
        }
    }

    private func browseFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false

        switch actionType {
        case .app:
            panel.allowedContentTypes = [UTType.application]
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
        case .file:
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
        case .folder:
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
        default:
            return
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        pathOrValue = url.path
        if name.isEmpty {
            name = url.deletingPathExtension().lastPathComponent
        }
    }

    private func save() {
        switch actionType {
        case .app, .file, .folder:
            if !FileManager.default.fileExists(atPath: pathOrValue) {
                validationError = "File or folder not found at this path."
                return
            }
        case .url:
            if URL(string: pathOrValue) == nil || (!pathOrValue.hasPrefix("http://") && !pathOrValue.hasPrefix("https://")) {
                validationError = "Please enter a valid URL starting with http:// or https://"
                return
            }
        case .shellCommand:
            break
        }
        validationError = nil

        let action: LaunchAction
        switch actionType {
        case .app: action = .app(path: pathOrValue)
        case .file: action = .file(path: pathOrValue)
        case .folder: action = .folder(path: pathOrValue)
        case .url: action = .url(urlString: pathOrValue)
        case .shellCommand: action = .shellCommand(command: pathOrValue)
        }

        let keywords = keywordsText
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        if var existing = entry {
            existing.name = name
            existing.action = action
            existing.subtitle = model.subtitleForAction(action)
            existing.keywords = keywords
            model.updateEntry(existing)
            model.editingEntry = nil
        } else {
            model.addEntry(name: name, action: action, keywords: keywords)
            model.isAddingEntry = false
        }
    }

    private func cancel() {
        model.isAddingEntry = false
        model.editingEntry = nil
    }
}
