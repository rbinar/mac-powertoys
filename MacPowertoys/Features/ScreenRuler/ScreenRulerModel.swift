import Foundation
import AppKit
import ScreenCaptureKit
import Carbon.HIToolbox

// Global C callback for Screen Ruler hotkey
private func screenRulerHotKeyHandler(nextHandler: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let userData, let event else { return OSStatus(eventNotHandledErr) }
    
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
    guard status == noErr else { return status }

    let model = Unmanaged<ScreenRulerModel>.fromOpaque(userData).takeUnretainedValue()
    
    Task { @MainActor in
        switch hotKeyID.id {
        case 2: // ⌃⌥R toggle
            model.isEnabled.toggle()
        case 3: // ESC close
            if model.isEnabled {
                model.isEnabled = false
            }
        default:
            break
        }
    }
    return noErr
}

// MARK: - Enums

enum MeasurementMode: String, CaseIterable {
    case bounds = "Bounds"
    case spacing = "Spacing"
    case horizontal = "Horizontal"
    case vertical = "Vertical"
}

enum ExtraUnit: String, CaseIterable {
    case none = "None"
    case inches = "Inches"
    case centimeters = "Centimeters"
    case millimeters = "Millimeters"
}

// MARK: - Captured Screen Pixel Buffer

struct CapturedScreen {
    let pixelData: Data
    let width: Int
    let height: Int
    let bytesPerRow: Int
    /// Points-to-pixels scale factors for coordinate conversion
    let scaleX: CGFloat
    let scaleY: CGFloat
}

// MARK: - Measurement Result

struct EdgeDistances {
    var left: Int = 0
    var right: Int = 0
    var top: Int = 0
    var bottom: Int = 0
}

// MARK: - Screen Ruler Model

@MainActor
final class ScreenRulerModel: ObservableObject {
    // MARK: - Settings
    @Published var isEnabled: Bool = false {
        didSet {
            if isEnabled { activate() } else { deactivate() }
        }
    }
    @Published var measurementMode: MeasurementMode = .spacing
    @Published var pixelTolerance: Double = 30
    @Published var perChannelDetection: Bool = false
    @Published var continuousCapture: Bool = false
    @Published var extraUnit: ExtraUnit = .none
    @Published var lineColor: NSColor = NSColor.systemYellow {
        didSet { updateOverlaySettings() }
    }
    @Published var showFeet: Bool = true {
        didSet { updateOverlaySettings() }
    }

    // MARK: - Runtime State
    @Published private(set) var isActive: Bool = false
    @Published var currentEdges: EdgeDistances = EdgeDistances()
    @Published var boundsStart: NSPoint? = nil
    @Published var boundsEnd: NSPoint? = nil

    // MARK: - Private
    private var overlayWindows: [(window: NSWindow, view: ScreenRulerOverlayView, displayID: UInt32, screen: NSScreen)] = []
    private var toolbarWindow: NSWindow?
    private var toolbarView: ScreenRulerToolbarView?
    private var trackingTimer: Timer?
    private var capturedScreens: [UInt32: CapturedScreen] = [:]
    private var captureTickCounter: Int = 0
    private var elevatedWindows: [NSWindow] = []

    // Keyboard & mouse monitors (active during measurement)
    private var keyGlobalMonitor: Any?
    private var keyLocalMonitor: Any?
    private var mouseDownGlobalMonitor: Any?
    private var mouseDownLocalMonitor: Any?
    private var mouseDragGlobalMonitor: Any?
    private var mouseDragLocalMonitor: Any?
    private var mouseUpGlobalMonitor: Any?
    private var mouseUpLocalMonitor: Any?
    private var scrollGlobalMonitor: Any?
    private var scrollLocalMonitor: Any?

    // Carbon hotkey
    private var hotKeyRef: EventHotKeyRef?
    private var escHotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    init() {
        registerCarbonHotKey()
    }

    // MARK: - Global Shortcut (⌃⌥R) via Carbon HotKey

    private func registerCarbonHotKey() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), screenRulerHotKeyHandler, 1, &eventType, selfPtr, &eventHandlerRef)

        // ⌃⌥R  (keyCode kVK_ANSI_R = 15)
        var hotKeyID = EventHotKeyID(signature: OSType(0x52554C52), id: 2) // "RULR"
        let modifiers: UInt32 = UInt32(controlKey | optionKey)
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_R), modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status == noErr {
            print("[ScreenRuler] Carbon HotKey ⌃⌥R registered successfully")
        } else {
            print("[ScreenRuler] Failed to register Carbon HotKey: \(status)")
        }
    }

    private func registerEscHotKey() {
        guard escHotKeyRef == nil else { return }
        // ESC (no modifiers) to close
        var escHotKeyID = EventHotKeyID(signature: OSType(0x52554C52), id: 3) // "RULR" id:3
        let escStatus = RegisterEventHotKey(UInt32(kVK_Escape), 0, escHotKeyID, GetApplicationEventTarget(), 0, &escHotKeyRef)
        if escStatus == noErr {
            print("[ScreenRuler] Carbon HotKey ESC registered successfully")
        } else {
            print("[ScreenRuler] Failed to register ESC HotKey: \(escStatus)")
        }
    }

    private func unregisterEscHotKey() {
        if let ref = escHotKeyRef {
            UnregisterEventHotKey(ref)
            escHotKeyRef = nil
            print("[ScreenRuler] Carbon HotKey ESC unregistered")
        }
    }

    // MARK: - Activation

    private func activate() {
        guard !isActive else { return }

        // Check Screen Recording permissions
        if !CGPreflightScreenCaptureAccess() {
            // Only show the custom alert if the system can't prompt the user.
            if !CGRequestScreenCaptureAccess() {
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Screen Recording Permission Required"
                    alert.informativeText = "MacPowerToys needs Screen Recording permission to measure elements on the screen. Please grant permission in System Settings > Privacy & Security > Screen Recording, then restart the app."
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "Open System Settings")
                    alert.addButton(withTitle: "Cancel")
                    if alert.runModal() == .alertFirstButtonReturn {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
            isEnabled = false
            return
        }

        isActive = true

        // Capture screens BEFORE creating overlay windows so they aren't in the screenshot
        Task {
            await captureScreensAsync()
            createOverlayWindows()
            showToolbar()
            elevateAppWindows()
            startTracking()
            registerActiveMonitors()
            registerEscHotKey()
        }
    }

    private func deactivate() {
        guard isActive else { return }
        isActive = false
        unregisterEscHotKey()
        stopTracking()
        removeActiveMonitors()
        hideToolbar()
        removeOverlayWindows()
        restoreAppWindows()
        capturedScreens.removeAll()
        boundsStart = nil
        boundsEnd = nil
    }

    private func elevateAppWindows() {
        for window in NSApplication.shared.windows {
            // Skip overlay and toolbar windows
            if overlayWindows.contains(where: { $0.window === window }) { continue }
            if window === toolbarWindow { continue }
            
            // Elevate normal windows so user can click the toggle to turn it off
            // Also elevate popovers/panels (like the color picker)
            if window.level == .normal || window.level == .popUpMenu {
                window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)
                elevatedWindows.append(window)
            }
        }
    }

    private func restoreAppWindows() {
        for window in elevatedWindows {
            window.level = .normal
        }
        elevatedWindows.removeAll()
    }

    // MARK: - Screen Capture

    private func captureScreensAsync() async {
        capturedScreens.removeAll()
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

            // Exclude our own overlay and toolbar windows
            let ownWindowIDs = Set(overlayWindows.map { $0.window.windowNumber } + [toolbarWindow?.windowNumber].compactMap { $0 })
            let excludedWindows = content.windows.filter { ownWindowIDs.contains(Int($0.windowID)) }

            for display in content.displays {
                let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
                let config = SCStreamConfiguration()
                // Let ScreenCaptureKit use the display's native pixel resolution
                config.width = display.width
                config.height = display.height
                config.capturesAudio = false
                config.showsCursor = false

                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)

                // Find the matching NSScreen to get the point-size frame
                let screen = NSScreen.screens.first { screenID(for: $0) == display.displayID }
                let screenFrame = screen?.frame ?? CGRect(x: 0, y: 0, width: CGFloat(display.width), height: CGFloat(display.height))

                if let captured = renderToBitmapBuffer(image, screenFrame: screenFrame) {
                    capturedScreens[display.displayID] = captured
                }
            }
        } catch {
            print("Screen capture failed: \(error.localizedDescription)")
        }
    }

    private func renderToBitmapBuffer(_ image: CGImage, screenFrame: CGRect) -> CapturedScreen? {
        let w = image.width
        let h = image.height
        let bytesPerPixel = 4
        let bytesPerRow = w * bytesPerPixel
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        // Use BGRA (nativeEndian + premultipliedFirst) to match PowerToys B8G8R8A8
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)

        guard let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ), let baseAddress = ctx.data else {
            return nil
        }

        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let data = Data(bytes: baseAddress, count: h * bytesPerRow)
        return CapturedScreen(
            pixelData: data,
            width: w,
            height: h,
            bytesPerRow: bytesPerRow,
            scaleX: CGFloat(w) / screenFrame.width,
            scaleY: CGFloat(h) / screenFrame.height
        )
    }

    private func screenID(for screen: NSScreen) -> UInt32 {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32) ?? 0
    }

    // MARK: - Overlay Windows

    private func createOverlayWindows() {
        for screen in NSScreen.screens {
            let frame = screen.frame
            let did = screenID(for: screen)
            let view = ScreenRulerOverlayView(frame: NSRect(origin: .zero, size: frame.size))
            view.lineColor = lineColor
            view.showFeet = showFeet
            view.measurementMode = measurementMode

            let window = NSWindow(
                contentRect: frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.contentView = view
            window.level = .screenSaver
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.animationBehavior = .none
            window.orderFrontRegardless()

            overlayWindows.append((window: window, view: view, displayID: did, screen: screen))
        }
    }

    private func removeOverlayWindows() {
        for entry in overlayWindows {
            entry.window.orderOut(nil)
        }
        overlayWindows.removeAll()
    }

    private func updateOverlaySettings() {
        for entry in overlayWindows {
            entry.view.lineColor = lineColor
            entry.view.showFeet = showFeet
            entry.view.setNeedsDisplay(entry.view.bounds)
        }
    }

    // MARK: - Toolbar

    private func showToolbar() {
        guard let mainScreen = NSScreen.main else { return }

        let toolbarWidth: CGFloat = 200
        let toolbarHeight: CGFloat = 40
        let x = mainScreen.frame.midX - toolbarWidth / 2
        let y = mainScreen.frame.maxY - 80

        let view = ScreenRulerToolbarView(
            frame: NSRect(x: 0, y: 0, width: toolbarWidth, height: toolbarHeight),
            onModeChange: { [weak self] mode in
                Task { @MainActor in self?.setMode(mode) }
            },
            onClose: { [weak self] in
                Task { @MainActor in self?.isEnabled = false }
            }
        )
        view.currentMode = measurementMode

        let window = NSWindow(
            contentRect: NSRect(x: x, y: y, width: toolbarWidth, height: toolbarHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        window.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.92)
        window.isOpaque = false
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.animationBehavior = .utilityWindow
        window.orderFrontRegardless()

        // Round corners
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.cornerRadius = 10
        window.contentView?.layer?.masksToBounds = true

        toolbarWindow = window
        toolbarView = view
    }

    private func hideToolbar() {
        toolbarWindow?.orderOut(nil)
        toolbarWindow = nil
        toolbarView = nil
    }

    func setMode(_ mode: MeasurementMode) {
        measurementMode = mode
        boundsStart = nil
        boundsEnd = nil
        for entry in overlayWindows {
            entry.view.measurementMode = mode
            entry.view.boundsStart = nil
            entry.view.boundsEnd = nil
            entry.view.setNeedsDisplay(entry.view.bounds)
        }
        toolbarView?.currentMode = mode
        toolbarView.map { $0.setNeedsDisplay($0.bounds) }
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
        // Continuous capture: re-capture every ~5 ticks (~12fps)
        if continuousCapture {
            captureTickCounter += 1
            if captureTickCounter >= 5 {
                captureTickCounter = 0
                Task { await captureScreensAsync() }
            }
        }

        let screenPoint = NSEvent.mouseLocation
        for entry in overlayWindows {
            let frame = entry.window.frame
            if frame.contains(screenPoint) {
                let localPoint = NSPoint(
                    x: screenPoint.x - frame.origin.x,
                    y: screenPoint.y - frame.origin.y
                )
                entry.view.cursorPosition = localPoint
                entry.view.isActiveScreen = true

                // Use stored displayID directly — no fragile frame comparison
                if let captured = capturedScreens[entry.displayID] {
                    let edges = detectEdges(
                        in: captured,
                        at: localPoint,
                        screenFrame: frame
                    )
                    entry.view.edges = edges
                    entry.view.extraUnit = extraUnit
                    entry.view.screenDPI = screenDPI(for: entry.screen)
                    currentEdges = edges
                }
            } else {
                entry.view.isActiveScreen = false
            }
            entry.view.setNeedsDisplay(entry.view.bounds)
        }
    }

    // MARK: - Event Monitors (Active during measurement)

    private func registerActiveMonitors() {
        // Keyboard: Esc to close, Cmd+1-4 for mode
        keyGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in self?.handleKeyDown(event) }
        }
        keyLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in self?.handleKeyDown(event) }
            return event
        }

        // Mouse events for bounds mode and click-to-copy
        mouseDownGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            Task { @MainActor in self?.handleMouseDown(event) }
        }
        mouseDownLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            Task { @MainActor in self?.handleMouseDown(event) }
            return event
        }
        mouseDragGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] event in
            Task { @MainActor in self?.handleMouseDragged(event) }
        }
        mouseDragLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged) { [weak self] event in
            Task { @MainActor in self?.handleMouseDragged(event) }
            return event
        }
        mouseUpGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            Task { @MainActor in self?.handleMouseUp(event) }
        }
        mouseUpLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            Task { @MainActor in self?.handleMouseUp(event) }
            return event
        }

        // Scroll wheel for tolerance adjustment
        scrollGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            Task { @MainActor in self?.handleScrollWheel(event) }
        }
        scrollLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            Task { @MainActor in self?.handleScrollWheel(event) }
            return event
        }
    }

    private func removeActiveMonitors() {
        if let m = keyGlobalMonitor { NSEvent.removeMonitor(m); keyGlobalMonitor = nil }
        if let m = keyLocalMonitor { NSEvent.removeMonitor(m); keyLocalMonitor = nil }
        if let m = mouseDownGlobalMonitor { NSEvent.removeMonitor(m); mouseDownGlobalMonitor = nil }
        if let m = mouseDownLocalMonitor { NSEvent.removeMonitor(m); mouseDownLocalMonitor = nil }
        if let m = mouseDragGlobalMonitor { NSEvent.removeMonitor(m); mouseDragGlobalMonitor = nil }
        if let m = mouseDragLocalMonitor { NSEvent.removeMonitor(m); mouseDragLocalMonitor = nil }
        if let m = mouseUpGlobalMonitor { NSEvent.removeMonitor(m); mouseUpGlobalMonitor = nil }
        if let m = mouseUpLocalMonitor { NSEvent.removeMonitor(m); mouseUpLocalMonitor = nil }
        if let m = scrollGlobalMonitor { NSEvent.removeMonitor(m); scrollGlobalMonitor = nil }
        if let m = scrollLocalMonitor { NSEvent.removeMonitor(m); scrollLocalMonitor = nil }
    }

    private func handleKeyDown(_ event: NSEvent) {
        // Esc to close
        if event.keyCode == 53 {
            isEnabled = false
            return
        }
        // Cmd+1-4 for mode selection
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers {
            case "1": setMode(.bounds)
            case "2": setMode(.spacing)
            case "3": setMode(.horizontal)
            case "4": setMode(.vertical)
            default: break
            }
        }
    }

    private func handleMouseDown(_ event: NSEvent) {
        let screenPoint = NSEvent.mouseLocation

        // Check if click is on the toolbar — ignore if so
        if let tbFrame = toolbarWindow?.frame, tbFrame.contains(screenPoint) {
            return
        }
        
        // Check if click is on an elevated app window (like Settings)
        for window in elevatedWindows {
            if window.frame.contains(screenPoint) {
                return
            }
        }

        if measurementMode == .bounds {
            // Start bounds measurement
            for entry in overlayWindows {
                let frame = entry.window.frame
                if frame.contains(screenPoint) {
                    let localPoint = NSPoint(
                        x: screenPoint.x - frame.origin.x,
                        y: screenPoint.y - frame.origin.y
                    )
                    boundsStart = localPoint
                    boundsEnd = localPoint
                    entry.view.boundsStart = localPoint
                    entry.view.boundsEnd = localPoint
                }
            }
        } else {
            // Click to copy measurement in non-bounds modes
            copyMeasurementToClipboard()
        }
    }

    private func handleMouseDragged(_ event: NSEvent) {
        guard measurementMode == .bounds, boundsStart != nil else { return }
        let screenPoint = NSEvent.mouseLocation
        for entry in overlayWindows {
            let frame = entry.window.frame
            if frame.contains(screenPoint) {
                let localPoint = NSPoint(
                    x: screenPoint.x - frame.origin.x,
                    y: screenPoint.y - frame.origin.y
                )
                boundsEnd = localPoint
                entry.view.boundsEnd = localPoint
                entry.view.setNeedsDisplay(entry.view.bounds)
            }
        }
    }

    private func handleMouseUp(_ event: NSEvent) {
        guard measurementMode == .bounds, boundsStart != nil else { return }
        let screenPoint = NSEvent.mouseLocation

        // Check if mouse up is on the toolbar — ignore if so
        if let tbFrame = toolbarWindow?.frame, tbFrame.contains(screenPoint) {
            return
        }
        
        // Check if click is on an elevated app window
        for window in elevatedWindows {
            if window.frame.contains(screenPoint) {
                return
            }
        }

        for entry in overlayWindows {
            let frame = entry.window.frame
            if frame.contains(screenPoint) {
                let localPoint = NSPoint(
                    x: screenPoint.x - frame.origin.x,
                    y: screenPoint.y - frame.origin.y
                )
                boundsEnd = localPoint
                entry.view.boundsEnd = localPoint
                entry.view.setNeedsDisplay(entry.view.bounds)
            }
        }
        // Copy bounds measurement
        copyBoundsMeasurementToClipboard()
    }

    private func handleScrollWheel(_ event: NSEvent) {
        // Scroll up increases tolerance, scroll down decreases
        let delta = event.scrollingDeltaY
        let step: Double = 15
        if delta > 0 {
            pixelTolerance = min(255, pixelTolerance + step)
        } else if delta < 0 {
            pixelTolerance = max(0, pixelTolerance - step)
        }
    }

    // MARK: - Clipboard

    private func copyMeasurementToClipboard() {
        var text = ""
        switch measurementMode {
        case .spacing:
            text = "H: \(max(1, currentEdges.left + currentEdges.right)) px, V: \(max(1, currentEdges.top + currentEdges.bottom)) px"
        case .horizontal:
            text = "\(max(1, currentEdges.left + currentEdges.right)) px"
        case .vertical:
            text = "\(max(1, currentEdges.top + currentEdges.bottom)) px"
        case .bounds:
            break
        }
        if !text.isEmpty {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }

    private func copyBoundsMeasurementToClipboard() {
        guard let start = boundsStart, let end = boundsEnd else { return }
        let w = Int(abs(end.x - start.x))
        let h = Int(abs(end.y - start.y))
        let text = "\(w) × \(h) px"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - Edge Detection

    private func detectEdges(
        in captured: CapturedScreen,
        at localPoint: NSPoint,
        screenFrame: NSRect
    ) -> EdgeDistances {
        let imgWidth = captured.width
        let imgHeight = captured.height

        let scaleX = captured.scaleX
        let scaleY = captured.scaleY

        // X conversion is straightforward. Y conversion can vary depending on bitmap orientation.
        let samplePoint = NSPoint(
            x: min(max(localPoint.x, 0), screenFrame.width - 1),
            y: min(max(localPoint.y, 0), screenFrame.height - 1)
        )

        let pixelX = Int(samplePoint.x * scaleX)
        let pixelYTopOrigin = Int((screenFrame.height - samplePoint.y) * scaleY)
        let pixelYBottomOrigin = Int(samplePoint.y * scaleY)

        // Clamp to safe range (1..width-2) like PowerToys does.
        let clampedX = max(1, min(pixelX, imgWidth - 2))

        let bytesPerRow = captured.bytesPerRow
        let tolerance = Int(pixelTolerance)
        let usePerChannel = perChannelDetection

        return captured.pixelData.withUnsafeBytes { rawBuffer -> EdgeDistances in
            let ptr = rawBuffer.baseAddress!.assumingMemoryBound(to: UInt8.self)

            // BGRA format: B=0, G=1, R=2, A=3 (byteOrder32Little + premultipliedFirst)
            func getPixel(_ x: Int, _ y: Int) -> UInt32 {
                let offset = y * bytesPerRow + x * 4
                return UnsafeRawPointer(ptr + offset).load(as: UInt32.self)
            }

            func getComponents(_ p: UInt32) -> (b: Int, g: Int, r: Int) {
                (
                    Int(p & 0xFF),
                    Int((p >> 8) & 0xFF),
                    Int((p >> 16) & 0xFF)
                )
            }

            // Average a small neighborhood to reduce sensitivity to antialiasing/noise.
            func averageColor(at x: Int, _ y: Int, radius: Int = 1) -> (b: Int, g: Int, r: Int) {
                var sb = 0
                var sg = 0
                var sr = 0
                var count = 0

                for yy in max(0, y - radius)...min(imgHeight - 1, y + radius) {
                    for xx in max(0, x - radius)...min(imgWidth - 1, x + radius) {
                        let c = getComponents(getPixel(xx, yy))
                        sb += c.b
                        sg += c.g
                        sr += c.r
                        count += 1
                    }
                }

                guard count > 0 else { return (0, 0, 0) }
                return (sb / count, sg / count, sr / count)
            }

            func pixelsCloseToStart(_ c: (b: Int, g: Int, r: Int), _ start: (b: Int, g: Int, r: Int)) -> Bool {
                let b0 = abs(c.b - start.b)
                let g0 = abs(c.g - start.g)
                let r0 = abs(c.r - start.r)
                if usePerChannel {
                    return b0 <= tolerance && g0 <= tolerance && r0 <= tolerance
                } else {
                    return (b0 + g0 + r0) <= tolerance
                }
            }

            func detectForY(_ yInput: Int) -> EdgeDistances {
                let clampedY = max(1, min(yInput, imgHeight - 2))
                let startColor = averageColor(at: clampedX, clampedY)

                // Scan left — find last similar pixel position.
                var leftEdge = 0
                do {
                    var x = clampedX
                    while x > 0 {
                        x -= 1
                        let c = getComponents(getPixel(x, clampedY))
                        if !pixelsCloseToStart(c, startColor) {
                            break
                        }
                    }
                    leftEdge = x + 1
                    let c = getComponents(getPixel(x, clampedY))
                    if pixelsCloseToStart(c, startColor) {
                        leftEdge = 0
                    }
                }

                // Scan right.
                var rightEdge = imgWidth - 1
                do {
                    var x = clampedX
                    while x < imgWidth - 1 {
                        x += 1
                        let c = getComponents(getPixel(x, clampedY))
                        if !pixelsCloseToStart(c, startColor) {
                            break
                        }
                    }
                    rightEdge = x - 1
                    let c = getComponents(getPixel(x, clampedY))
                    if pixelsCloseToStart(c, startColor) {
                        rightEdge = imgWidth - 1
                    }
                }

                // Scan up (decreasing y in image coords).
                var topEdge = 0
                do {
                    var y = clampedY
                    while y > 0 {
                        y -= 1
                        let c = getComponents(getPixel(clampedX, y))
                        if !pixelsCloseToStart(c, startColor) {
                            break
                        }
                    }
                    topEdge = y + 1
                    let c = getComponents(getPixel(clampedX, y))
                    if pixelsCloseToStart(c, startColor) {
                        topEdge = 0
                    }
                }

                // Scan down (increasing y in image coords).
                var bottomEdge = imgHeight - 1
                do {
                    var y = clampedY
                    while y < imgHeight - 1 {
                        y += 1
                        let c = getComponents(getPixel(clampedX, y))
                        if !pixelsCloseToStart(c, startColor) {
                            break
                        }
                    }
                    bottomEdge = y - 1
                    let c = getComponents(getPixel(clampedX, y))
                    if pixelsCloseToStart(c, startColor) {
                        bottomEdge = imgHeight - 1
                    }
                }

                return EdgeDistances(
                    left: Int(CGFloat(clampedX - leftEdge) / scaleX),
                    right: Int(CGFloat(rightEdge - clampedX) / scaleX),
                    top: Int(CGFloat(clampedY - topEdge) / scaleY),
                    bottom: Int(CGFloat(bottomEdge - clampedY) / scaleY)
                )
            }

            let edgesTopOrigin = detectForY(pixelYTopOrigin)
            let edgesBottomOrigin = detectForY(pixelYBottomOrigin)

            let spanTop = edgesTopOrigin.left + edgesTopOrigin.right + edgesTopOrigin.top + edgesTopOrigin.bottom
            let spanBottom = edgesBottomOrigin.left + edgesBottomOrigin.right + edgesBottomOrigin.top + edgesBottomOrigin.bottom

            return spanTop >= spanBottom ? edgesTopOrigin : edgesBottomOrigin
        }
    }

    // MARK: - Unit Conversion

    func screenDPI(for screen: NSScreen) -> CGFloat {
        if let resolution = screen.deviceDescription[NSDeviceDescriptionKey.resolution] as? NSSize {
            return resolution.width // DPI along x-axis
        }
        return 72.0 // Default macOS DPI
    }

    func convertPixels(_ pixels: Int, dpi: CGFloat, unit: ExtraUnit) -> String? {
        guard unit != .none else { return nil }
        let inches = CGFloat(pixels) / dpi
        switch unit {
        case .none:
            return nil
        case .inches:
            return String(format: "%.2f in", inches)
        case .centimeters:
            return String(format: "%.2f cm", inches * 2.54)
        case .millimeters:
            return String(format: "%.1f mm", inches * 25.4)
        }
    }

    // MARK: - Cleanup

    func stopMonitoring() {
        deactivate()
        if let ref = hotKeyRef { UnregisterEventHotKey(ref); hotKeyRef = nil }
        if let ref = escHotKeyRef { UnregisterEventHotKey(ref); escHotKeyRef = nil }
        if let ref = eventHandlerRef { RemoveEventHandler(ref); eventHandlerRef = nil }
    }
}
