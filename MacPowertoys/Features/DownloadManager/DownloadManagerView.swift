import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct DownloadManagerView: View {
    @EnvironmentObject var model: DownloadManagerModel
    let onBack: () -> Void

    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FeatureHeader(title: "Download Manager", onBack: onBack)
            Divider()
            if let offer = model.clipboardOffer { offerCard(offer) }
            input
            list
            Divider()
            settings
        }
        .padding()
        .frame(width: 340)
        .onAppear { model.refreshTools() }
    }

    // MARK: Input

    private var input: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("https://…", text: $model.urlText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.addFromInput() }
                Button("Download") { model.addFromInput() }
            }
            Toggle("Video (yt-dlp)", isOn: $model.videoMode).toggleStyle(.checkbox)
            if model.videoMode && model.ytDlpPath == nil {
                HStack {
                    Text(DownloadManagerModel.installCommand)
                        .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                    Button("Copy Command") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(DownloadManagerModel.installCommand, forType: .string)
                    }
                    .controlSize(.small)
                }
            }
            if let error = model.inputError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                              style: StrokeStyle(lineWidth: 1.5, dash: [5]))
        )
        .onDrop(of: [UTType.url], isTargeted: $isDropTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in model.urlText = url.absoluteString; model.addFromInput() }
            }
            return true
        }
    }

    private func offerCard(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Download this link?").font(.system(.subheadline, design: .rounded))
            Text(url.absoluteString).font(.caption).foregroundStyle(.secondary)
                .lineLimit(2).truncationMode(.middle)
            HStack {
                Button("Download") { model.acceptOffer() }
                Button("Dismiss") { model.dismissOffer() }
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.12)))
    }

    // MARK: List

    @ViewBuilder
    private var list: some View {
        if model.tasks.isEmpty {
            Text("No downloads yet")
                .font(.subheadline).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity).padding(.vertical, 16)
        } else {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(model.tasks) { row($0) }
                }
            }
        }
        Spacer(minLength: 0)
    }

    private func row(_ item: DownloadItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.fileName).font(.system(.subheadline, design: .rounded)).lineLimit(1).truncationMode(.middle)
            if item.state != .completed {
                if let fraction = item.fraction {
                    ProgressView(value: fraction)
                } else {
                    ProgressView(value: item.state == .downloading ? nil : 0)
                }
            }
            Text(status(item)).font(.caption).foregroundStyle(.secondary)
            if let message = item.message {
                Text(message).font(.caption).foregroundStyle(item.state == .failed ? Color.red : Color.orange)
            }
            HStack {
                switch item.state {
                case .downloading:
                    Button("Pause") { model.pause(item.id) }
                case .paused, .failed:
                    Button("Resume") { model.resume(item.id) }
                case .completed:
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.selectFile(model.revealPath(item), inFileViewerRootedAtPath: item.folderPath)
                    }
                }
                if item.state == .completed {
                    Button("Remove") { model.remove(item.id) }
                } else {
                    Button("Cancel") { model.cancel(item.id) }
                }
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.1)))
    }

    private func status(_ item: DownloadItem) -> String {
        var pieces: [String] = []
        switch item.state {
        case .downloading: pieces.append("Downloading")
        case .paused: pieces.append("Paused")
        case .completed: pieces.append("Done")
        case .failed: pieces.append("Failed")
        }
        if !item.isVideo, item.state != .completed {
            let done = ByteCountFormatter.string(fromByteCount: item.receivedBytes, countStyle: .file)
            if let total = item.totalLength {
                pieces.append("\(done) of \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))")
            } else {
                pieces.append(done)
            }
        }
        if item.state == .downloading, let speed = model.speedText[item.id] { pieces.append(speed) }
        return pieces.joined(separator: " · ")
    }

    // MARK: Settings

    private var settings: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text((model.saveFolderPath as NSString).abbreviatingWithTildeInPath)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
                Button("Change…") { chooseFolder() }.controlSize(.small)
            }
            Stepper("Connections: \(model.connections)", value: $model.connections, in: 1...8)
                .font(.caption)
            Toggle("Offer to download copied links", isOn: $model.watchClipboard)
                .toggleStyle(.checkbox).font(.caption)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { model.saveFolderPath = url.path }
    }
}
