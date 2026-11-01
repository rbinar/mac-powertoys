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
    /// Double-tap Ctrl activation armed. The spotlight itself is `isSpotlightActive`.
    @Published var isEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "findMyMouse.isEnabled")
            if isEnabled {
                startMonitoring()
            } else {
                stopMonitoring()
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
    private var dismissGlobalMonitors: [Any] = []
    private var dismissLocalMonitors: [Any] = []
    private var lastClickDismissTime: Date?
    private var lastCtrlPressTime: Date?
    private var overlayWindows: [FindMyMouseOverlayWindow] = []
    private var cursorTrackingTimer: Timer?
    private let doublePressInterval: TimeInterval = 0.4

    init() {
        // Assigning in init does not fire didSet, so start monitors explicitly.
        isEnabled = UserDefaults.standard.bool(forKey: "findMyMouse.isEnabled")
        if isEnabled { startMonitoring() }
    }

    // MARK: - Monitoring (double-Ctrl listener, only while enabled)

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
        // Tear down the spotlight explicitly without mutating isEnabled
        // (avoids re-entrancy through the didSet).
        dismissSpotlight()
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
            if isSpotlightActive { dismissSpotlight() } else { activateSpotlight() }
        } else {
            lastCtrlPressTime = now
        }
    }

    // MARK: - Spotlight Activation

    func activateSpotlight() {
        // Idempotency guard FIRST: two rapid double-Ctrl taps each hop onto the
        // main actor via Task { @MainActor }; flipping isSpotlightActive before
        // any window is created ensures a second entrant returns early instead
        // of appending a duplicate set of overlay windows that would leak.
        guard !isSpotlightActive else { return }
        isSpotlightActive = true
        startDismissMonitors()

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
        stopDismissMonitors()

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

    /// Test button action. Ignores the action that follows a click-dismiss
    /// (mouse-down dismisses via the monitor, mouse-up would re-activate).
    func toggleSpotlightFromButton() {
        if let t = lastClickDismissTime, Date().timeIntervalSince(t) < 0.5 { return }
        if isSpotlightActive { dismissSpotlight() } else { activateSpotlight() }
    }

    // MARK: - Dismiss Monitors (ESC / click)

    private func startDismissMonitors() {
        stopDismissMonitors()
        let globals: [Any?] = [
            NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.keyCode == 53 else { return }
                Task { @MainActor in self?.dismissSpotlight() }
            },
            NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
                Task { @MainActor in self?.dismissFromClick() }
            }
        ]
        let locals: [Any?] = [
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == 53 { Task { @MainActor in self?.dismissSpotlight() } }
                return event
            },
            NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                Task { @MainActor in self?.dismissFromClick() }
                return event
            }
        ]
        dismissGlobalMonitors = globals.compactMap { $0 }
        dismissLocalMonitors = locals.compactMap { $0 }
    }

    private func stopDismissMonitors() {
        for m in dismissGlobalMonitors + dismissLocalMonitors { NSEvent.removeMonitor(m) }
        dismissGlobalMonitors = []
        dismissLocalMonitors = []
    }

    private func dismissFromClick() {
        guard isSpotlightActive else { return }
        lastClickDismissTime = Date()
        dismissSpotlight()
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
