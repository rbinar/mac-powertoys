import Foundation
import AppKit

enum ActivationMethod: String, CaseIterable, Identifiable {
    case doubleLeftCtrl = "Double Left ⌃"
    case doubleRightCtrl = "Double Right ⌃"

    var id: String { rawValue }
}

@MainActor
final class FindMyMouseModel: ObservableObject {
    // MARK: - Settings
    @Published var isEnabled: Bool = false {
        didSet {
            if isEnabled {
                activateSpotlight()
            } else {
                dismissSpotlight()
            }
        }
    }
    @Published var activationMethod: ActivationMethod = .doubleLeftCtrl
    @Published var overlayOpacity: Double = 0.5
    @Published var backgroundColor: NSColor = .black
    @Published var spotlightRadius: CGFloat = 100
    @Published var animationDurationMs: Double = 500

    // MARK: - Runtime State
    @Published private(set) var isSpotlightActive: Bool = false

    // MARK: - Private
    private var globalFlagMonitor: Any?
    private var localFlagMonitor: Any?
    private var lastCtrlPressTime: Date?
    private var overlayWindows: [FindMyMouseOverlayWindow] = []
    private var cursorTrackingTimer: Timer?
    private let doublePressInterval: TimeInterval = 0.4

    init() {
        startMonitoring()
    }

    // MARK: - Monitoring (always-on double-Ctrl listener)

    func startMonitoring() {
        stopMonitoring()

        globalFlagMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.handleFlagsChanged(event)
            }
        }

        localFlagMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.handleFlagsChanged(event)
            }
            return event
        }
    }

    func stopMonitoring() {
        if let m = globalFlagMonitor { NSEvent.removeMonitor(m); globalFlagMonitor = nil }
        if let m = localFlagMonitor { NSEvent.removeMonitor(m); localFlagMonitor = nil }
        if isEnabled {
            isEnabled = false
        }
    }

    // MARK: - Ctrl Detection

    private func handleFlagsChanged(_ event: NSEvent) {
        let isCtrlDown: Bool
        switch activationMethod {
        case .doubleLeftCtrl:
            isCtrlDown = event.modifierFlags.contains(.control) && event.keyCode == 0x3B
        case .doubleRightCtrl:
            isCtrlDown = event.modifierFlags.contains(.control) && event.keyCode == 0x3E
        }

        guard isCtrlDown else { return }

        let now = Date()
        if let last = lastCtrlPressTime, now.timeIntervalSince(last) < doublePressInterval {
            lastCtrlPressTime = nil
            isEnabled.toggle()
        } else {
            lastCtrlPressTime = now
        }
    }

    // MARK: - Spotlight Activation

    func activateSpotlight() {
        guard !isSpotlightActive else { return }
        isSpotlightActive = true

        for screen in NSScreen.screens {
            let window = FindMyMouseOverlayWindow(
                screen: screen,
                overlayOpacity: overlayOpacity,
                backgroundColor: backgroundColor,
                spotlightRadius: spotlightRadius,
                animationDurationMs: animationDurationMs
            )
            window.showOverlay()
            overlayWindows.append(window)
        }

        startCursorTracking()
    }

    func dismissSpotlight() {
        guard isSpotlightActive else { return }
        isSpotlightActive = false

        stopCursorTracking()

        for window in overlayWindows {
            window.hideOverlay()
        }

        let windows = overlayWindows
        overlayWindows = []
        let duration = animationDurationMs / 1000.0
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.1) {
            for w in windows {
                w.close()
            }
        }
    }

    // MARK: - Cursor Tracking

    private func startCursorTracking() {
        cursorTrackingTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateCursorPosition()
            }
        }
        RunLoop.main.add(cursorTrackingTimer!, forMode: .common)
    }

    private func stopCursorTracking() {
        cursorTrackingTimer?.invalidate()
        cursorTrackingTimer = nil
    }

    private func updateCursorPosition() {
        let mouseLocation = NSEvent.mouseLocation
        for window in overlayWindows {
            window.updateSpotlight(at: mouseLocation)
        }
    }
}
