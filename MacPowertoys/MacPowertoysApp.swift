import SwiftUI

@main
struct MacPowerToysApp: App {
    private let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    init() {
        guard !isRunningTests else { return }

        // Hide color panel at app startup
        DispatchQueue.main.async {
            NSColorPanel.shared.orderOut(nil)
        }
    }

    var body: some Scene {
        MenuBarExtra("Mac PowerToys", systemImage: "wrench.and.screwdriver") {
            if isRunningTests {
                EmptyView()
            } else {
                AppRootView()
            }
        }
        .menuBarExtraStyle(.window)
    }
}

private struct AppRootView: View {
    @StateObject private var model = ColorModel()
    @StateObject private var findMyMouseModel = FindMyMouseModel()
    @StateObject private var mouseHighlighterModel = MouseHighlighterModel()
    @StateObject private var crosshairsModel = CrosshairsModel()
    @StateObject private var cursorWrapModel = CursorWrapModel()
    @StateObject private var screenRulerModel = ScreenRulerModel()
    @StateObject private var zoomItModel = ZoomItModel()
    @StateObject private var awakeModel = AwakeModel()
    @StateObject private var mouseJigglerModel = MouseJigglerModel()
    @StateObject private var clipboardManagerModel = ClipboardManagerModel()
    @StateObject private var markdownPreviewModel = MarkdownPreviewModel()
    @StateObject private var screenAnnotationModel = ScreenAnnotationModel()
    @StateObject private var speechToTextModel = SpeechToTextModel()
    @StateObject private var videoConverterModel = VideoConverterModel()
    @StateObject private var pomodoroTimerModel = PomodoroTimerModel()
    @StateObject private var testDataGeneratorModel = TestDataGeneratorModel()
    @StateObject private var portManagerModel = PortManagerModel()
    @StateObject private var systemInfoModel = SystemInfoModel()
    @StateObject private var quickLaunchModel = QuickLaunchModel()
    @StateObject private var pdfToolsModel = PdfToolsModel()
    @StateObject private var screenCaptureModel = ScreenCaptureModel()
    @StateObject private var gitHubNotifierModel = GitHubNotifierModel()
    @StateObject private var imageOptimizerModel = ImageOptimizerModel()

    var body: some View {
        let _ = installPaletteCommandsIfNeeded()
        ContentView()
            .environmentObject(model)
            .environmentObject(findMyMouseModel)
            .environmentObject(mouseHighlighterModel)
            .environmentObject(crosshairsModel)
            .environmentObject(cursorWrapModel)
            .environmentObject(screenRulerModel)
            .environmentObject(zoomItModel)
            .environmentObject(awakeModel)
            .environmentObject(mouseJigglerModel)
            .environmentObject(clipboardManagerModel)
            .environmentObject(markdownPreviewModel)
            .environmentObject(screenAnnotationModel)
            .environmentObject(speechToTextModel)
            .environmentObject(videoConverterModel)
            .environmentObject(pomodoroTimerModel)
            .environmentObject(testDataGeneratorModel)
            .environmentObject(portManagerModel)
            .environmentObject(systemInfoModel)
            .environmentObject(quickLaunchModel)
            .environmentObject(pdfToolsModel)
            .environmentObject(screenCaptureModel)
            .environmentObject(gitHubNotifierModel)
            .environmentObject(imageOptimizerModel)
            .frame(width: 340, height: 640)
            .padding(.vertical, 8)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                model.closeColorPanel()
                model.stopMonitoring()
                findMyMouseModel.stopMonitoring()
                mouseHighlighterModel.stopMonitoring()
                crosshairsModel.stopMonitoring()
                cursorWrapModel.stopMonitoring()
                screenRulerModel.stopMonitoring()
                zoomItModel.stopMonitoring()
                awakeModel.stopMonitoring()
                mouseJigglerModel.stopMonitoring()
                clipboardManagerModel.stopMonitoring()
                markdownPreviewModel.stopMonitoring()
                screenAnnotationModel.stopMonitoring()
                speechToTextModel.stopMonitoring()
                videoConverterModel.stopMonitoring()
                pomodoroTimerModel.stopMonitoring()
                portManagerModel.stopMonitoring()
                systemInfoModel.stopMonitoring()
                quickLaunchModel.stopMonitoring()
                pdfToolsModel.stopMonitoring()
                screenCaptureModel.stopMonitoring()
                gitHubNotifierModel.stopMonitoring()
                imageOptimizerModel.stopMonitoring()
                testDataGeneratorModel.stopMonitoring()
            }
    }

    // MARK: - Command palette wiring

    /// Called from `body`; assigns the palette commands once, outside the view update.
    private func installPaletteCommandsIfNeeded() {
        guard quickLaunchModel.commands.isEmpty else { return }
        DispatchQueue.main.async {
            guard quickLaunchModel.commands.isEmpty else { return }
            quickLaunchModel.commands = makePaletteCommands()
        }
    }

    private func paletteScreen<V: View>(_ view: V) -> AnyView {
        AnyView(
            view
                .environmentObject(model)
                .environmentObject(findMyMouseModel)
                .environmentObject(mouseHighlighterModel)
                .environmentObject(crosshairsModel)
                .environmentObject(cursorWrapModel)
                .environmentObject(screenRulerModel)
                .environmentObject(zoomItModel)
                .environmentObject(awakeModel)
                .environmentObject(mouseJigglerModel)
                .environmentObject(clipboardManagerModel)
                .environmentObject(markdownPreviewModel)
                .environmentObject(screenAnnotationModel)
                .environmentObject(speechToTextModel)
                .environmentObject(videoConverterModel)
                .environmentObject(pomodoroTimerModel)
                .environmentObject(testDataGeneratorModel)
                .environmentObject(portManagerModel)
                .environmentObject(systemInfoModel)
                .environmentObject(quickLaunchModel)
                .environmentObject(pdfToolsModel)
                .environmentObject(screenCaptureModel)
                .environmentObject(gitHubNotifierModel)
                .environmentObject(imageOptimizerModel)
        )
    }

    private func makePaletteCommands() -> [PaletteCommand] {
        let color = model
        let ruler = screenRulerModel
        let zoom = zoomItModel
        let annotation = screenAnnotationModel
        let capture = screenCaptureModel
        let findMouse = findMyMouseModel
        let awake = awakeModel
        let jiggler = mouseJigglerModel
        let crosshairs = crosshairsModel
        let highlighter = mouseHighlighterModel
        let cursorWrap = cursorWrapModel
        let pomodoro = pomodoroTimerModel
        let quickLaunch = quickLaunchModel
        let back: () -> Void = { quickLaunch.closeScreen() }

        return [
            // Screen Tools
            PaletteCommand(id: "screenRuler.start", title: "Screen Ruler", subtitle: "Start measuring", symbol: "ruler", group: .screenTools, shortcut: "⌃⌥R", keywords: ["measure", "pixels"], run: { ruler.startSession() }, screen: { paletteScreen(ScreenRulerView(onBack: back)) }),
            PaletteCommand(id: "zoomIt.screenZoom", title: "Screen Zoom", subtitle: "Freeze and magnify the screen", symbol: "plus.magnifyingglass", group: .screenTools, shortcut: "⌃⌥Z", keywords: ["zoomit", "magnify"], run: { zoom.activateScreenZoom() }, screen: { paletteScreen(ZoomItView(onBack: back)) }),
            PaletteCommand(id: "zoomIt.liveZoom", title: "Live Zoom", subtitle: "Magnify in real time", symbol: "video", group: .screenTools, shortcut: "⌃⌥L", keywords: ["zoomit", "magnify"], run: { zoom.activateLiveZoom() }, screen: { paletteScreen(ZoomItView(onBack: back)) }),
            PaletteCommand(id: "screenAnnotation.start", title: "Screen Annotation", subtitle: "Draw on screen", symbol: "pencil.tip.crop.circle", group: .screenTools, shortcut: "⌃⌥D", keywords: ["draw", "markup"], run: { annotation.startSession() }, screen: { paletteScreen(ScreenAnnotationView(onBack: back)) }),
            PaletteCommand(id: "screenCapture.start", title: "Screen Capture", subtitle: "Select an area, copy to clipboard", symbol: "camera.viewfinder", group: .screenTools, shortcut: "⌃⌥4", keywords: ["screenshot"], run: { capture.startCapture() }, screen: { paletteScreen(ScreenCaptureView(onBack: back)) }),
            PaletteCommand(id: "colorPicker.pick", title: "Color Picker", subtitle: "Pick a color from the screen", symbol: "eyedropper", group: .screenTools, shortcut: "⌃⌥C", keywords: ["eyedropper", "hex"], run: { color.pickFromScreen() }, screen: { paletteScreen(ColorPickerView(onBack: back)) }),
            PaletteCommand(id: "findMyMouse.spotlight", title: "Find My Mouse", subtitle: "Show the cursor spotlight", symbol: "cursorarrow.rays", group: .screenTools, keywords: ["cursor", "pointer"], run: { findMouse.activateSpotlight() }, screen: { paletteScreen(FindMyMouseView(onBack: back)) }),

            // Modes
            PaletteCommand(id: "awake.toggle", title: "Awake", subtitle: "Keep the Mac awake", symbol: "cup.and.saucer.fill", group: .modes, keywords: ["sleep", "caffeinate"], isOn: { awake.isEnabled }, run: { awake.isEnabled.toggle() }, screen: { paletteScreen(AwakeView(onBack: back)) }),
            PaletteCommand(id: "mouseJiggler.toggle", title: "Mouse Jiggler", subtitle: "Stay active", symbol: "computermouse.fill", group: .modes, keywords: ["idle"], isOn: { jiggler.isEnabled }, run: { jiggler.isEnabled.toggle() }, screen: { paletteScreen(MouseJigglerView(onBack: back)) }),
            PaletteCommand(id: "crosshairs.toggle", title: "Mouse Crosshairs", subtitle: "Crosshair overlay", symbol: "plus.circle", group: .modes, isOn: { crosshairs.isEnabled }, run: { crosshairs.isEnabled.toggle() }, screen: { paletteScreen(CrosshairsView(onBack: back)) }),
            PaletteCommand(id: "mouseHighlighter.toggle", title: "Mouse Highlighter", subtitle: "Highlight clicks", symbol: "hand.tap", group: .modes, isOn: { highlighter.isEnabled }, run: { highlighter.isEnabled.toggle() }, screen: { paletteScreen(MouseHighlighterView(onBack: back)) }),
            PaletteCommand(id: "cursorWrap.toggle", title: "Cursor Wrap", subtitle: "Wrap at screen edges", symbol: "arrow.trianglehead.2.counterclockwise", group: .modes, isOn: { cursorWrap.isEnabled }, run: { cursorWrap.isEnabled.toggle() }, screen: { paletteScreen(CursorWrapView(onBack: back)) }),
            PaletteCommand(id: "pomodoro.toggle", title: "Pomodoro", subtitle: "Start a focus session", symbol: "timer", group: .modes, keywords: ["focus", "timer"], isOn: { pomodoro.isEnabled }, run: { pomodoro.isEnabled.toggle() }, screen: { paletteScreen(PomodoroTimerView(onBack: back)) }),

            // Tools
            PaletteCommand(id: "clipboardManager.open", title: "Clipboard Manager", subtitle: "Clipboard history", symbol: "list.clipboard", group: .tools, shortcut: "⌃⌥V", keywords: ["paste", "history"], screen: { paletteScreen(ClipboardManagerView(onBack: back)) }),
            PaletteCommand(id: "pdfTools.open", title: "PDF Tools", subtitle: "Merge, split and convert PDFs", symbol: "doc.badge.gearshape", group: .tools, screen: { paletteScreen(PdfToolsView(onBack: back)) }),
            PaletteCommand(id: "imageOptimizer.open", title: "Image Optimizer", subtitle: "Compress and resize images", symbol: "photo.badge.arrow.down", group: .tools, keywords: ["compress"], screen: { paletteScreen(ImageOptimizerView(onBack: back)) }),
            PaletteCommand(id: "videoConverter.open", title: "Video Converter", subtitle: "Convert video files", symbol: "film", group: .tools, keywords: ["ffmpeg"], screen: { paletteScreen(VideoConverterView(onBack: back)) }),
            PaletteCommand(id: "markdownPreview.open", title: "Markdown Preview", subtitle: "Preview markdown files", symbol: "doc.richtext", group: .tools, screen: { paletteScreen(MarkdownPreviewView(onBack: back)) }),
            PaletteCommand(id: "speechToText.open", title: "Speech to Text", subtitle: "Transcribe audio", symbol: "waveform.badge.mic", group: .tools, keywords: ["whisper", "transcribe"], screen: { paletteScreen(SpeechToTextView(onBack: back)) }),
            PaletteCommand(id: "portManager.open", title: "Port Manager", subtitle: "Listening ports and processes", symbol: "network", group: .tools, screen: { paletteScreen(PortManagerView(onBack: back)) }),
            PaletteCommand(id: "systemInfo.open", title: "System Info", subtitle: "CPU, memory and disk", symbol: "gauge.with.dots.needle.33percent", group: .tools, screen: { paletteScreen(SystemInfoView(onBack: back)) }),
            PaletteCommand(id: "testDataGenerator.open", title: "Test Data Generator", subtitle: "Generate fake data", symbol: "wand.and.stars", group: .tools, keywords: ["fake", "mock"], screen: { paletteScreen(TestDataGeneratorView(onBack: back)) }),
            PaletteCommand(id: "gitHubNotifier.open", title: "GitHub Notifier", subtitle: "Pull requests and notifications", symbol: "bell.badge.circle", group: .tools, keywords: ["pr", "notifications"], screen: { paletteScreen(GitHubNotifierView(onBack: back)) }),
        ]
    }
}
