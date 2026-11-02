import SwiftUI
import UniformTypeIdentifiers

struct VideoConverterView: View {
    @EnvironmentObject var model: VideoConverterModel
    let onBack: () -> Void
    private let homebrewInstallCommand = "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerSection
            Divider()
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    if !model.ffmpegAvailable {
                        ffmpegWarningSection
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
                    
                    if !model.conversionHistory.isEmpty {
                        historySection
                    }
                }
            }
        }
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        FeatureHeader(title: "Video Converter", onBack: onBack)
    }
    
    // MARK: - FFmpeg Warning
    
    private var ffmpegWarningSection: some View {
        VStack(spacing: 12) {
            if model.isInstallingFFmpeg {
                // Installing state
                VStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.regular)
                    
                    Text("Installing FFmpeg…")
                        .font(.headline)
                    
                    Text("This may take a few minutes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    // Live log
                    ScrollView(.vertical, showsIndicators: true) {
                        Text(model.installLog)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(height: 80)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color(nsColor: .separatorColor))
                    )
                }
            } else if model.ffmpegAvailable {
                // Just installed successfully
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.green)
                    
                    Text("FFmpeg Installed!")
                        .font(.headline)
                    
                    if let version = model.ffmpegVersion {
                        Text(version)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } else {
                // Not installed
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.orange)
                
                Text("FFmpeg Not Found")
                    .font(.headline)
                
                Text("Video Converter requires FFmpeg to be installed on your system.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                
                if model.homebrewAvailable {
                    // Homebrew is available — offer one-click install
                    Button {
                        model.installFFmpeg()
                    } label: {
                        Label("Install FFmpeg via Homebrew", systemImage: "arrow.down.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    
                    if model.installFailed {
                        // Show log on failure
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Installation failed. Log:")
                                .font(.caption)
                                .foregroundStyle(.red.opacity(0.8))
                            
                            ScrollView(.vertical, showsIndicators: true) {
                                Text(model.installLog)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                            .frame(height: 60)
                            .padding(6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(nsColor: .textBackgroundColor))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(Color(nsColor: .separatorColor))
                            )
                        }
                    }
                } else {
                    // No Homebrew — show manual instructions
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Homebrew not found. Install it first:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        HStack {
                            Text(homebrewInstallCommand)
                                .font(.system(.caption2, design: .monospaced))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color(nsColor: .textBackgroundColor))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .strokeBorder(Color(nsColor: .separatorColor))
                                )
                                .lineLimit(2)
                            
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(homebrewInstallCommand, forType: .string)
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Copy Homebrew install command")
                            .help("Copy Homebrew install command")
                        }
                        
                        Text("Then install FFmpeg:")
                            .font(.caption)
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
                                        .fill(Color(nsColor: .textBackgroundColor))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .strokeBorder(Color(nsColor: .separatorColor))
                                )
                            
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString("brew install ffmpeg", forType: .string)
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Copy FFmpeg install command")
                            .help("Copy FFmpeg install command")
                        }
                    }
                    .padding(10)
                    .cardBackground()
                }
                
                // Retry detection button
                Button {
                    model.retryDetection()
                } label: {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Retry Detection")
                    }
                    .font(.caption)
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
        Button {
            model.selectInputFile()
        } label: {
        VStack(spacing: 10) {
            Image(systemName: "film.fill")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            
            Text("Drop video here")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Text("or click to browse")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    model.isDragTargeted ? Color.accentColor : Color.primary.opacity(0.15),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6])
                )
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(model.isDragTargeted ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.03))
                )
        )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Select video")
        .accessibilityHint("Or drop a video here")
        .onDrop(of: [.fileURL], isTargeted: $model.isDragTargeted) { providers in
            handleDrop(providers)
        }
    }
    
    // MARK: - File Info
    
    private var fileInfoSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "film.fill")
                    .foregroundStyle(.tint)
                
                Text(model.inputFileURL?.lastPathComponent ?? "")
                    .font(.subheadline)
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
                .accessibilityLabel("Remove input video")
                .help("Remove input video")
            }
            
            if let metadata = model.inputMetadata {
                HStack(spacing: 12) {
                    Label(metadata.formattedResolution, systemImage: "rectangle.arrowtriangle.2.outward")
                    Label(metadata.codec, systemImage: "cpu")
                    Label(metadata.formattedDuration, systemImage: "clock")
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                
                HStack(spacing: 12) {
                    Label(metadata.formattedFileSize, systemImage: "doc")
                    Label(String(format: "%.0f fps", metadata.frameRate), systemImage: "speedometer")
                    if metadata.hasAudioTrack {
                        Label(metadata.audioCodec ?? "Audio", systemImage: "speaker.wave.2")
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            } else if case .analyzing = model.conversionState {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Analyzing…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .cardBackground()
    }
    
    // MARK: - Format Section
    
    private var formatSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Output Format")
            
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
                .font(.system(size: 11, weight: model.selectedFormat == format ? .semibold : .regular))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(model.selectedFormat == format ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(model.selectedFormat == format ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(model.selectedFormat == format ? .isSelected : [])
    }
    
    // MARK: - Video Settings
    
    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Quality
            VStack(alignment: .leading, spacing: 4) {
                SectionHeader("Quality")
                
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
                SectionHeader("Resolution")
                
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
            SectionHeader("Audio Quality")
            
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
            Label("Convert to \(model.selectedFormat.rawValue)", systemImage: "arrow.triangle.2.circlepath")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .keyboardShortcut(.defaultAction)
        .disabled(model.inputMetadata == nil)
    }
    
    private func progressSection(progress: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Converting…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Text("\(Int(progress * 100))%")
                    .font(.system(.caption, design: .monospaced).weight(.medium))
                    .foregroundStyle(.secondary)
                
                Text(model.formattedElapsedTime)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                
                Button {
                    model.cancelConversion()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel conversion")
                .help("Cancel conversion")
            }
            
            ProgressView(value: progress)
                .progressViewStyle(.linear)
        }
        .padding(10)
        .cardBackground()
    }
    
    private func completedSection(outputPath: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Conversion Complete")
                    .font(.subheadline.weight(.medium))
            }
            
            let url = URL(fileURLWithPath: outputPath)
            Text(url.lastPathComponent)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            
            Text("Completed in \(model.formattedElapsedTime)")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            
            HStack(spacing: 8) {
                Button {
                    model.revealInFinder(outputPath)
                } label: {
                    HStack {
                        Image(systemName: "folder")
                        Text("Show in Finder")
                    }
                    .font(.caption)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.1))
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
                    .font(.caption)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.1))
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
                    .font(.subheadline.weight(.medium))
            }
            
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Button {
                model.conversionState = .idle
            } label: {
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Try Again")
                }
                .font(.caption)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.1))
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
                    .font(.subheadline.weight(.medium))
            }
            
            HStack(spacing: 8) {
                Button {
                    model.conversionState = .idle
                } label: {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Try Again")
                    }
                    .font(.caption)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.1))
                    )
                }
                .buttonStyle(.plain)
                
                Button {
                    model.reset()
                } label: {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Reset")
                    }
                    .font(.caption)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.1))
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
            SectionHeader("Recent Conversions")
            
            ForEach(model.conversionHistory) { item in
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 10))
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.inputName)
                            .font(.system(size: 10))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        
                        Text("\(item.outputFormat) · \(formatElapsed(item.elapsedTime))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
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
                    .accessibilityLabel("Reveal \(item.inputName) output in Finder")
                    .help("Reveal in Finder")
                }
                .padding(.vertical, 3)
            }
        }
        .padding(8)
        .cardBackground()
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
