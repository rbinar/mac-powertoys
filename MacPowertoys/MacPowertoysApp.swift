import SwiftUI

@main
struct MacPowerToysApp: App {
    @StateObject private var model = ColorModel()
    @StateObject private var findMyMouseModel = FindMyMouseModel()
    @StateObject private var mouseHighlighterModel = MouseHighlighterModel()
    @StateObject private var crosshairsModel = CrosshairsModel()
    @StateObject private var cursorWrapModel = CursorWrapModel()
    @StateObject private var screenRulerModel = ScreenRulerModel()
    @StateObject private var zoomItModel = ZoomItModel()
    @StateObject private var webhookNotifierModel = WebhookNotifierModel()
    @StateObject private var awakeModel = AwakeModel()
    @StateObject private var mouseJigglerModel = MouseJigglerModel()
    @StateObject private var clipboardManagerModel = ClipboardManagerModel()
    @StateObject private var markdownPreviewModel = MarkdownPreviewModel()
    @StateObject private var screenAnnotationModel = ScreenAnnotationModel()
    @StateObject private var videoConverterModel = VideoConverterModel()
    @StateObject private var pomodoroTimerModel = PomodoroTimerModel()
    @StateObject private var testDataGeneratorModel = TestDataGeneratorModel()

    init() {
        // Hide color panel at app startup
        DispatchQueue.main.async {
            NSColorPanel.shared.orderOut(nil)
        }

        // Request Accessibility permissions for global shortcuts (only prompt if not already granted)
        if !AXIsProcessTrusted() {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        }
    }

    var body: some Scene {
        MenuBarExtra("Mac PowerToys", systemImage: "wrench.and.screwdriver") {
            ContentView()
                .environmentObject(model)
                .environmentObject(findMyMouseModel)
                .environmentObject(mouseHighlighterModel)
                .environmentObject(crosshairsModel)
                .environmentObject(cursorWrapModel)
                .environmentObject(screenRulerModel)
                .environmentObject(zoomItModel)
                .environmentObject(webhookNotifierModel)
                .environmentObject(awakeModel)
                .environmentObject(mouseJigglerModel)
                .environmentObject(clipboardManagerModel)
                .environmentObject(markdownPreviewModel)
                .environmentObject(screenAnnotationModel)
                .environmentObject(videoConverterModel)
                .environmentObject(pomodoroTimerModel)
                .environmentObject(testDataGeneratorModel)
                .frame(width: 340, height: 560)
                .padding(.vertical, 8)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    model.closeColorPanel()
                    findMyMouseModel.stopMonitoring()
                    mouseHighlighterModel.stopMonitoring()
                    crosshairsModel.stopMonitoring()
                    cursorWrapModel.stopMonitoring()
                    screenRulerModel.stopMonitoring()
                    zoomItModel.stopMonitoring()
                    webhookNotifierModel.stopMonitoring()
                    awakeModel.stopMonitoring()
                    mouseJigglerModel.stopMonitoring()
                    clipboardManagerModel.stopMonitoring()
                    markdownPreviewModel.stopMonitoring()
                    screenAnnotationModel.stopMonitoring()
                    videoConverterModel.stopMonitoring()
                    pomodoroTimerModel.stopMonitoring()
                }
        }
        .menuBarExtraStyle(.window)
    }
}
