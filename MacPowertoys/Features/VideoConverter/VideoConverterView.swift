import SwiftUI
import UniformTypeIdentifiers

struct VideoConverterView: View {
    @EnvironmentObject var model: VideoConverterModel
    let onBack: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerSection
            Divider()
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    if !model.ffmpegAvailable {
                        ffmpegWarningSection
                    }
                    
                    if !model.conversionHistory.isEmpty {
                        historySection
                    }
                    
                    if model.inputFileURL == nil {
                        inputSection
                    } else {
                        fileInfoSection
                        Divider()
                        formatSection
                        if !model.selectedFormat.isAudioOnly {
                            settingsSection
                        } else {
                            audioSettingsSection
                        }
                        Divider()
                        actionSection
                    }
                }
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
            
            Text("Video Converter")
                .font(.system(.headline, design: .rounded))
            
            Spacer()
        }
    }
    
    // MARK: - FFmpeg Warning
    
    private var ffmpegWarningSection: some View {
        VStack(spacing: 12) {
            if model.isInstallingFFmpeg {
                // Installing state
                VStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.regular)
                    
                    Text("Installing FFmpeg...")
                        .font(.system(.headline, design: .rounded))
                    
                    Text("This may take a few minutes")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                    
                    // Live log
                    ScrollView(.vertical, showsIndicators: true) {
                        Text(model.installLog)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(height: 80)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.black.opacity(0.3))
                    )
                }
            } else if model.ffmpegAvailable {
                // Just installed successfully
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.green)
                    
                    Text("FFmpeg Installed!")
                        .font(.system(.headline, design: .rounded))
                    
                    if let version = model.ffmpegVersion {
                        Text(version)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } else {
                // Not installed
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.yellow)
                
                Text("FFmpeg Not Found")
                    .font(.system(.headline, design: .rounded))
                
                Text("Video Converter requires FFmpeg to be installed on your system.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                
                if model.homebrewAvailable {
                    // Homebrew is available — offer one-click install
                    Button {
                        model.installFFmpeg()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.body.weight(.semibold))
                            Text("Install FFmpeg via Homebrew")
                                .font(.system(.subheadline, design: .rounded))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.accentColor.opacity(0.8))
                        )
                    }
                    .buttonStyle(.plain)
                    
                    if model.installFailed {
                        // Show log on failure
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Installation failed. Log:")
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(.red.opacity(0.8))
                            
                            ScrollView(.vertical, showsIndicators: true) {
                                Text(model.installLog)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                            .frame(height: 60)
                            .padding(6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(.black.opacity(0.3))
                            )
                        }
                    }
                } else {
                    // No Homebrew — show manual instructions
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Homebrew not found. Install it first:")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                        
                        HStack {
                            Text("/bin/bash -c \"$(curl -fsSL https://brew.sh/install.sh)\"")
                                .font(.system(size: 9, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(.black.opacity(0.3))
                                )
                                .lineLimit(2)
                            
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString("/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"", forType: .string)
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        Text("Then install FFmpeg:")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                        
                        HStack {
                            Text("brew install ffmpeg")
                                .font(.system(.caption, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(.black.opacity(0.3))
                                )
                            
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString("brew install ffmpeg", forType: .string)
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.white.opacity(0.05))
                    )
                }
                
                // Retry detection button
                Button {
                    model.retryDetection()
                } label: {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Retry Detection")
                    }
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 20)
    }
    
    // MARK: - Input Section (Drag & Drop)
    
    private var inputSection: some View {
        VStack(spacing: 10) {
            Image(systemName: "film.fill")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            
            Text("Drop video here")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
            
            Text("or click to browse")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    model.isDragTargeted ? Color.accentColor : Color.white.opacity(0.15),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6])
                )
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(model.isDragTargeted ? Color.accentColor.opacity(0.08) : Color.white.opacity(0.03))
                )
        )
        .onTapGesture {
            model.selectInputFile()
        }
        .onDrop(of: [.fileURL], isTargeted: $model.isDragTargeted) { providers in
            handleDrop(providers)
        }
    }
    
    // MARK: - File Info
    
    private var fileInfoSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "film.fill")
                    .foregroundStyle(.blue)
                
                Text(model.inputFileURL?.lastPathComponent ?? "")
                    .font(.system(.subheadline, design: .rounded))
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                Spacer()
                
                Button {
                    model.reset()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            if let metadata = model.inputMetadata {
                HStack(spacing: 12) {
                    Label(metadata.formattedResolution, systemImage: "rectangle.arrowtriangle.2.outward")
                    Label(metadata.codec, systemImage: "cpu")
                    Label(metadata.formattedDuration, systemImage: "clock")
                }
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.secondary)
                
                HStack(spacing: 12) {
                    Label(metadata.formattedFileSize, systemImage: "doc")
                    Label(String(format: "%.0f fps", metadata.frameRate), systemImage: "speedometer")
                    if metadata.hasAudioTrack {
                        Label(metadata.audioCodec ?? "Audio", systemImage: "speaker.wave.2")
                    }
                }
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.secondary)
            } else if case .analyzing = model.conversionState {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Analyzing...")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.1), lineWidth: 0.5)
        )
    }
    
    // MARK: - Format Section
    
    private var formatSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Output Format")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
            
            // Category picker
            Picker("Category", selection: $model.selectedCategory) {
                ForEach(VideoOutputFormat.FormatCategory.allCases) { category in
                    Text(category.rawValue).tag(category)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            
            // Format chips
            let formats = VideoOutputFormat.allCases.filter { $0.category == model.selectedCategory }
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 55), spacing: 6)
            ], spacing: 6) {
                ForEach(formats) { format in
                    formatChip(format)
                }
            }
        }
    }
    
    private func formatChip(_ format: VideoOutputFormat) -> some View {
        Button {
            model.selectedFormat = format
        } label: {
            Text(format.rawValue)
                .font(.system(size: 11, weight: model.selectedFormat == format ? .semibold : .regular, design: .rounded))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(model.selectedFormat == format ? Color.accentColor.opacity(0.25) : Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(model.selectedFormat == format ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Video Settings
    
    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Quality
            VStack(alignment: .leading, spacing: 4) {
                Text("Quality")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                
                Picker("Quality", selection: $model.selectedQuality) {
                    ForEach(VideoQualityPreset.allCases) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            
            // Resolution
            VStack(alignment: .leading, spacing: 4) {
                Text("Resolution")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                
                Picker("Resolution", selection: $model.selectedResolution) {
                    ForEach(ResolutionPreset.allCases) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }
                .labelsHidden()
            }
        }
    }
    
    // MARK: - Audio Settings
    
    private var audioSettingsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Audio Quality")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
            
            Picker("Quality", selection: $model.selectedQuality) {
                ForEach(VideoQualityPreset.allCases) { preset in
                    Text(preset.rawValue).tag(preset)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }
    
    // MARK: - Action Section
    
    private var actionSection: some View {
        Group {
            switch model.conversionState {
            case .idle, .analyzing:
                convertButton
            case .converting(let progress):
                progressSection(progress: progress)
            case .completed(let outputPath):
                completedSection(outputPath: outputPath)
            case .failed(let message):
                failedSection(message: message)
            case .cancelled:
                cancelledSection
            }
        }
    }
    
    private var convertButton: some View {
        Button {
            model.startConversion()
        } label: {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.body.weight(.semibold))
                Text("Convert to \(model.selectedFormat.rawValue)")
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.opacity(model.inputMetadata != nil ? 0.8 : 0.3))
            )
        }
        .buttonStyle(.plain)
        .disabled(model.inputMetadata == nil)
    }
    
    private func progressSection(progress: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Converting...")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Text("\(Int(progress * 100))%")
                    .font(.system(.caption, design: .monospaced).weight(.medium))
                    .foregroundStyle(.secondary)
                
                Text(model.formattedElapsedTime)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
                
                Button {
                    model.cancelConversion()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            ProgressView(value: progress)
                .progressViewStyle(.linear)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.white.opacity(0.05))
        )
    }
    
    private func completedSection(outputPath: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Conversion Complete")
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
            }
            
            let url = URL(fileURLWithPath: outputPath)
            Text(url.lastPathComponent)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            
            Text("Completed in \(model.formattedElapsedTime)")
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.tertiary)
            
            HStack(spacing: 8) {
                Button {
                    model.revealInFinder(outputPath)
                } label: {
                    HStack {
                        Image(systemName: "folder")
                        Text("Show in Finder")
                    }
                    .font(.system(.caption, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.white.opacity(0.1))
                    )
                }
                .buttonStyle(.plain)
                
                Button {
                    model.reset()
                } label: {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("New")
                    }
                    .font(.system(.caption, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.white.opacity(0.1))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.green.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.green.opacity(0.2), lineWidth: 0.5)
        )
    }
    
    private func failedSection(message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Text("Conversion Failed")
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
            }
            
            Text(message)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
            
            Button {
                model.conversionState = .idle
            } label: {
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Try Again")
                }
                .font(.system(.caption, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.white.opacity(0.1))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.red.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.red.opacity(0.2), lineWidth: 0.5)
        )
    }
    
    private var cancelledSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
                Text("Conversion Cancelled")
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
            }
            
            HStack(spacing: 8) {
                Button {
                    model.conversionState = .idle
                } label: {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Try Again")
                    }
                    .font(.system(.caption, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.white.opacity(0.1))
                    )
                }
                .buttonStyle(.plain)
                
                Button {
                    model.reset()
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("Reset")
                    }
                    .font(.system(.caption, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.white.opacity(0.1))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.orange.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.orange.opacity(0.2), lineWidth: 0.5)
        )
    }
    
    // MARK: - History
    
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recent Conversions")
                .font(.system(.caption, design: .rounded).weight(.medium))
                .foregroundStyle(.secondary)
            
            ForEach(model.conversionHistory) { item in
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 10))
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.inputName)
                            .font(.system(size: 10, design: .rounded))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        
                        Text("\(item.outputFormat) · \(formatElapsed(item.elapsedTime))")
                            .font(.system(size: 9, design: .rounded))
                            .foregroundStyle(.tertiary)
                    }
                    
                    Spacer()
                    
                    Button {
                        model.revealInFinder(item.outputPath)
                    } label: {
                        Image(systemName: "folder")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 3)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.white.opacity(0.03))
        )
    }
    
    private func formatElapsed(_ time: TimeInterval) -> String {
        let m = Int(time) / 60
        let s = Int(time) % 60
        return String(format: "%d:%02d", m, s)
    }
    
    // MARK: - Helpers
    
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            Task { @MainActor in
                model.setInputFile(url)
            }
        }
        return true
    }
}
