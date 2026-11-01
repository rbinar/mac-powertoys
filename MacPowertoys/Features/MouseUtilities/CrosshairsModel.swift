import Foundation
import AppKit

// MARK: - Persistence helpers

private func crosshairsSaveColor(_ c: NSColor, _ key: String) {
    let s = c.usingColorSpace(.sRGB) ?? c
    UserDefaults.standard.set([Double(s.redComponent), Double(s.greenComponent), Double(s.blueComponent), Double(s.alphaComponent)], forKey: key)
}

private func crosshairsLoadColor(_ key: String, _ fallback: NSColor) -> NSColor {
    guard let a = UserDefaults.standard.array(forKey: key) as? [Double], a.count == 4 else { return fallback }
    return NSColor(srgbRed: CGFloat(a[0]), green: CGFloat(a[1]), blue: CGFloat(a[2]), alpha: CGFloat(a[3]))
}

@MainActor
final class CrosshairsModel: ObservableObject {
    // MARK: - Settings
    @Published var isEnabled: Bool = false {
        didSet {
            if isEnabled { activate() } else { deactivate() }
        }
    }
    @Published var crosshairColor: NSColor = NSColor.systemYellow {
        didSet {
            crosshairsSaveColor(crosshairColor, "crosshairs.crosshairColor")
            for entry in overlayWindows { entry.view.crosshairColor = crosshairColor }
        }
    }
    @Published var crosshairOpacity: Double = 0.75 {
        didSet {
            UserDefaults.standard.set(crosshairOpacity, forKey: "crosshairs.crosshairOpacity")
            for entry in overlayWindows { entry.view.crosshairOpacity = crosshairOpacity }
        }
    }
    @Published var centerRadius: CGFloat = 20 {
        didSet {
            UserDefaults.standard.set(Double(centerRadius), forKey: "crosshairs.centerRadius")
            for entry in overlayWindows { entry.view.centerRadius = centerRadius }
        }
    }
    @Published var thickness: CGFloat = 2 {
        didSet {
            UserDefaults.standard.set(Double(thickness), forKey: "crosshairs.thickness")
            for entry in overlayWindows { entry.view.thickness = thickness }
        }
    }
    @Published var borderColor: NSColor = NSColor.black {
        didSet {
            crosshairsSaveColor(borderColor, "crosshairs.borderColor")
            for entry in overlayWindows { entry.view.borderColor = borderColor }
        }
    }
    @Published var borderSize: CGFloat = 1 {
        didSet {
            UserDefaults.standard.set(Double(borderSize), forKey: "crosshairs.borderSize")
            for entry in overlayWindows { entry.view.borderSize = borderSize }
        }
    }

    // MARK: - Runtime State
    @Published private(set) var isActive: Bool = false

    // MARK: - Private
    private var overlayWindows: [(window: NSWindow, view: CrosshairsOverlayView)] = []
    private var trackingTimer: Timer?
    private var shortcutGlobalMonitor: Any?
    private var shortcutLocalMonitor: Any?
    private var escGlobalMonitor: Any?
    private var escLocalMonitor: Any?
    private var lastOptionPressTime: Date?
    private let doublePressInterval: TimeInterval = 0.4
    private let rightOptionKeyCode: UInt16 = 0x3D

    init() {
        let d = UserDefaults.standard
        crosshairColor = crosshairsLoadColor("crosshairs.crosshairColor", crosshairColor)
        if d.object(forKey: "crosshairs.crosshairOpacity") != nil { crosshairOpacity = d.double(forKey: "crosshairs.crosshairOpacity") }
        if d.object(forKey: "crosshairs.centerRadius") != nil { centerRadius = CGFloat(d.double(forKey: "crosshairs.centerRadius")) }
        if d.object(forKey: "crosshairs.thickness") != nil { thickness = CGFloat(d.double(forKey: "crosshairs.thickness")) }
        borderColor = crosshairsLoadColor("crosshairs.borderColor", borderColor)
        if d.object(forKey: "crosshairs.borderSize") != nil { borderSize = CGFloat(d.double(forKey: "crosshairs.borderSize")) }
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
        startEscMonitors()

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
        stopEscMonitors()
        stopTracking()
        for entry in overlayWindows {
            entry.window.orderOut(nil)
        }
        overlayWindows.removeAll()
    }

    // MARK: - ESC to turn off

    private func startEscMonitors() {
        stopEscMonitors()
        escGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return }
            Task { @MainActor in self?.isEnabled = false }
        }
        escLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { Task { @MainActor in self?.isEnabled = false } }
            return event
        }
    }

    private func stopEscMonitors() {
        if let m = escGlobalMonitor { NSEvent.removeMonitor(m); escGlobalMonitor = nil }
        if let m = escLocalMonitor { NSEvent.removeMonitor(m); escLocalMonitor = nil }
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
        if let m = shortcutGlobalMonitor { NSEvent.removeMonitor(m); shortcutGlobalMonitor = nil }
        if let m = shortcutLocalMonitor { NSEvent.removeMonitor(m); shortcutLocalMonitor = nil }
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
