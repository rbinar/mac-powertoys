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

        // Create every module at launch. MenuBarExtra builds its content lazily (on the first
        // click), so owning the registry in AppRootView left all global hotkeys dead until then.
        let registry = AppModules.registry
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { registry.stopAll() }
        }
    }

    var body: some Scene {
        MenuBarExtra("Mac PowerToys", systemImage: "wrench.and.screwdriver") {
            if isRunningTests {
                EmptyView()
            } else {
                AppRootView(registry: AppModules.registry)
            }
        }
        .menuBarExtraStyle(.window)
    }
}

/// The app-wide module registry, created once at launch (never in unit tests).
@MainActor
private enum AppModules {
    static let registry = ModuleRegistry(catalog: ModuleCatalog.all)
}

private struct AppRootView: View {
    let registry: ModuleRegistry

    var body: some View {
        ContentView()
            .environmentObject(registry)
            .frame(width: 340, height: 640)
            .padding(.vertical, 8)
    }
}
