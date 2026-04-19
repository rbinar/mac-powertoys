import SwiftUI
import UniformTypeIdentifiers
import AppKit
import CoreGraphics
import ImageIO

struct ImageOptimizerView: View {
    @EnvironmentObject var model: ImageOptimizerModel
    let onBack: () -> Void
    @State private var previewItemID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerSection
            Divider()
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    if model.items.isEmpty {
                        dropZoneSection
                    } else {
                        fileListSection
                    }
                    settingsCard
                    estimatedOutputRow
                    actionRow
                    stateStrip
                    beforeAfterSection
                }
            }
        }
        .onChange(of: model.state) { _, newState in
            if case .completed = newState {
                previewItemID = model.items.first(where: { $0.outputURL != nil })?.id
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            Button(action: onBack) {
                Label("Back", systemImage: "chevron.left")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.plain)
            Text("Image Optimizer")
                .font(.system(.headline, design: .rounded))
            Spacer()
        }
    }

    // MARK: - Drop Zone

    private var dropZoneSection: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(model.isDragTargeted ? Color.accentColor.opacity(0.08) : Color.white.opacity(0.03))
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    model.isDragTargeted ? Color.accentColor : Color.white.opacity(0.2),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6])
                )
            VStack(spacing: 8) {
                Image(systemName: "photo.stack")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text("Drop images here")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
                Text("JPEG · PNG · WebP · HEIC")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.tertiary)
                Text("or click to browse")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 24)
        }
        .onTapGesture { model.selectImages() }
        .onDrop(of: [.fileURL], isTargeted: $model.isDragTargeted) { providers in
            Task {
                var urls: [URL] = []
                for provider in providers {
                    if let url = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) as? URL {
                        urls.append(url)
                    } else if let data = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) as? Data,
                              let url = URL(dataRepresentation: data, relativeTo: nil) {
                        urls.append(url)
                    }
                }
                await MainActor.run { model.addImages(urls) }
            }
            return true
        }
    }

    // MARK: - File List

    private var fileListSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Images (\(model.items.count))")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear All") { model.clearAll() }
                    .font(.system(.caption2, design: .rounded))
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
            }
            ScrollView(.vertical) {
                VStack(spacing: 4) {
                    ForEach(model.items) { item in
                        HStack(spacing: 8) {
                            ZStack(alignment: .bottomTrailing) {
                                AsyncImageView(url: item.url, contentMode: .fill)
                                    .frame(width: 40, height: 40)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                if item.error != nil {
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.red)
                                        .background(Circle().fill(Color.black).padding(-1))
                                } else if item.isProcessed {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.green)
                                        .background(Circle().fill(Color.black).padding(-1))
                                }
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.name)
                                    .font(.system(.caption, design: .rounded))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                if let error = item.error {
                                    Text(error)
                                        .font(.system(.caption2, design: .rounded))
                                        .foregroundStyle(.red)
                                } else if item.isProcessed {
                                    Text(item.savingsDescription)
                                        .font(.system(.caption2, design: .rounded))
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text(ByteCountFormatter.string(fromByteCount: item.originalSize, countStyle: .file))
                                        .font(.system(.caption2, design: .rounded))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            Spacer()
                            if let outputURL = item.outputURL {
                                Button {
                                    model.revealInFinder(outputURL)
                                } label: {
                                    Image(systemName: "folder")
                                        .font(.caption2)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                            }
                            if !item.isProcessed {
                                Button {
                                    model.removeItem(item)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 160)
        }
        .onDrop(of: [.fileURL], isTargeted: $model.isDragTargeted) { providers in
            Task {
                var urls: [URL] = []
                for provider in providers {
                    if let url = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) as? URL {
                        urls.append(url)
                    } else if let data = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) as? Data,
                              let url = URL(dataRepresentation: data, relativeTo: nil) {
                        urls.append(url)
                    }
                }
                await MainActor.run { model.addImages(urls) }
            }
            return true
        }
    }

    // MARK: - Settings Card

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Output Format
            Text("Output Format")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
            Picker("", selection: $model.outputFormat) {
                ForEach(ImageOutputFormat.allCases) { format in
                    Text(format.rawValue).tag(format)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            // Quality
            HStack {
                Text("Quality")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(model.compressionQuality * 100))%")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Slider(value: $model.compressionQuality, in: 0.1...1.0, step: 0.05)
                .controlSize(.small)
            if model.outputFormat == .png {
                Text("PNG is lossless — quality affects JPEG/WebP output")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.tertiary)
            }

            // Resize toggle
            HStack {
                Toggle("Resize images", isOn: $model.shouldResize)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.system(.caption, design: .rounded))
                Spacer()
            }

            // Resize options
            if model.shouldResize {
                Picker("", selection: $model.resizeMode) {
                    ForEach(ResizeMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if model.resizeMode == .pixels {
                    HStack(spacing: 8) {
                        Text("Width")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.secondary)
                        TextField("1920", value: $model.resizeWidth, formatter: intFormatter)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                            .controlSize(.small)
                        Text("×")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                        Text("Height")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.secondary)
                        TextField("1080", value: $model.resizeHeight, formatter: intFormatter)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                            .controlSize(.small)
                    }
                    HStack {
                        Toggle("Maintain aspect ratio", isOn: $model.maintainAspectRatio)
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            .font(.system(.caption, design: .rounded))
                        Spacer()
                    }
                    if model.maintainAspectRatio {
                        Text("Largest dimension will be used as the constraint")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    HStack {
                        Text("Scale")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(model.resizePercent)%")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: Binding(
                            get: { Double(model.resizePercent) },
                            set: { model.resizePercent = Int($0) }
                        ),
                        in: 10...200,
                        step: 5
                    )
                    .controlSize(.small)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.14))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
        )
    }

    // MARK: - Estimated Output

    @ViewBuilder
    private var estimatedOutputRow: some View {
        if !model.items.isEmpty, !isProcessing, case .idle = model.state {
            HStack(spacing: 5) {
                Image(systemName: "info.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text("Est. output: \(model.estimatedSavingsDescription)")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Action Row

    private var actionRow: some View {
        HStack(spacing: 8) {
            Button {
                model.process()
            } label: {
                HStack {
                    if case .processing = model.state {
                        ProgressView().controlSize(.small)
                    }
                    Text(actionButtonLabel)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.items.isEmpty || isProcessing)

            if !model.items.isEmpty {
                Button {
                    model.reset()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .help("Reset")
            }
        }
    }

    // MARK: - State Strip

    @ViewBuilder
    private var stateStrip: some View {
        switch model.state {
        case .idle:
            EmptyView()
        case .processing(let progress, let message):
            VStack(alignment: .leading, spacing: 4) {
                Text(message)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
        case .completed(let totalSaved, let fileCount):
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Saved \(ByteCountFormatter.string(fromByteCount: totalSaved, countStyle: .file)) across \(fileCount) image\(fileCount == 1 ? "" : "s")")
                    .font(.system(.caption, design: .rounded))
                Spacer()
                if let outputURL = model.items.first(where: { $0.outputURL != nil })?.outputURL {
                    Button("Open Output Folder") {
                        NSWorkspace.shared.open(outputURL.deletingLastPathComponent())
                    }
                    .font(.system(.caption2, design: .rounded))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
        case .failed(let message):
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text(message)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
        }
    }

    // MARK: - Helpers

    private var actionButtonLabel: String {
        switch model.state {
        case .processing: return "Optimizing..."
        case .completed: return "Optimize Again"
        default: return "Optimize"
        }
    }

    private var isProcessing: Bool {
        if case .processing = model.state { return true }
        return false
    }

    private var intFormatter: NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .none
        f.minimum = 1
        f.maximum = 99999
        return f
    }

    private func fileIcon(_ item: ImageItem) -> String {
        if item.error != nil { return "exclamationmark.photo" }
        if item.isProcessed { return "photo.badge.checkmark" }
        return "photo"
    }

    private func selectedPreviewItem(from items: [ImageItem]) -> ImageItem? {
        items.first(where: { $0.id == previewItemID }) ?? items.first
    }

    // MARK: - Before / After

    @ViewBuilder
    private var beforeAfterSection: some View {
        let processedItems = model.items.filter { $0.outputURL != nil }
        if let item = selectedPreviewItem(from: processedItems) {
            VStack(alignment: .leading, spacing: 8) {
                if processedItems.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(processedItems) { pi in
                                Text(pi.name)
                                    .lineLimit(1)
                                    .font(.system(.caption2, design: .rounded))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule().fill(previewItemID == pi.id
                                            ? Color.accentColor.opacity(0.3)
                                            : Color.white.opacity(0.08))
                                    )
                                    .onTapGesture { previewItemID = pi.id }
                            }
                        }
                    }
                }

                HStack(alignment: .top, spacing: 8) {
                    VStack(spacing: 4) {
                        AsyncImageView(url: item.url, contentMode: .fit)
                            .frame(maxWidth: .infinity)
                            .frame(height: 90)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1)))
                        Text("Before")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.tertiary)
                        Text(ByteCountFormatter.string(fromByteCount: item.originalSize, countStyle: .file))
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.secondary)
                            .fontWeight(.medium)
                    }

                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 38)

                    VStack(spacing: 4) {
                        if let outputURL = item.outputURL {
                            AsyncImageView(url: outputURL, contentMode: .fit)
                                .frame(maxWidth: .infinity)
                                .frame(height: 90)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1)))
                        }
                        Text("After")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.tertiary)
                        Text(item.savingsDescription)
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.green)
                            .fontWeight(.medium)
                    }
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.1)))
        }
    }
}

// MARK: - Async Image Helper

private struct AsyncImageView: View {
    let url: URL
    let contentMode: ContentMode
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Color.white.opacity(0.04)
            }
        }
        .task(id: url) {
            image = await loadThumbnail(url)
        }
    }

    private func loadThumbnail(_ url: URL) async -> NSImage? {
        await Task.detached(priority: .utility) {
            let options = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 600,
                kCGImageSourceCreateThumbnailWithTransform: true
            ] as CFDictionary
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cgThumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
                return NSImage(contentsOf: url)
            }
            return NSImage(cgImage: cgThumb, size: .zero)
        }.value
    }
}
