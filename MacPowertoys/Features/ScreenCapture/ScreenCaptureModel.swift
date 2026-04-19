import Foundation
import AppKit
import ScreenCaptureKit
import Carbon.HIToolbox

// MARK: - Hotkey Config

private struct ScreenCaptureHotKey {
    static let signature = OSType(0x53435054) // "SCPT"
    static let captureID: UInt32 = 1
    static let escID: UInt32 = 2
}

// MARK: - Global C callback

private func screenCaptureHotKeyHandler(
    nextHandler: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData, let event else { return OSStatus(eventNotHandledErr) }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }

    let model = Unmanaged<ScreenCaptureModel>.fromOpaque(userData).takeUnretainedValue()

    Task { @MainActor in
        switch hotKeyID.id {
        case ScreenCaptureHotKey.captureID:
            if model.isCapturing {
                model.cancelCapture()
            } else if model.isEnabled {
                model.startCapture()
            }
        case ScreenCaptureHotKey.escID:
            if model.isCapturing {
                model.cancelCapture()
            }
        default:
            break
        }
    }
    return noErr
}

// MARK: - ScreenCaptureModel

@MainActor
final class ScreenCaptureModel: ObservableObject {

    // MARK: - Settings

    @Published var isEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "screenCapture.isEnabled")
            if !isEnabled && isCapturing {
                cancelCapture()
            }
        }
    }

    // MARK: - Runtime State

    @Published private(set) var isCapturing: Bool = false

    // MARK: - Private — Selection State

    private var selectionStart: NSPoint?
    private var selectionEnd: NSPoint?

    // MARK: - Private — Windows & Views

    private var overlayWindows: [(window: NSWindow, view: ScreenCaptureOverlayView, displayID: UInt32, screen: NSScreen)] = []
    private var hudWindow: NSWindow?

    // MARK: - Private — Event Monitors

    private var mouseDownGlobalMonitor: Any?
    private var mouseDragGlobalMonitor: Any?
    private var mouseUpGlobalMonitor: Any?

    // MARK: - Private — Carbon Hotkeys

    private var captureHotKeyRef: EventHotKeyRef?
    private var escHotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    // MARK: - Init

    init() {
        isEnabled = UserDefaults.standard.bool(forKey: "screenCapture.isEnabled")
        registerCarbonHotKey()
    }

    func stopMonitoring() {
        cancelCapture()
        if let ref = eventHandlerRef { RemoveEventHandler(ref) }
        if let ref = captureHotKeyRef { UnregisterEventHotKey(ref) }
        if let ref = escHotKeyRef { UnregisterEventHotKey(ref) }
    }

    // MARK: - Global Shortcut (⌘⌥4)

    private func registerCarbonHotKey() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            screenCaptureHotKeyHandler,
            1, &eventType,
            selfPtr,
            &eventHandlerRef
        )

        // ⌃⌥4 — kVK_ANSI_4 = 21
        let hotKeyID = EventHotKeyID(signature: ScreenCaptureHotKey.signature, id: ScreenCaptureHotKey.captureID)
        let modifiers = UInt32(controlKey | optionKey)
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_4),
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &captureHotKeyRef
        )
        if status == noErr {
            NSLog("%@", "[ScreenCapture] Carbon HotKey ⌘⌥4 registered")
        } else {
            NSLog("%@", "[ScreenCapture] Failed to register ⌘⌥4: \(status)")
        }
    }

    private func registerEscHotKey() {
        guard escHotKeyRef == nil else { return }
        let escID = EventHotKeyID(signature: ScreenCaptureHotKey.signature, id: ScreenCaptureHotKey.escID)
        let escStatus = RegisterEventHotKey(
            UInt32(kVK_Escape),
            0,
            escID,
            GetApplicationEventTarget(),
            0,
            &escHotKeyRef
        )
        if escStatus == noErr {
            NSLog("%@", "[ScreenCapture] Carbon ESC HotKey registered")
        }
    }

    private func unregisterEscHotKey() {
        if let ref = escHotKeyRef {
            UnregisterEventHotKey(ref)
            escHotKeyRef = nil
        }
    }

    // MARK: - Activation

    func startCapture() {
        guard !isCapturing else { return }
        guard checkScreenRecordingPermission() else { return }

        isCapturing = true
        selectionStart = nil
        selectionEnd = nil

        createOverlayWindows()
        registerMouseMonitors()
        registerEscHotKey()
        NSCursor.crosshair.set()
        NSLog("%@", "[ScreenCapture] Selection mode started")
    }

    func cancelCapture() {
        guard isCapturing else { return }
        finishCapture()
        NSCursor.arrow.set()
        NSLog("%@", "[ScreenCapture] Capture cancelled")
    }

    private func finishCapture() {
        isCapturing = false
        selectionStart = nil
        selectionEnd = nil
        unregisterEscHotKey()
        removeMouseMonitors()
        removeOverlayWindows()
        NSCursor.arrow.set()
    }

    // MARK: - Overlay Windows

    private func createOverlayWindows() {
        for screen in NSScreen.screens {
            let frame = screen.frame
            let did = screenID(for: screen)
            let view = ScreenCaptureOverlayView(frame: NSRect(origin: .zero, size: frame.size))

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
        for entry in overlayWindows { entry.window.orderOut(nil) }
        overlayWindows.removeAll()
    }

    private func screenID(for screen: NSScreen) -> UInt32 {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32) ?? 0
    }

    // MARK: - Event Monitors

    private func registerMouseMonitors() {
        mouseDownGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            Task { @MainActor in self?.handleMouseDown() }
        }
        mouseDragGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
            Task { @MainActor in self?.handleMouseDragged() }
        }
        mouseUpGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            Task { @MainActor in self?.handleMouseUp() }
        }
    }

    private func removeMouseMonitors() {
        if let m = mouseDownGlobalMonitor { NSEvent.removeMonitor(m); mouseDownGlobalMonitor = nil }
        if let m = mouseDragGlobalMonitor { NSEvent.removeMonitor(m); mouseDragGlobalMonitor = nil }
        if let m = mouseUpGlobalMonitor { NSEvent.removeMonitor(m); mouseUpGlobalMonitor = nil }
    }

    // MARK: - Mouse Event Handling

    private func handleMouseDown() {
        selectionStart = NSEvent.mouseLocation
        selectionEnd = NSEvent.mouseLocation
        updateOverlayRects()
    }

    private func handleMouseDragged() {
        guard selectionStart != nil else { return }
        selectionEnd = NSEvent.mouseLocation
        updateOverlayRects()
    }

    private func handleMouseUp() {
        guard let start = selectionStart else { return }
        let end = NSEvent.mouseLocation
        let screenRect = normalizedScreenRect(from: start, to: end)

        guard screenRect.width > 5, screenRect.height > 5 else {
            cancelCapture()
            return
        }

        // Hide overlays before capture so they don't appear in screenshot
        for entry in overlayWindows { entry.window.orderOut(nil) }
        NSCursor.arrow.set()

        Task {
            // Wait 2 frames for overlay to fully disappear from screen compositor
            try? await Task.sleep(nanoseconds: 30_000_000)
            await captureAndCopy(screenRect: screenRect)
            finishCapture()
            showCopiedHUD()
        }
    }

    private func updateOverlayRects() {
        guard let start = selectionStart, let end = selectionEnd else { return }
        let screenRect = normalizedScreenRect(from: start, to: end)

        for entry in overlayWindows {
            // Convert screen-global rect to window-local rect
            let windowRect = NSRect(
                x: screenRect.minX - entry.window.frame.minX,
                y: screenRect.minY - entry.window.frame.minY,
                width: screenRect.width,
                height: screenRect.height
            )
            let clipped = windowRect.intersection(entry.view.bounds)
            entry.view.selectionRect = clipped.isEmpty ? nil : clipped
        }
    }

    private func normalizedScreenRect(from a: NSPoint, to b: NSPoint) -> NSRect {
        NSRect(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(b.x - a.x),
            height: abs(b.y - a.y)
        )
    }

    // MARK: - Screen Capture

    private func captureAndCopy(screenRect: NSRect) async {
        do {
            guard let screen = primaryScreen(for: screenRect) else {
                NSLog("[ScreenCapture] No screen found for rect \(screenRect)")
                return
            }

            let displayID = screenID(for: screen)
            let scale = screen.backingScaleFactor

            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let scDisplay = content.displays.first(where: { $0.displayID == displayID }) else {
                NSLog("[ScreenCapture] SCDisplay not found for displayID \(displayID)")
                return
            }

            let filter = SCContentFilter(display: scDisplay, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.width = scDisplay.width
            config.height = scDisplay.height
            config.capturesAudio = false
            config.showsCursor = false

            let fullImage = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )

            // Convert screen-space rect to pixel coordinates in CGImage
            // AppKit: origin = bottom-left; CGImage: origin = top-left → Y-flip required
            let relativeX = screenRect.minX - screen.frame.minX
            let relativeY = screen.frame.maxY - screenRect.maxY

            let pixelX = relativeX * scale
            let pixelY = relativeY * scale
            let pixelW = screenRect.width * scale
            let pixelH = screenRect.height * scale

            let cropRect = CGRect(x: pixelX, y: pixelY, width: pixelW, height: pixelH)

            guard let croppedImage = fullImage.cropping(to: cropRect) else {
                NSLog("[ScreenCapture] CGImage cropping failed for rect \(cropRect)")
                return
            }

            let rep = NSBitmapImageRep(cgImage: croppedImage)
            guard let pngData = rep.representation(using: .png, properties: [:]) else {
                NSLog("[ScreenCapture] PNG encoding failed")
                return
            }

            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setData(pngData, forType: .png)
            NSLog("%@", "[ScreenCapture] Image copied: \(croppedImage.width)×\(croppedImage.height)px")

        } catch {
            NSLog("[ScreenCapture] Capture failed: \(error.localizedDescription)")
        }
    }

    private func primaryScreen(for rect: NSRect) -> NSScreen? {
        NSScreen.screens.max(by: {
            $0.frame.intersection(rect).area < $1.frame.intersection(rect).area
        })
    }

    // MARK: - HUD

    private func showCopiedHUD() {
        let hudW: CGFloat = 220
        let hudH: CGFloat = 44
        guard let screen = NSScreen.main else { return }

        let x = screen.frame.midX - hudW / 2
        let y = screen.frame.minY + 80

        let effectView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: hudW, height: hudH))
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.appearance = NSAppearance(named: .darkAqua)
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 12
        effectView.layer?.masksToBounds = true

        let label = NSTextField(labelWithString: "✓  Copied to clipboard")
        label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.sizeToFit()
        label.frame = NSRect(
            x: (hudW - label.frame.width) / 2,
            y: (hudH - label.frame.height) / 2,
            width: label.frame.width,
            height: label.frame.height
        )
        effectView.addSubview(label)

        let window = NSWindow(
            contentRect: NSRect(x: x, y: y, width: hudW, height: hudH),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = effectView
        window.level = .statusBar
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.animationBehavior = .utilityWindow
        window.orderFrontRegardless()

        hudWindow = window

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.hudWindow?.orderOut(nil)
            self?.hudWindow = nil
        }
    }

    // MARK: - Permissions

    private func checkScreenRecordingPermission() -> Bool {
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Screen Recording Permission Required"
                alert.informativeText = "MacPowerToys needs Screen Recording permission to capture the screen. Please grant permission in System Settings > Privacy & Security > Screen Recording, then restart the app."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Open System Settings")
                alert.addButton(withTitle: "Cancel")
                if alert.runModal() == .alertFirstButtonReturn {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            isEnabled = false
            return false
        }
        return true
    }
}

// MARK: - NSRect area helper

private extension NSRect {
    var area: CGFloat { width * height }
}
