import Foundation
import AppKit

@MainActor
final class MouseHighlighterModel: ObservableObject {
    // MARK: - Settings
    @Published var isEnabled: Bool = false {
        didSet {
            if isEnabled { startMonitoring() } else { stopMonitoring() }
        }
    }
    @Published var primaryButtonColor: NSColor = NSColor.systemYellow
    @Published var secondaryButtonColor: NSColor = NSColor.systemBlue
    @Published var highlightRadius: CGFloat = 30
    @Published var fadeDelayMs: Double = 300
    @Published var fadeDurationMs: Double = 400

    // MARK: - Private
    private var globalLeftMonitor: Any?
    private var globalRightMonitor: Any?
    private var localLeftMonitor: Any?
    private var localRightMonitor: Any?
    private var overlayWindows: [(window: NSWindow, view: MouseHighlighterOverlayView)] = []
    private var shortcutGlobalMonitor: Any?
    private var shortcutLocalMonitor: Any?
    private var lastOptionPressTime: Date?
    private let doublePressInterval: TimeInterval = 0.4

    init() {
        registerShortcut()
    }

    // MARK: - Shortcut (Double Left ⌥)

    private func registerShortcut() {
        shortcutGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in self?.handleFlagsChanged(event) }
        }
        shortcutLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in self?.handleFlagsChanged(event) }
            return event
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        // Left Option key = keyCode 0x3A
        guard event.modifierFlags.contains(.option), event.keyCode == 0x3A else { return }
        let now = Date()
        if let last = lastOptionPressTime, now.timeIntervalSince(last) < doublePressInterval {
            lastOptionPressTime = nil
            isEnabled.toggle()
        } else {
            lastOptionPressTime = now
        }
    }

    // MARK: - Monitoring

    func startMonitoring() {
        guard isEnabled else { return }
        stopMonitoring()
        setupOverlayWindow()

        globalLeftMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            Task { @MainActor in self?.handleClick(at: NSEvent.mouseLocation, isPrimary: true) }
        }
        globalRightMonitor = NSEvent.addGlobalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            Task { @MainActor in self?.handleClick(at: NSEvent.mouseLocation, isPrimary: false) }
        }
        localLeftMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            Task { @MainActor in self?.handleClick(at: NSEvent.mouseLocation, isPrimary: true) }
            return event
        }
        localRightMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            Task { @MainActor in self?.handleClick(at: NSEvent.mouseLocation, isPrimary: false) }
            return event
        }
    }

    func stopMonitoring() {
        if let m = globalLeftMonitor { NSEvent.removeMonitor(m); globalLeftMonitor = nil }
        if let m = globalRightMonitor { NSEvent.removeMonitor(m); globalRightMonitor = nil }
        if let m = localLeftMonitor { NSEvent.removeMonitor(m); localLeftMonitor = nil }
        if let m = localRightMonitor { NSEvent.removeMonitor(m); localRightMonitor = nil }
        removeOverlayWindows()
    }

    // MARK: - Overlay Windows (per screen)

    private func removeOverlayWindows() {
        for entry in overlayWindows {
            entry.view.stopTimer()
            entry.window.orderOut(nil)
        }
        overlayWindows.removeAll()
    }

    private func setupOverlayWindow() {
        removeOverlayWindows()

        for screen in NSScreen.screens {
            let frame = screen.frame
            let view = MouseHighlighterOverlayView(frame: NSRect(origin: .zero, size: frame.size))

            let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false, screen: screen)
            window.contentView = view
            window.level = .screenSaver
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.animationBehavior = .none
            window.orderFrontRegardless()

            overlayWindows.append((window: window, view: view))
        }
    }

    // MARK: - Click Handling

    private func handleClick(at screenPoint: NSPoint, isPrimary: Bool) {
        let color = isPrimary ? primaryButtonColor : secondaryButtonColor
        for entry in overlayWindows {
            let windowFrame = entry.window.frame
            guard windowFrame.contains(screenPoint) else { continue }
            let localPoint = NSPoint(x: screenPoint.x - windowFrame.origin.x,
                                     y: screenPoint.y - windowFrame.origin.y)
            entry.view.addHighlight(
                at: localPoint,
                color: color,
                radius: highlightRadius,
                fadeDelay: fadeDelayMs / 1000.0,
                fadeDuration: fadeDurationMs / 1000.0
            )
            break
        }
    }
}

// MARK: - Overlay View

class MouseHighlighterOverlayView: NSView {
    private struct Highlight {
        let center: NSPoint
        let color: NSColor
        let radius: CGFloat
        let createdAt: CFTimeInterval
        let fadeDelay: CFTimeInterval
        let fadeDuration: CFTimeInterval

        var opacity: CGFloat {
            let elapsed = CACurrentMediaTime() - createdAt
            if elapsed < fadeDelay { return 0.6 }
            let fadeProgress = min((elapsed - fadeDelay) / fadeDuration, 1.0)
            return CGFloat(0.6 * (1.0 - fadeProgress))
        }

        var isExpired: Bool {
            CACurrentMediaTime() - createdAt > fadeDelay + fadeDuration
        }
    }

    private var highlights: [Highlight] = []
    private var cleanupTimer: Timer?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.isOpaque = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    func addHighlight(at localPoint: NSPoint, color: NSColor, radius: CGFloat, fadeDelay: Double, fadeDuration: Double) {
        highlights.append(Highlight(
            center: localPoint,
            color: color,
            radius: radius,
            createdAt: CACurrentMediaTime(),
            fadeDelay: fadeDelay,
            fadeDuration: fadeDuration
        ))
        startCleanupTimer()
        setNeedsDisplay(bounds)
    }

    func stopTimer() {
        cleanupTimer?.invalidate()
        cleanupTimer = nil
    }

    private func startCleanupTimer() {
        guard cleanupTimer == nil else { return }
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.tick()
            }
        }
        RunLoop.main.add(cleanupTimer!, forMode: .common)
    }

    private func tick() {
        highlights.removeAll { $0.isExpired }
        if highlights.isEmpty {
            cleanupTimer?.invalidate()
            cleanupTimer = nil
        }
        setNeedsDisplay(bounds)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        ctx.clear(bounds)

        for highlight in highlights {
            let opacity = highlight.opacity
            guard opacity > 0 else { continue }

            let r = highlight.radius
            let rect = CGRect(x: highlight.center.x - r, y: highlight.center.y - r, width: r * 2, height: r * 2)
            let color = highlight.color.withAlphaComponent(opacity)

            ctx.setFillColor(color.cgColor)
            ctx.fillEllipse(in: rect)
        }
    }
}
