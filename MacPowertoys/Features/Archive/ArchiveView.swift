import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ArchiveView: View {
    @EnvironmentObject var model: ArchiveModel
    let onBack: () -> Void
    var initialMode: ArchiveModel.Mode? = nil   // set by the palette's Extract / Compress commands

    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FeatureHeader(title: "Archive", onBack: onBack)
            Divider()
            Picker("", selection: $model.mode) {
                ForEach(ArchiveModel.Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()
            .disabled(model.isBusy)
            dropZone
            if !model.engineReady {
                missingEngine
            } else {
                if model.mode == .extract { extractSection } else { compressSection }
                busyAndMessages
            }
            Spacer(minLength: 0)
        }
        .padding()
        .onAppear { if let initialMode, !model.isBusy { model.mode = initialMode } }
    }

    // MARK: - Missing engine

    private var missingEngine: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.usesRAR ? "unar not found" : "7zz not found")
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
            Text(model.usesRAR
                 ? "Archive opens RAR files with The Unarchiver command line tools (unar and lsar). Install them with Homebrew, then check again."
                 : "Archive uses the 7-Zip command line tool. Install it with Homebrew, then check again.")
                .font(.caption).foregroundStyle(.secondary)
            Text(model.missingInstallCommand)
                .font(.system(.caption, design: .monospaced))
                .padding(6).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            HStack {
                Button("Copy Command") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.missingInstallCommand, forType: .string)
                }
                Button("Check Again") { model.checkAgain() }
            }
        }
    }

    // MARK: - Drop zone

    private var dropZone: some View {
        VStack(spacing: 8) {
            Image(systemName: "archivebox").font(.system(size: 26)).foregroundStyle(.secondary)
            Text(model.mode == .extract ? "Drop an archive" : "Drop files or folders")
                .font(.system(.subheadline, design: .rounded))
            Button("Choose…") { choose() }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                              style: StrokeStyle(lineWidth: 1.5, dash: [5]))
        )
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in handle(url) }
                }
            }
            return !providers.isEmpty
        }
        .disabled(model.isBusy)
    }

    private func handle(_ url: URL) {
        if model.mode == .extract { model.setArchive(url) } else { model.addItems([url]) }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = model.mode == .compress
        panel.allowsMultipleSelection = model.mode == .compress
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach(handle)
    }

    // MARK: - Extract

    @ViewBuilder
    private var extractSection: some View {
        if let url = model.archiveURL {
            Text(url.lastPathComponent).font(.system(.subheadline, design: .rounded)).lineLimit(1).truncationMode(.middle)
            if model.needsPassword {
                HStack {
                    SecureField("Password", text: $model.extractPassword)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { model.loadListing() }
                    Button("Unlock") { model.loadListing() }
                        .disabled(model.extractPassword.isEmpty || model.isBusy)
                }
            }
            if !model.entries.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(model.entries) { e in
                            HStack(spacing: 6) {
                                Image(systemName: e.isFolder ? "folder" : "doc").foregroundStyle(.secondary)
                                Text(e.path).lineLimit(1).truncationMode(.middle)
                                Spacer(minLength: 0)
                                if !e.isFolder {
                                    Text(ByteCountFormatter.string(fromByteCount: e.size, countStyle: .file))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .font(.caption)
                        }
                    }
                }
                .frame(maxHeight: 150)
                HStack {
                    Button("Extract Here") { model.extract(toFolder: false) }
                    Button("Extract to Folder") { model.extract(toFolder: true) }
                }
                .disabled(model.isBusy)
            }
        }
    }

    // MARK: - Compress

    @ViewBuilder
    private var compressSection: some View {
        if !model.items.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(model.items.prefix(4), id: \.self) {
                    Text($0.lastPathComponent).font(.caption).lineLimit(1).truncationMode(.middle)
                }
                if model.items.count > 4 {
                    Text("+ \(model.items.count - 4) more").font(.caption).foregroundStyle(.secondary)
                }
            }
            Picker("Format", selection: $model.format) {
                ForEach(ArchiveFormat.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            Picker("Level", selection: $model.level) {
                ForEach(ArchiveLevel.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            SecureField("Password (optional)", text: $model.compressPassword)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Compress") { model.compress() }
                Button("Clear") { model.clearItems() }
            }
            .disabled(model.isBusy)
        }
    }

    // MARK: - Progress and messages

    @ViewBuilder
    private var busyAndMessages: some View {
        if model.isBusy {
            HStack {
                if let p = model.progress { ProgressView(value: p) } else { ProgressView().controlSize(.small) }
                Button("Cancel") { model.cancel() }.controlSize(.small)
            }
        }
        if let message = model.statusMessage {
            HStack {
                Text(message).font(.caption).foregroundStyle(.secondary)
                if let url = model.resultURL {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                        .controlSize(.small)
                }
            }
        }
        if let message = model.errorMessage {
            Text(message).font(.caption).foregroundStyle(.red)
        }
    }
}
