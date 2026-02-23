import SwiftUI

@main
struct MacPowertoysApp: App {
    @StateObject private var model = ColorModel()

    init() {
        // Hide color panel at app startup
        DispatchQueue.main.async {
            NSColorPanel.shared.orderOut(nil)
        }
    }

    var body: some Scene {
        MenuBarExtra("Mac Powertoys", systemImage: "wrench.and.screwdriver") {
            ContentView()
                .environmentObject(model)
                .frame(width: 340)
                .padding(.vertical, 8)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    model.closeColorPanel()
                }
        }
        .menuBarExtraStyle(.window)
    }
}
