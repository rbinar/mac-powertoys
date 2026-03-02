import SwiftUI
import AppKit

enum Feature: Hashable {
    case colorPicker
    case mouseUtilitiesHub
    case findMyMouse
    case mouseHighlighter
    case crosshairs
    case cursorWrap
    case screenRuler
    case zoomIt
    case webhookNotifier
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
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(.white.opacity(0.14))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(.white.opacity(0.18), lineWidth: 0.8)
                    )
                Spacer()
                if let binding = isEnabled {
                    Toggle("", isOn: binding)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .controlSize(.mini)
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
        .onTapGesture {
            action()
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isHovered ? AnyShapeStyle(.quaternary.opacity(0.85)) : AnyShapeStyle(.quaternary.opacity(0.45)))
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var model: ColorModel
    @EnvironmentObject var findMyMouseModel: FindMyMouseModel
    @EnvironmentObject var mouseHighlighterModel: MouseHighlighterModel
    @EnvironmentObject var crosshairsModel: CrosshairsModel
    @EnvironmentObject var cursorWrapModel: CursorWrapModel
    @EnvironmentObject var screenRulerModel: ScreenRulerModel
    @EnvironmentObject var zoomItModel: ZoomItModel
    @EnvironmentObject var webhookNotifierModel: WebhookNotifierModel
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

            ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 6) {

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
                                .fill(.white.opacity(0.14))
                        )
                        .overlay(
                            Circle()
                                .stroke(.white.opacity(0.18), lineWidth: 0.8)
                        )
                }
                .buttonStyle(.plain)
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
                                .fill(.white.opacity(0.14))
                        )
                        .overlay(
                            Circle()
                                .stroke(.white.opacity(0.18), lineWidth: 0.8)
                        )
                }
                .buttonStyle(.plain)
                .help("Copy \(model.hexString)")

                Circle()
                    .fill(Color(nsColor: model.nsColor))
                    .frame(width: 22, height: 22)
                    .overlay(Circle().stroke(.secondary.opacity(0.4), lineWidth: 0.7))
                    .help(model.hexString)
            }

            // Row 1: Screen Ruler | ZoomIt
            HStack(spacing: 6) {
                CompactFeatureCard(
                    title: "Screen Ruler",
                    icon: "ruler",
                    statusText: screenRulerModel.isEnabled ? "Active" : "Disabled",
                    isEnabled: $screenRulerModel.isEnabled,
                    action: { withAnimation(.easeInOut(duration: 0.15)) { activeFeature = .screenRuler } }
                )
                CompactFeatureCard(
                    title: "ZoomIt",
                    icon: "magnifyingglass",
                    statusText: zoomItModel.isEnabled ? "Active" : "Disabled",
                    isEnabled: $zoomItModel.isEnabled,
                    action: { withAnimation(.easeInOut(duration: 0.15)) { activeFeature = .zoomIt } }
                )
            }

            // Row 2: Mouse Utilities | Mouse Jiggler
            HStack(spacing: 6) {
                CompactFeatureCard(
                    title: "Mouse Utilities",
                    icon: "cursorarrow",
                    statusText: mouseUtilitiesStatusText,
                    isEnabled: nil,
                    action: { withAnimation(.easeInOut(duration: 0.15)) { activeFeature = .mouseUtilitiesHub } }
                )
                CompactFeatureCard(
                    title: "Mouse Jiggler",
                    icon: "computermouse.fill",
                    statusText: mouseJigglerModel.isEnabled ? "Active" : "Disabled",
                    isEnabled: $mouseJigglerModel.isEnabled,
                    action: { withAnimation(.easeInOut(duration: 0.15)) { activeFeature = .mouseJiggler } }
                )
            }

            // Row 3: Awake | Pomodoro Timer
            HStack(spacing: 6) {
                CompactFeatureCard(
                    title: "Awake",
                    icon: "cup.and.saucer.fill",
                    statusText: awakeModel.isEnabled ? (awakeModel.isIndefinite ? "Indefinite" : awakeModel.formattedRemaining) : "Disabled",
                    isEnabled: $awakeModel.isEnabled,
                    action: { withAnimation(.easeInOut(duration: 0.15)) { activeFeature = .awake } }
                )
                CompactFeatureCard(
                    title: "Pomodoro Timer",
                    icon: "timer",
                    statusText: pomodoroTimerStatusText,
                    isEnabled: $pomodoroTimerModel.isEnabled,
                    action: { withAnimation(.easeInOut(duration: 0.15)) { activeFeature = .pomodoroTimer } }
                )
            }

            // Row 4: Clipboard Manager | Markdown Preview
            HStack(spacing: 6) {
                CompactFeatureCard(
                    title: "Clipboard Manager",
                    icon: "list.clipboard",
                    statusText: clipboardManagerModel.isEnabled ? "\(clipboardManagerModel.clipboardItems.count) items" : "Disabled",
                    isEnabled: $clipboardManagerModel.isEnabled,
                    action: { withAnimation(.easeInOut(duration: 0.15)) { activeFeature = .clipboardManager } }
                )
                CompactFeatureCard(
                    title: "Markdown Preview",
                    icon: "doc.richtext",
                    statusText: "\(markdownPreviewModel.recentFiles.count) recent",
                    isEnabled: nil,
                    action: { withAnimation(.easeInOut(duration: 0.15)) { activeFeature = .markdownPreview } }
                )
            }

            // Row 5: Screen Annotation | Video Converter
            HStack(spacing: 6) {
                CompactFeatureCard(
                    title: "Screen Annotation",
                    icon: "pencil.tip.crop.circle",
                    statusText: screenAnnotationModel.isEnabled ? "Active" : "Disabled",
                    isEnabled: $screenAnnotationModel.isEnabled,
                    action: { withAnimation(.easeInOut(duration: 0.15)) { activeFeature = .screenAnnotation } }
                )
                CompactFeatureCard(
                    title: "Video Converter",
                    icon: "film",
                    statusText: "Ready",
                    isEnabled: nil,
                    action: { withAnimation(.easeInOut(duration: 0.15)) { activeFeature = .videoConverter } }
                )
            }
            
            // Row 6: PDF Tools | Quick Launch
            HStack(spacing: 6) {
                CompactFeatureCard(
                    title: "PDF Tools",
                    icon: "doc.badge.gearshape",
                    statusText: "Ready",
                    isEnabled: nil,
                    action: { withAnimation(.easeInOut(duration: 0.15)) { activeFeature = .pdfTools } }
                )
                CompactFeatureCard(
                    title: "Quick Launch",
                    icon: "bolt.fill",
                    statusText: "\(quickLaunchModel.customEntries.count) shortcuts",
                    isEnabled: nil,
                    action: { withAnimation(.easeInOut(duration: 0.15)) { activeFeature = .quickLaunch } }
                )
            }

            // Row 7: Test Data Generator | Speech to Text
            HStack(spacing: 6) {
                CompactFeatureCard(
                    title: "Test Data Generator",
                    icon: "wand.and.stars",
                    statusText: "Ready",
                    isEnabled: nil,
                    action: { withAnimation(.easeInOut(duration: 0.15)) { activeFeature = .testDataGenerator } }
                )
                CompactFeatureCard(
                    title: "Speech to Text",
                    icon: "waveform.badge.mic",
                    statusText: speechToTextModel.hubStatusText,
                    isEnabled: nil,
                    action: { withAnimation(.easeInOut(duration: 0.15)) { activeFeature = .speechToText } }
                )
            }
            
            // Row 8: Port Manager | System Info
            HStack(spacing: 6) {
                CompactFeatureCard(
                    title: "Port Manager",
                    icon: "network",
                    statusText: portManagerModel.isEnabled ? "\(portManagerModel.ports.count) ports" : "Disabled",
                    isEnabled: $portManagerModel.isEnabled,
                    action: { withAnimation(.easeInOut(duration: 0.15)) { activeFeature = .portManager } }
                )
                CompactFeatureCard(
                    title: "System Info",
                    icon: "gauge.with.dots.needle.33percent",
                    statusText: systemInfoModel.isEnabled ? systemInfoModel.hubStatusText : "Disabled",
                    isEnabled: $systemInfoModel.isEnabled,
                    action: { withAnimation(.easeInOut(duration: 0.15)) { activeFeature = .systemInfo } }
                )
            }

            // Webhook Notifier - full width
            FeatureCardView(title: "Webhook Notifier", action: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    activeFeature = .webhookNotifier
                }
            }) {
                Image(systemName: "bell.badge")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(.white.opacity(0.14))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(.white.opacity(0.18), lineWidth: 0.8)
                    )

                let activeCount = webhookNotifierModel.topics.filter { $0.isActive }.count
                Text(webhookNotifierModel.isEnabled ? "\(activeCount) active webhooks" : "Disabled")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                Toggle("", isOn: $webhookNotifierModel.isEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.mini)
            }

            } // VStack inside ScrollView
            } // ScrollView

            Divider()

            // Footer
            HStack {
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
                .environmentObject(model)
        case .mouseUtilitiesHub:
            mouseUtilitiesHubView
        case .findMyMouse:
            FindMyMouseView(onBack: { goBack(to: .mouseUtilitiesHub) })
                .environmentObject(findMyMouseModel)
        case .mouseHighlighter:
            MouseHighlighterView(onBack: { goBack(to: .mouseUtilitiesHub) })
                .environmentObject(mouseHighlighterModel)
        case .crosshairs:
            CrosshairsView(onBack: { goBack(to: .mouseUtilitiesHub) })
                .environmentObject(crosshairsModel)
        case .cursorWrap:
            CursorWrapView(onBack: { goBack(to: .mouseUtilitiesHub) })
                .environmentObject(cursorWrapModel)
        case .screenRuler:
            ScreenRulerView(onBack: { goBack() })
                .environmentObject(screenRulerModel)
        case .zoomIt:
            ZoomItView(onBack: { goBack() })
                .environmentObject(zoomItModel)
        case .webhookNotifier:
            WebhookNotifierView(onBack: { goBack() })
                .environmentObject(webhookNotifierModel)
        case .awake:
            AwakeView(onBack: { goBack() })
                .environmentObject(awakeModel)
        case .mouseJiggler:
            MouseJigglerView(onBack: { goBack() })
                .environmentObject(mouseJigglerModel)
        case .clipboardManager:
            ClipboardManagerView(onBack: { goBack() })
                .environmentObject(clipboardManagerModel)
        case .markdownPreview:
            MarkdownPreviewView(onBack: { goBack() })
                .environmentObject(markdownPreviewModel)
        case .screenAnnotation:
            ScreenAnnotationView(onBack: { goBack() })
                .environmentObject(screenAnnotationModel)
        case .videoConverter:
            VideoConverterView(onBack: { goBack() })
                .environmentObject(videoConverterModel)
        case .pomodoroTimer:
            PomodoroTimerView(onBack: { goBack() })
                .environmentObject(pomodoroTimerModel)
        case .testDataGenerator:
            TestDataGeneratorView(onBack: { goBack() })
        case .speechToText:
            SpeechToTextView(onBack: { goBack() })
                .environmentObject(speechToTextModel)
        case .portManager:
            PortManagerView(onBack: { goBack() })
                .environmentObject(portManagerModel)
        case .systemInfo:
            SystemInfoView(onBack: { goBack() })
                .environmentObject(systemInfoModel)
        case .quickLaunch:
            QuickLaunchView(onBack: { goBack() })
                .environmentObject(quickLaunchModel)
        case .pdfTools:
            PdfToolsView(onBack: { goBack() })
                .environmentObject(pdfToolsModel)
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
                }
                .buttonStyle(.plain)

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
                        .fill(.white.opacity(0.14))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(.white.opacity(0.18), lineWidth: 0.8)
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
                            .foregroundStyle(.tertiary)
                        if let shortcut {
                            Text("·")
                                .font(.system(.caption2, design: .rounded))
                                .foregroundStyle(.quaternary)
                            Text(shortcut)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.quaternary)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            Toggle("", isOn: isEnabled)
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

        if count == 0 { return "All disabled" }
        return "\(count) of 4 enabled"
    }

    private var pomodoroTimerStatusText: String {
        guard pomodoroTimerModel.isEnabled else { return "Disabled" }
        switch pomodoroTimerModel.currentPhase {
        case .idle: return "Ready"
        case .focus: return "Focus \(pomodoroTimerModel.formattedRemaining)"
        case .shortBreak: return "Break \(pomodoroTimerModel.formattedRemaining)"
        case .longBreak: return "Break \(pomodoroTimerModel.formattedRemaining)"
        }
    }
}
