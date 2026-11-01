import SwiftUI
import AppKit
import ServiceManagement

enum Feature: Hashable {
    case colorPicker
    case mouseUtilitiesHub
    case findMyMouse
    case mouseHighlighter
    case crosshairs
    case cursorWrap
    case screenRuler
    case zoomIt
    case awake
    case mouseJiggler
    case clipboardManager
    case markdownPreview
    case screenAnnotation
    case videoConverter
    case pomodoroTimer
    case testDataGenerator
    case speechToText
    case portManager
    case systemInfo
    case quickLaunch
    case pdfTools
    case screenCapture
    case gitHubNotifier
    case imageOptimizer
}

struct FeatureCardView<Content: View>: View {
    let title: String
    let action: () -> Void
    @ViewBuilder let content: Content
    
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                action()
            } label: {
                HStack {
                    Text(title)
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.semibold)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                content
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isHovered ? AnyShapeStyle(.quaternary.opacity(0.85)) : AnyShapeStyle(.quaternary.opacity(0.45)))
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}

struct CompactFeatureCard: View {
    let title: String
    let icon: String
    let statusText: String
    let isEnabled: Binding<Bool>?
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Color.primary.opacity(0.14))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(Color.primary.opacity(0.18), lineWidth: 0.8)
                    )
                Spacer()
                if let binding = isEnabled {
                    // Layout placeholder only; the real toggle is overlaid below, outside the button.
                    Toggle("Enable \(title)", isOn: binding)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .controlSize(.mini)
                        .hidden()
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            
            Text(title)
                .font(.system(.caption, design: .rounded))
                .fontWeight(.semibold)
                .lineLimit(1)
            
            Text(statusText)
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(statusText)")
        .overlay(alignment: .topTrailing) {
            if let binding = isEnabled {
                Toggle("Enable \(title)", isOn: binding)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.mini)
                    .frame(height: 28)
                    .padding(10)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isHovered ? AnyShapeStyle(.quaternary.opacity(0.85)) : AnyShapeStyle(.quaternary.opacity(0.45)))
        )
        .accessibilityElement(children: .contain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}

private struct FeatureCardSpec {
    let title: String
    let icon: String
    let statusText: String
    let isEnabled: Binding<Bool>?
    let feature: Feature
}

struct ContentView: View {
    @EnvironmentObject var model: ColorModel
    @EnvironmentObject var findMyMouseModel: FindMyMouseModel
    @EnvironmentObject var mouseHighlighterModel: MouseHighlighterModel
    @EnvironmentObject var crosshairsModel: CrosshairsModel
    @EnvironmentObject var cursorWrapModel: CursorWrapModel
    @EnvironmentObject var screenRulerModel: ScreenRulerModel
    @EnvironmentObject var zoomItModel: ZoomItModel
    @EnvironmentObject var awakeModel: AwakeModel
    @EnvironmentObject var mouseJigglerModel: MouseJigglerModel
    @EnvironmentObject var clipboardManagerModel: ClipboardManagerModel
    @EnvironmentObject var markdownPreviewModel: MarkdownPreviewModel
    @EnvironmentObject var screenAnnotationModel: ScreenAnnotationModel
    @EnvironmentObject var videoConverterModel: VideoConverterModel
    @EnvironmentObject var pomodoroTimerModel: PomodoroTimerModel
    @EnvironmentObject var speechToTextModel: SpeechToTextModel
    @EnvironmentObject var portManagerModel: PortManagerModel
    @EnvironmentObject var systemInfoModel: SystemInfoModel
    @EnvironmentObject var quickLaunchModel: QuickLaunchModel
    @EnvironmentObject var pdfToolsModel: PdfToolsModel
    @EnvironmentObject var screenCaptureModel: ScreenCaptureModel
    @EnvironmentObject var gitHubNotifierModel: GitHubNotifierModel
    @EnvironmentObject var imageOptimizerModel: ImageOptimizerModel
    @State private var activeFeature: Feature? = nil
    @State private var showingQuitAlert = false

    var body: some View {
        Group {
            if let feature = activeFeature {
                featureView(for: feature)
            } else {
                featureHub
            }
        }
        .padding(12)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowClipboardManager"))) { _ in
            withAnimation(.easeInOut(duration: 0.15)) {
                activeFeature = .clipboardManager
            }
            NSApp.activate(ignoringOtherApps: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowImageOptimizer"))) { _ in
            withAnimation(.easeInOut(duration: 0.15)) {
                activeFeature = .imageOptimizer
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Feature Grid Data

    private var featureCards: [FeatureCardSpec] {
        [
            FeatureCardSpec(title: "Screen Ruler", icon: "ruler", statusText: screenRulerModel.isActive ? "Measuring" : (screenRulerModel.isEnabled ? "⌃⌥R ready" : "Off"), isEnabled: $screenRulerModel.isEnabled, feature: .screenRuler),
            FeatureCardSpec(title: "ZoomIt", icon: "magnifyingglass", statusText: (zoomItModel.isZooming || zoomItModel.isLiveZooming) ? "Zooming" : (zoomItModel.isEnabled ? "⌃⌥Z / ⌃⌥L ready" : "Off"), isEnabled: $zoomItModel.isEnabled, feature: .zoomIt),
            FeatureCardSpec(title: "Mouse Utilities", icon: "cursorarrow", statusText: mouseUtilitiesStatusText, isEnabled: nil, feature: .mouseUtilitiesHub),
            FeatureCardSpec(title: "Mouse Jiggler", icon: "computermouse.fill", statusText: mouseJigglerModel.isEnabled ? "Running" : "Off", isEnabled: $mouseJigglerModel.isEnabled, feature: .mouseJiggler),
            FeatureCardSpec(title: "Awake", icon: "cup.and.saucer.fill", statusText: awakeModel.isEnabled ? (awakeModel.isIndefinite ? "Indefinite" : awakeModel.formattedRemaining) : "Off", isEnabled: $awakeModel.isEnabled, feature: .awake),
            FeatureCardSpec(title: "Pomodoro Timer", icon: "timer", statusText: pomodoroTimerStatusText, isEnabled: $pomodoroTimerModel.isEnabled, feature: .pomodoroTimer),
            FeatureCardSpec(title: "Clipboard Manager", icon: "list.clipboard", statusText: clipboardManagerModel.isEnabled ? "\(clipboardManagerModel.clipboardItems.count) items" : "Off", isEnabled: $clipboardManagerModel.isEnabled, feature: .clipboardManager),
            FeatureCardSpec(title: "Markdown Preview", icon: "doc.richtext", statusText: "\(markdownPreviewModel.recentFiles.count) recent", isEnabled: nil, feature: .markdownPreview),
            FeatureCardSpec(title: "Screen Annotation", icon: "pencil.tip.crop.circle", statusText: screenAnnotationModel.isActive ? "Drawing" : (screenAnnotationModel.isEnabled ? "⌃⌥D ready" : "Off"), isEnabled: $screenAnnotationModel.isEnabled, feature: .screenAnnotation),
            FeatureCardSpec(title: "Video Converter", icon: "film", statusText: "Ready", isEnabled: nil, feature: .videoConverter),
            FeatureCardSpec(title: "PDF Tools", icon: "doc.badge.gearshape", statusText: "Ready", isEnabled: nil, feature: .pdfTools),
            FeatureCardSpec(title: "Quick Launch", icon: "bolt.fill", statusText: "\(quickLaunchModel.customEntries.count) shortcuts", isEnabled: nil, feature: .quickLaunch),
            FeatureCardSpec(title: "Test Data Generator", icon: "wand.and.stars", statusText: "Ready", isEnabled: nil, feature: .testDataGenerator),
            FeatureCardSpec(title: "Speech to Text", icon: "waveform.badge.mic", statusText: speechToTextModel.hubStatusText, isEnabled: nil, feature: .speechToText),
            FeatureCardSpec(title: "Port Manager", icon: "network", statusText: portManagerModel.isEnabled ? "\(portManagerModel.ports.count) ports" : "Off", isEnabled: $portManagerModel.isEnabled, feature: .portManager),
            FeatureCardSpec(title: "System Info", icon: "gauge.with.dots.needle.33percent", statusText: systemInfoModel.isEnabled ? systemInfoModel.hubStatusText : "Off", isEnabled: $systemInfoModel.isEnabled, feature: .systemInfo),
            FeatureCardSpec(title: "Screen Capture", icon: "camera.viewfinder", statusText: screenCaptureModel.isEnabled ? "⌃⌥4 ready" : "Off", isEnabled: $screenCaptureModel.isEnabled, feature: .screenCapture),
            FeatureCardSpec(title: "Image Optimizer", icon: "photo.badge.arrow.down", statusText: imageOptimizerModel.items.isEmpty ? "Ready" : "\(imageOptimizerModel.items.count) images", isEnabled: nil, feature: .imageOptimizer),
            FeatureCardSpec(title: "GitHub Notifier", icon: "bell.badge.circle", statusText: gitHubNotifierModel.hubStatusText, isEnabled: $gitHubNotifierModel.isEnabled, feature: .gitHubNotifier),
        ]
    }

    @ViewBuilder
    private func cardView(_ spec: FeatureCardSpec) -> some View {
        CompactFeatureCard(
            title: spec.title,
            icon: spec.icon,
            statusText: spec.statusText,
            isEnabled: spec.isEnabled,
            action: { withAnimation(.easeInOut(duration: 0.15)) { activeFeature = spec.feature } }
        )
    }

    // MARK: - Feature Hub (main menu)

    private var featureHub: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text("Mac PowerToys")
                    .font(.system(.headline, design: .rounded))
            }

            Divider()

            ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 6) {

            AccessibilityBanner()

            // Color Picker module - full width (has special controls)
            FeatureCardView(title: "Color Picker", action: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    activeFeature = .colorPicker
                }
            }) {
                Button {
                    model.pickFromScreen()
                } label: {
                    Image(systemName: "eyedropper")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(Color.primary.opacity(0.14))
                        )
                        .overlay(
                            Circle()
                                .stroke(Color.primary.opacity(0.18), lineWidth: 0.8)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Pick color from screen")
                .help("Pick from screen")

                SwatchView(
                    nsColor: model.nsColor,
                    swatchHeight: 22,
                    swatchCornerRadius: 5,
                    onSelect: { shade in
                        model.selectFromHistory(shade)
                    }
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    model.copy(model.hexString)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(Color.primary.opacity(0.14))
                        )
                        .overlay(
                            Circle()
                                .stroke(Color.primary.opacity(0.18), lineWidth: 0.8)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy \(model.hexString)")
                .help("Copy \(model.hexString)")

                Circle()
                    .fill(Color(nsColor: model.nsColor))
                    .frame(width: 22, height: 22)
                    .overlay(Circle().stroke(.secondary.opacity(0.4), lineWidth: 0.7))
                    .help(model.hexString)
            }

            // Feature grid — two cards per row, order defined by `featureCards`
            ForEach(Array(stride(from: 0, to: featureCards.count, by: 2)), id: \.self) { rowStart in
                HStack(spacing: 6) {
                    cardView(featureCards[rowStart])
                    if rowStart + 1 < featureCards.count {
                        cardView(featureCards[rowStart + 1])
                    }
                }
            }

            } // VStack inside ScrollView
            } // ScrollView

            Divider()

            // Footer
            HStack {
                LaunchAtLoginToggle()
                Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button {
                    showingQuitAlert = true
                } label: {
                    Label("Quit", systemImage: "power")
                        .labelStyle(.titleAndIcon)
                }
                .keyboardShortcut("q")
                .buttonStyle(.bordered)
                .alert("Quit Mac PowerToys?", isPresented: $showingQuitAlert) {
                    Button("Cancel", role: .cancel) { }
                    Button("Quit", role: .destructive) {
                        NSApplication.shared.terminate(nil)
                    }
                } message: {
                    Text("Are you sure you want to quit?")
                }
            }
        }
    }

    // MARK: - Feature Views

    @ViewBuilder
    private func featureView(for feature: Feature) -> some View {
        switch feature {
        case .colorPicker:
            ColorPickerView(onBack: { goBack() })
        case .mouseUtilitiesHub:
            mouseUtilitiesHubView
        case .findMyMouse:
            FindMyMouseView(onBack: { goBack(to: .mouseUtilitiesHub) })
        case .mouseHighlighter:
            MouseHighlighterView(onBack: { goBack(to: .mouseUtilitiesHub) })
        case .crosshairs:
            CrosshairsView(onBack: { goBack(to: .mouseUtilitiesHub) })
        case .cursorWrap:
            CursorWrapView(onBack: { goBack(to: .mouseUtilitiesHub) })
        case .screenRuler:
            ScreenRulerView(onBack: { goBack() })
        case .zoomIt:
            ZoomItView(onBack: { goBack() })
        case .awake:
            AwakeView(onBack: { goBack() })
        case .mouseJiggler:
            MouseJigglerView(onBack: { goBack() })
        case .clipboardManager:
            ClipboardManagerView(onBack: { goBack() })
        case .markdownPreview:
            MarkdownPreviewView(onBack: { goBack() })
        case .screenAnnotation:
            ScreenAnnotationView(onBack: { goBack() })
        case .videoConverter:
            VideoConverterView(onBack: { goBack() })
        case .pomodoroTimer:
            PomodoroTimerView(onBack: { goBack() })
        case .testDataGenerator:
            TestDataGeneratorView(onBack: { goBack() })
        case .speechToText:
            SpeechToTextView(onBack: { goBack() })
        case .portManager:
            PortManagerView(onBack: { goBack() })
        case .systemInfo:
            SystemInfoView(onBack: { goBack() })
        case .quickLaunch:
            QuickLaunchView(onBack: { goBack() })
        case .pdfTools:
            PdfToolsView(onBack: { goBack() })
        case .screenCapture:
            ScreenCaptureView(onBack: { goBack() })
        case .gitHubNotifier:
            GitHubNotifierView(onBack: { goBack() })
        case .imageOptimizer:
            ImageOptimizerView(onBack: { goBack() })
        }
    }

    private func goBack(to feature: Feature? = nil) {
        withAnimation(.easeInOut(duration: 0.15)) {
            activeFeature = feature
        }
    }

    // MARK: - Mouse Utilities Hub

    private var mouseUtilitiesHubView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Navigation header
            HStack {
                Button { goBack() } label: {
                    Label("Back", systemImage: "chevron.left")
                        .labelStyle(.iconOnly)
                        .frame(minWidth: 24, minHeight: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                .help("Back")

                Text("Mouse Utilities")
                    .font(.system(.headline, design: .rounded))

                Spacer()
            }

            Divider()

            mouseUtilityRow(
                title: "Find My Mouse",
                icon: "cursorarrow.rays",
                description: "Spotlight on cursor",
                shortcut: "Double ⌃",
                isEnabled: $findMyMouseModel.isEnabled,
                feature: .findMyMouse
            )

            mouseUtilityRow(
                title: "Mouse Highlighter",
                icon: "hand.tap",
                description: "Highlight clicks",
                shortcut: "Double Left ⌥",
                isEnabled: $mouseHighlighterModel.isEnabled,
                feature: .mouseHighlighter
            )

            mouseUtilityRow(
                title: "Mouse Crosshairs",
                icon: "plus.circle",
                description: "Crosshair overlay",
                shortcut: "Double Right ⌥",
                isEnabled: $crosshairsModel.isEnabled,
                feature: .crosshairs
            )

            mouseUtilityRow(
                title: "Cursor Wrap",
                icon: "arrow.trianglehead.2.counterclockwise",
                description: "Wrap at edges",
                shortcut: nil,
                isEnabled: $cursorWrapModel.isEnabled,
                feature: .cursorWrap
            )
            
            Spacer()
        }
    }

    private func mouseUtilityRow(
        title: String,
        icon: String,
        description: String,
        shortcut: String?,
        isEnabled: Binding<Bool>,
        feature: Feature
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.primary.opacity(0.14))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Color.primary.opacity(0.18), lineWidth: 0.8)
                )

            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    activeFeature = feature
                }
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.medium)
                    HStack(spacing: 4) {
                        Text(description)
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.secondary)
                        if let shortcut {
                            Text("·")
                                .font(.system(.caption2, design: .rounded))
                                .foregroundStyle(.secondary)
                            Text(shortcut)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            Toggle("Enable \(title)", isOn: isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.mini)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helper

    private var mouseUtilitiesStatusText: String {
        let count = [
            findMyMouseModel.isEnabled,
            mouseHighlighterModel.isEnabled,
            crosshairsModel.isEnabled,
            cursorWrapModel.isEnabled
        ].filter { $0 }.count

        if count == 0 { return "All off" }
        return "\(count) of 4 enabled"
    }

    private var pomodoroTimerStatusText: String {
        guard pomodoroTimerModel.isEnabled else { return "Off" }
        switch pomodoroTimerModel.currentPhase {
        case .idle: return "Ready"
        case .focus: return "Focus \(pomodoroTimerModel.formattedRemaining)"
        case .shortBreak: return "Break \(pomodoroTimerModel.formattedRemaining)"
        case .longBreak: return "Break \(pomodoroTimerModel.formattedRemaining)"
        }
    }
}

// MARK: - Accessibility Banner

private struct AccessibilityBanner: View {
    @State private var isTrusted = AXIsProcessTrusted()
    @State private var timer: Timer?

    var body: some View {
        Group {
            if !isTrusted {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.shield")
                        .foregroundStyle(.orange)
                    Text("Global shortcuts need Accessibility permission")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("Grant…") {
                        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
                        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .controlSize(.small)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
            }
        }
        .onAppear {
            isTrusted = AXIsProcessTrusted()
            startTimerIfNeeded()
        }
        .onDisappear { stopTimer() }
    }

    private func startTimerIfNeeded() {
        stopTimer()
        guard !isTrusted else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            Task { @MainActor in
                isTrusted = AXIsProcessTrusted()
                if isTrusted { stopTimer() }
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - Launch at Login

private struct LaunchAtLoginToggle: View {
    @State private var isOn = false

    var body: some View {
        Toggle("Launch at Login", isOn: Binding(
            get: { isOn },
            set: { newValue in
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                    isOn = newValue
                } catch {
                    NSLog("[App] Launch at login failed: %@", error.localizedDescription)
                    isOn = SMAppService.mainApp.status == .enabled
                }
            }
        ))
        .toggleStyle(.switch)
        .controlSize(.mini)
        .font(.system(.caption, design: .rounded))
        .onAppear { isOn = SMAppService.mainApp.status == .enabled }
    }
}
