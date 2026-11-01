import Foundation

/// The single registration list. Order = palette order. A new module is one line here.
enum ModuleCatalog {
    @MainActor static let all: [AnyModule] = [
        ScreenRulerModule.module,
        ZoomItModule.module,
        ScreenAnnotationModule.module,
        ScreenCaptureModule.module,
        ColorPickerModule.module,
        FindMyMouseModule.module,
        AwakeModule.module,
        MouseJigglerModule.module,
        CrosshairsModule.module,
        MouseHighlighterModule.module,
        CursorWrapModule.module,
        PomodoroTimerModule.module,
        ClipboardManagerModule.module,
        PdfToolsModule.module,
        ImageOptimizerModule.module,
        VideoConverterModule.module,
        MarkdownPreviewModule.module,
        SpeechToTextModule.module,
        PortManagerModule.module,
        SystemInfoModule.module,
        TestDataGeneratorModule.module,
        GitHubNotifierModule.module,
        QuickLaunchModule.module,
    ]
}
