import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct FileLocksmithView: View {
    @EnvironmentObject var model: FileLocksmithModel
    let onBack: () -> Void

    @State private var isDropTargeted = false
    @State private var pending: PendingAction?

    private struct PendingAction: Identifiable {
        let process: LockingProcess
        let force: Bool
        var id: String { "\(process.pid)-\(force)" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FeatureHeader(title: "File Locksmith", onBack: onBack)
            Divider()
            dropZone
            if let url = model.targetURL {
                VStack(alignment: .leading, spacing: 2) {
                    Text(url.lastPathComponent).font(.system(.subheadline, design: .rounded)).lineLimit(1)
                    Text(url.path).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(2).truncationMode(.middle)
                }
                HStack {
                    Button("Refresh") { model.refresh() }
                        .disabled(model.isScanning)
                    if model.isScanning { ProgressView().controlSize(.small) }
                }
                results
            }
            if let message = model.errorMessage {
                Text(message).font(.caption).foregroundStyle(.red)
            }
            Spacer(minLength: 0)
        }
        .padding()
        .alert(item: $pending) { action in
            Alert(
                title: Text(action.force ? "Force Quit \(action.process.name)?" : "Quit \(action.process.name)?"),
                message: Text(action.force
                    ? "Force quit \(action.process.name) (PID \(action.process.pid))? Unsaved work will be lost."
                    : "Quit \(action.process.name) (PID \(action.process.pid))? Unsaved work may be lost."),
                primaryButton: .destructive(Text(action.force ? "Force Quit" : "Quit")) {
                    model.signal(action.process, force: action.force)
                },
                secondaryButton: .cancel())
        }
    }

    private var dropZone: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock.doc").font(.system(size: 26)).foregroundStyle(.secondary)
            Text("Drop a file or folder").font(.system(.subheadline, design: .rounded))
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
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in model.setTarget(url) }
            }
            return true
        }
    }

    @ViewBuilder
    private var results: some View {
        if model.hasResult && model.processes.isEmpty {
            Text("No process is using this item")
                .font(.subheadline).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center).padding(.top, 8)
        } else if model.hasResult {
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(model.processes) { row($0) }
                }
            }
        }
        if model.hasResult {
            Text("Only your own processes are shown.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func row(_ p: LockingProcess) -> some View {
        HStack(spacing: 8) {
            icon(for: p).frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(p.name).font(.system(.subheadline, design: .rounded)).lineLimit(1)
                Text("PID \(p.pid) · \(p.user)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if model.stubbornPIDs.contains(p.pid) {
                Button("Force Quit…") { pending = PendingAction(process: p, force: true) }
            }
            Button("Quit…") { pending = PendingAction(process: p, force: false) }
        }
        .controlSize(.small)
    }

    @ViewBuilder
    private func icon(for p: LockingProcess) -> some View {
        if let image = NSRunningApplication(processIdentifier: p.pid)?.icon {
            Image(nsImage: image).resizable().scaledToFit()
        } else {
            Image(systemName: "gearshape").foregroundStyle(.secondary)
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { model.setTarget(url) }
    }
}
