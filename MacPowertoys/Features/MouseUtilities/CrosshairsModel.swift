import Foundation
import AppKit

@MainActor
final class CrosshairsModel: ObservableObject {
    // MARK: - Settings
    @Published var isEnabled: Bool = false {
        didSet {
            if isEnabled { activate() } else { deactivate() }
        }
    }
    @Published var crosshairColor: NSColor = NSColor.systemYellow {
        didSet { for entry in overlayWindows { entry.view.crosshairColor = crosshairColor } }
    }
    @Published var crosshairOpacity: Double = 0.75 {
        didSet { for entry in overlayWindows { entry.view.crosshairOpacity = crosshairOpacity } }
    }
    @Published var centerRadius: CGFloat = 20 {
        didSet { for entry in overlayWindows { entry.view.centerRadius = centerRadius } }
    }
    @Published var thickness: CGFloat = 2 {
        didSet { for entry in overlayWindows { entry.view.thickness = thickness } }
    }
    @Published var borderColor: NSColor = NSColor.black {
        didSet { for entry in overlayWindows { entry.view.borderColor = borderColor } }
    }
    @Published var borderSize: CGFloat = 1 {
        didSet { for entry in overlayWindows { entry.view.borderSize = borderSize } }
    }

    // MARK: - Runtime State
    @Published private(set) var isActive: Bool = false

    // MARK: - Private
    private var overlayWindows: [(window: NSWindow, view: CrosshairsOverlayView)] = []
    private var trackingTimer: Timer?
    private var shortcutGlobalMonitor: Any?
    private var shortcutLocalMonitor: Any?
    private var lastOptionPressTime: Date?
    private let doublePressInterval: TimeInterval = 0.4
    private let rightOptionKeyCode: UInt16 = 0x3D

    init() {
        registerShortcut()
    }

    // MARK: - Shortcut (Double Right ⌥)

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
        guard event.modifierFlags.contains(.option), event.keyCode == rightOptionKeyCode else { return }
        let now = Date()
        if let last = lastOptionPressTime, now.timeIntervalSince(last) < doublePressInterval {
            lastOptionPressTime = nil
            isEnabled.toggle()
        } else {
            lastOptionPressTime = now
        }
    }

    // MARK: - Activation

    private func activate() {
        guard !isActive else { return }
        isActive = true

        for screen in NSScreen.screens {
            let frame = screen.frame
            let view = CrosshairsOverlayView(frame: NSRect(origin: .zero, size: frame.size))
            view.crosshairColor = crosshairColor
            view.crosshairOpacity = crosshairOpacity
            view.centerRadius = centerRadius
            view.thickness = thickness
            view.borderColor = borderColor
            view.borderSize = borderSize

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

        startTracking()
    }

    private func deactivate() {
        guard isActive else { return }
        isActive = false
        stopTracking()
        for entry in overlayWindows {
            entry.window.orderOut(nil)
        }
        overlayWindows.removeAll()
    }

    // MARK: - Tracking

    private func startTracking() {
        trackingTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updatePosition()
            }
        }
        RunLoop.main.add(trackingTimer!, forMode: .common)
    }

    private func stopTracking() {
        trackingTimer?.invalidate()
        trackingTimer = nil
    }

    private func updatePosition() {
        let screenPoint = NSEvent.mouseLocation
        for entry in overlayWindows {
            let frame = entry.window.frame
            if frame.contains(screenPoint) {
                let localPoint = NSPoint(x: screenPoint.x - frame.origin.x,
                                         y: screenPoint.y - frame.origin.y)
                entry.view.cursorPosition = localPoint
                entry.view.isActiveScreen = true
            } else {
                entry.view.isActiveScreen = false
            }
            entry.view.setNeedsDisplay(entry.view.bounds)
        }
    }

    func stopMonitoring() {
        deactivate()
    }
}

// MARK: - Crosshairs Overlay View

class CrosshairsOverlayView: NSView {
    var crosshairColor: NSColor = .systemYellow
    var crosshairOpacity: Double = 0.75
    var centerRadius: CGFloat = 20
    var thickness: CGFloat = 2
    var borderColor: NSColor = .black
    var borderSize: CGFloat = 1
    var cursorPosition: NSPoint = .zero
    var isActiveScreen: Bool = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.isOpaque = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)

        guard isActiveScreen else { return }

        let viewPoint = cursorPosition
        let halfThickness = thickness / 2
        let halfBorder = (thickness + borderSize * 2) / 2

        // Draw border lines first (slightly thicker)
        let borderAlphaColor = borderColor.withAlphaComponent(CGFloat(crosshairOpacity))
        ctx.setFillColor(borderAlphaColor.cgColor)

        // Horizontal border
        let hBorderRect = CGRect(x: 0, y: viewPoint.y - halfBorder, width: bounds.width, height: thickness + borderSize * 2)
        ctx.fill(hBorderRect)

        // Vertical border
        let vBorderRect = CGRect(x: viewPoint.x - halfBorder, y: 0, width: thickness + borderSize * 2, height: bounds.height)
        ctx.fill(vBorderRect)

        // Draw crosshair lines on top
        let lineColor = crosshairColor.withAlphaComponent(CGFloat(crosshairOpacity))
        ctx.setFillColor(lineColor.cgColor)

        // Horizontal line (left part)
        let hLeftRect = CGRect(x: 0, y: viewPoint.y - halfThickness, width: viewPoint.x - centerRadius, height: thickness)
        if hLeftRect.width > 0 { ctx.fill(hLeftRect) }

        // Horizontal line (right part)
        let hRightX = viewPoint.x + centerRadius
        let hRightRect = CGRect(x: hRightX, y: viewPoint.y - halfThickness, width: bounds.width - hRightX, height: thickness)
        if hRightRect.width > 0 { ctx.fill(hRightRect) }

        // Vertical line (bottom part)
        let vBottomRect = CGRect(x: viewPoint.x - halfThickness, y: 0, width: thickness, height: viewPoint.y - centerRadius)
        if vBottomRect.height > 0 { ctx.fill(vBottomRect) }

        // Vertical line (top part)
        let vTopY = viewPoint.y + centerRadius
        let vTopRect = CGRect(x: viewPoint.x - halfThickness, y: vTopY, width: thickness, height: bounds.height - vTopY)
        if vTopRect.height > 0 { ctx.fill(vTopRect) }

        // Clear center gap (punch hole for center radius)
        ctx.setBlendMode(.clear)
        let centerRect = CGRect(
            x: viewPoint.x - centerRadius,
            y: viewPoint.y - centerRadius,
            width: centerRadius * 2,
            height: centerRadius * 2
        )
        ctx.fillEllipse(in: centerRect)
    }
}
