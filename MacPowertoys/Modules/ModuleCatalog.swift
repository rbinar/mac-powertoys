import Foundation

/// The single registration list. Order = hub order. A new module is one line here.
enum ModuleCatalog {
    @MainActor static let all: [AnyModule] = [
        ColorPickerModule.module,
        ScreenRulerModule.module,
        ZoomItModule.module,
        FindMyMouseModule.module,
        MouseHighlighterModule.module,
        CrosshairsModule.module,
        CursorWrapModule.module,
        MouseJigglerModule.module,
        AwakeModule.module,
        PomodoroTimerModule.module,
        ClipboardManagerModule.module,
        MarkdownPreviewModule.module,
        ScreenAnnotationModule.module,
        VideoConverterModule.module,
        PdfToolsModule.module,
        QuickLaunchModule.module,
        TestDataGeneratorModule.module,
        SpeechToTextModule.module,
        PortManagerModule.module,
        SystemInfoModule.module,
        ScreenCaptureModule.module,
        ImageOptimizerModule.module,
        GitHubNotifierModule.module,
        TextExtractorModule.module,
    ]

    /// Palette order shipped in 2.2.0, kept stable. Modules missing here follow in catalog order.
    static let paletteOrder = [
        "screenRuler", "zoomIt", "screenAnnotation", "screenCapture", "colorPicker", "findMyMouse", "awake",
        "mouseJiggler", "crosshairs", "mouseHighlighter", "cursorWrap", "pomodoroTimer", "clipboardManager",
        "pdfTools", "imageOptimizer", "videoConverter", "markdownPreview", "speechToText", "portManager",
        "systemInfo", "testDataGenerator", "gitHubNotifier", "quickLaunch",
    ]
}
