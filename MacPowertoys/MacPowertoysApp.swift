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
    @StateObject private var registry = ModuleRegistry(catalog: ModuleCatalog.all)

    var body: some View {
        registry.inject(into: AnyView(ContentView()))
            .frame(width: 340, height: 640)
            .padding(.vertical, 8)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                registry.stopAll()
            }
    }
}
