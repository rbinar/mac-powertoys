import Foundation
import AppKit
import ScreenCaptureKit
import Carbon.HIToolbox
import VideoToolbox

private enum ZoomItHotKey {
    static let signature = OSType(0x5A4F4F4D) // "ZOOM"
    static let toggleScreenZoom: UInt32 = 4
    static let toggleLiveZoom: UInt32 = 5
    static let close: UInt32 = 6
}

private let zoomIncrement = 0.1

// Global C callback for ZoomIt hotkeys
private func zoomItHotKeyHandler(nextHandler: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let userData, let event else { return OSStatus(eventNotHandledErr) }
    let model = Unmanaged<ZoomItModel>.fromOpaque(userData).takeUnretainedValue()
    
    var hotKeyID = EventHotKeyID()
    GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
    
    guard hotKeyID.signature == ZoomItHotKey.signature else { return OSStatus(eventNotHandledErr) }
    NSLog("%@", "[ZoomIt] Hotkey pressed with ID: \(hotKeyID.id)")
    
    switch hotKeyID.id {
    case ZoomItHotKey.toggleScreenZoom, ZoomItHotKey.toggleLiveZoom, ZoomItHotKey.close:
        Task { @MainActor in
            switch hotKeyID.id {
            case ZoomItHotKey.toggleScreenZoom: // ⌃⌥Z toggle Screen Zoom
                NSLog("%@", "[ZoomIt] Toggle Screen Zoom")
                if model.isZooming { model.deactivate() } else { model.activateScreenZoom() }
            case ZoomItHotKey.toggleLiveZoom: // ⌃⌥L toggle Live Zoom
                NSLog("%@", "[ZoomIt] Toggle Live Zoom")
                if model.isLiveZooming { model.deactivate() } else { model.activateLiveZoom() }
            case ZoomItHotKey.close: // ESC close
                NSLog("%@", "[ZoomIt] ESC pressed")
                model.deactivate()
            default:
                break
            }
        }
        return noErr
    default:
        return OSStatus(eventNotHandledErr)
    }
}

@MainActor
final class ZoomItModel: ObservableObject {
    // MARK: - Settings
    /// Arms the ⌃⌥Z / ⌃⌥L shortcuts. Zoom itself only starts from a shortcut.
    @Published var isEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "zoomIt.isEnabled")
            if isEnabled {
                registerZoomHotKeys()
            } else {
                deactivate()
                unregisterZoomHotKeys()
            }
        }
    }
    @Published var magnificationLevel: Double = 2.0 {
        didSet {
            updateZoomLevel()
        }
    }
    @Published var animateZoom: Bool = true {
        didSet {
            for entry in overlayWindows {
                entry.view.animateZoom = animateZoom
            }
        }
    }
    
    // MARK: - Runtime State
    @Published private(set) var isZooming: Bool = false
    @Published private(set) var isLiveZooming: Bool = false
    
    // MARK: - Private
    /// Bumped on every activate/deactivate so in-flight activation tasks can detect they are stale.
    private var activationGeneration = 0
    private var exitHintWindow: NSWindow?
    private var overlayWindows: [(window: NSWindow, view: ZoomItOverlayView, displayID: UInt32, screen: NSScreen)] = []
    private var capturedScreens: [UInt32: CGImage] = [:]
    
    // Monitors
    private var mouseMovedGlobalMonitor: Any?
    private var mouseMovedLocalMonitor: Any?
    private var scrollGlobalMonitor: Any?
    private var scrollLocalMonitor: Any?
    
    // Carbon hotkey
    private var zoomHotKeyRef: EventHotKeyRef?
    private var liveZoomHotKeyRef: EventHotKeyRef?
    private var escHotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    
    // Live Zoom Stream
    private var streams: [UInt32: SCStream] = [:]
    private var streamOutputs: [UInt32: StreamOutput] = [:]
    private let frameQueue = DispatchQueue(label: "com.rbinar.MacPowerToys.zoomit.frames")
    
    // Display configuration changes
    private var screenParametersObserver: NSObjectProtocol?
    
    init() {
        NSLog("%@", "[ZoomIt] ZoomItModel initialized")
        installHotKeyHandler()
        isEnabled = UserDefaults.standard.bool(forKey: "zoomIt.isEnabled")
        if isEnabled { registerZoomHotKeys() }
    }
    
    func stopMonitoring() {
        deactivate()
        removeScreenParametersObserver()
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
        unregisterZoomHotKeys()
        if let escHotKeyRef { UnregisterEventHotKey(escHotKeyRef) }
    }
    
    // MARK: - Global Shortcuts
    
    private func installHotKeyHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), zoomItHotKeyHandler, 1, &eventType, selfPtr, &eventHandlerRef)
    }

    private func registerZoomHotKeys() {
        guard zoomHotKeyRef == nil else { return }
        let modifiers: UInt32 = UInt32(controlKey | optionKey)
        
        // ⌃⌥Z (keyCode kVK_ANSI_Z = 6)
        var zoomHotKeyID = EventHotKeyID(signature: ZoomItHotKey.signature, id: ZoomItHotKey.toggleScreenZoom) // "ZOOM"
        RegisterEventHotKey(UInt32(kVK_ANSI_Z), modifiers, zoomHotKeyID, GetApplicationEventTarget(), 0, &zoomHotKeyRef)
        
        // ⌃⌥L (keyCode kVK_ANSI_L = 37)
        var liveZoomHotKeyID = EventHotKeyID(signature: ZoomItHotKey.signature, id: ZoomItHotKey.toggleLiveZoom)
        RegisterEventHotKey(UInt32(kVK_ANSI_L), modifiers, liveZoomHotKeyID, GetApplicationEventTarget(), 0, &liveZoomHotKeyRef)
    }

    private func unregisterZoomHotKeys() {
        if let ref = zoomHotKeyRef { UnregisterEventHotKey(ref); zoomHotKeyRef = nil }
        if let ref = liveZoomHotKeyRef { UnregisterEventHotKey(ref); liveZoomHotKeyRef = nil }
    }

    private func registerEscHotKey() {
        guard escHotKeyRef == nil else { return }
        var escHotKeyID = EventHotKeyID(signature: ZoomItHotKey.signature, id: ZoomItHotKey.close)
        RegisterEventHotKey(UInt32(kVK_Escape), 0, escHotKeyID, GetApplicationEventTarget(), 0, &escHotKeyRef)
    }

    private func unregisterEscHotKey() {
        if let ref = escHotKeyRef {
            UnregisterEventHotKey(ref)
            escHotKeyRef = nil
        }
    }

    // MARK: - Activation
    
    func activateScreenZoom() {
        NSLog("%@", "[ZoomIt] activateScreenZoom called. isEnabled: \(isEnabled), isZooming: \(isZooming), isLiveZooming: \(isLiveZooming)")
        if isLiveZooming { deactivate() }
        guard !isZooming else { return }
        
        if !checkScreenRecordingPermission() { 
            NSLog("%@", "[ZoomIt] Screen recording permission denied")
            return 
        }
        
        isZooming = true
        addScreenParametersObserver()
        activationGeneration += 1
        let generation = activationGeneration
        NSLog("%@", "[ZoomIt] Starting screen capture...")
        
        Task {
            await captureScreensAsync()
            // Deactivated (or re-activated) while capturing: don't create orphan overlays.
            guard generation == activationGeneration else { return }
            NSLog("%@", "[ZoomIt] Screen capture finished. Creating overlay windows...")
            createOverlayWindows(isLive: false)
            registerActiveMonitors()
            registerEscHotKey()
            updateZoomCenter(NSEvent.mouseLocation)
            showExitHintHUD("ESC or ⌃⌥Z to exit")
            NSLog("%@", "[ZoomIt] Overlay windows created and monitors registered.")
        }
    }
    
    func activateLiveZoom() {
        NSLog("%@", "[ZoomIt] activateLiveZoom called. isEnabled: \(isEnabled), isZooming: \(isZooming), isLiveZooming: \(isLiveZooming)")
        if isZooming { deactivate() }
        guard !isLiveZooming else { return }
        
        if !checkScreenRecordingPermission() { 
            NSLog("%@", "[ZoomIt] Screen recording permission denied")
            return 
        }
        
        isLiveZooming = true
        addScreenParametersObserver()
        activationGeneration += 1
        let generation = activationGeneration
        NSLog("%@", "[ZoomIt] Starting live streams...")
        
        Task {
            createOverlayWindows(isLive: true)
            await startLiveStreams(generation: generation)
            guard generation == activationGeneration else { return }
            registerActiveMonitors()
            registerEscHotKey()
            updateZoomCenter(NSEvent.mouseLocation)
            showExitHintHUD("ESC or ⌃⌥L to exit")
            NSLog("%@", "[ZoomIt] Live zoom overlay windows created and streams started.")
        }
    }
    
    private func showExitHintHUD(_ text: String) {
        let hudW: CGFloat = 240
        let hudH: CGFloat = 40
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main else { return }

        let effectView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: hudW, height: hudH))
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.appearance = NSAppearance(named: .darkAqua)
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 12
        effectView.layer?.masksToBounds = true

        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.sizeToFit()
        label.frame = NSRect(
            x: (hudW - label.frame.width) / 2,
            y: (hudH - label.frame.height) / 2,
            width: label.frame.width,
            height: label.frame.height
        )
        effectView.addSubview(label)

        let window = NSWindow(
            contentRect: NSRect(x: screen.frame.midX - hudW / 2, y: screen.frame.maxY - hudH - 60, width: hudW, height: hudH),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = effectView
        window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.animationBehavior = .utilityWindow
        window.orderFrontRegardless()

        exitHintWindow?.orderOut(nil)
        exitHintWindow = window

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self, weak window] in
            window?.orderOut(nil)
            if self?.exitHintWindow === window {
                self?.exitHintWindow = nil
            }
        }
    }

    func deactivate() {
        guard isZooming || isLiveZooming else { return }
        activationGeneration += 1
        let wasZooming = isZooming
        isZooming = false
        isLiveZooming = false

        removeScreenParametersObserver()
        unregisterEscHotKey()
        removeActiveMonitors()
        removeOverlayWindows(wasZooming: wasZooming)
        stopLiveStreams()
        capturedScreens.removeAll()
    }
    
    // MARK: - Display Changes
    
    private func addScreenParametersObserver() {
        removeScreenParametersObserver()
        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.rebuildForScreenChange() }
        }
    }
    
    private func removeScreenParametersObserver() {
        if let screenParametersObserver {
            NotificationCenter.default.removeObserver(screenParametersObserver)
            self.screenParametersObserver = nil
        }
    }
    
    private func rebuildForScreenChange() {
        guard isZooming || isLiveZooming else { return }
        NSLog("%@", "[ZoomIt] Screen parameters changed, rebuilding overlays")
        let wasLive = isLiveZooming
        deactivate()
        if wasLive {
            activateLiveZoom()
        } else {
            activateScreenZoom()
        }
    }
    
    private func checkScreenRecordingPermission() -> Bool {
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Screen Recording Permission Required"
                alert.informativeText = "MacPowerToys needs Screen Recording permission to zoom the screen. Please grant permission in System Settings > Privacy & Security > Screen Recording, then restart the app."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Open System Settings")
                alert.addButton(withTitle: "Cancel")
                if alert.runModal() == .alertFirstButtonReturn {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            return false
        }
        return true
    }
    
    // MARK: - Screen Capture
    
    private func captureScreensAsync() async {
        capturedScreens.removeAll()
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            NSLog("%@", "[ZoomIt] Found \(content.displays.count) displays")
            
            for display in content.displays {
                let filter = SCContentFilter(display: display, excludingWindows: [])
                let config = SCStreamConfiguration()
                config.width = display.width
                config.height = display.height
                config.capturesAudio = false
                config.showsCursor = false
                
                NSLog("%@", "[ZoomIt] Capturing display \(display.displayID) (\(display.width)x\(display.height))...")
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                capturedScreens[display.displayID] = image
                NSLog("%@", "[ZoomIt] Captured image for display \(display.displayID): \(image.width)x\(image.height)")
            }
        } catch {
            NSLog("%@", "[ZoomIt] Screen capture failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Live Stream
    
    private func startLiveStreams(generation: Int) async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            NSLog("%@", "[ZoomIt] Live stream found \(content.displays.count) displays")
            
            // Exclude our own overlay windows
            let ownWindowIDs = Set(overlayWindows.map { $0.window.windowNumber })
            let excludedWindows = content.windows.filter { ownWindowIDs.contains(Int($0.windowID)) }
            
            for display in content.displays {
                let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
                let config = SCStreamConfiguration()
                config.width = display.width
                config.height = display.height
                config.capturesAudio = false
                config.showsCursor = false
                config.minimumFrameInterval = CMTime(value: 1, timescale: 60) // ~60 fps for smoother live zoom
                config.queueDepth = 3 // Reduce latency
                
                NSLog("%@", "[ZoomIt] Starting stream for display \(display.displayID)...")
                let stream = SCStream(filter: filter, configuration: config, delegate: nil)
                let output = StreamOutput(displayID: display.displayID, model: self)
                
                try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: frameQueue)
                try await stream.startCapture()
                guard generation == activationGeneration else {
                    // Deactivated while starting: don't leave this stream running untracked.
                    try? await stream.stopCapture()
                    return
                }
                
                streams[display.displayID] = stream
                streamOutputs[display.displayID] = output
                NSLog("%@", "[ZoomIt] Stream started for display \(display.displayID)")
            }
        } catch {
            NSLog("%@", "[ZoomIt] Live stream failed: \(error.localizedDescription)")
        }
    }
    
    private func stopLiveStreams() {
        for stream in streams.values {
            stream.stopCapture()
        }
        streams.removeAll()
        streamOutputs.removeAll()
    }
    
    func updateLiveImage(_ image: CGImage, for displayID: UInt32) {
        guard isLiveZooming else { return }
        if let entry = overlayWindows.first(where: { $0.displayID == displayID }) {
            entry.view.updateImage(image)
        }
    }
    
    // MARK: - Overlay Windows
    
    private func createOverlayWindows(isLive: Bool) {
        for screen in NSScreen.screens {
            let frame = screen.frame
            let did = screenID(for: screen)
            let view = ZoomItOverlayView(frame: NSRect(origin: .zero, size: frame.size))
            view.animateZoom = animateZoom
            view.zoomLevel = magnificationLevel
            
            if !isLive, let image = capturedScreens[did] {
                view.updateImage(image)
            }
            
            let window = NSWindow(
                contentRect: frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: screen
            )
            // With `screen:` set, contentRect is taken relative to that screen's origin,
            // which double-offsets non-main displays; pin the global frame explicitly.
            window.setFrame(frame, display: false)
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
        
        // Hide cursor during static zoom
        if !isLive {
            NSCursor.hide()
        }
    }
    
    private func removeOverlayWindows(wasZooming: Bool) {
        for entry in overlayWindows {
            entry.window.orderOut(nil)
        }
        overlayWindows.removeAll()
        
        if wasZooming {
            NSCursor.unhide()
        }
    }
    
    private func screenID(for screen: NSScreen) -> UInt32 {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32) ?? 0
    }
    
    // MARK: - Monitors
    
    private func registerActiveMonitors() {
        // keyDown: ESC fallback that doesn't depend on the Carbon ESC hotkey, which can be
        // claimed by another feature's registration.
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .scrollWheel, .keyDown]
        
        mouseMovedGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handleEvent(event)
        }
        mouseMovedLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handleEvent(event)
            return event
        }
    }
    
    private func removeActiveMonitors() {
        if let m = mouseMovedGlobalMonitor { NSEvent.removeMonitor(m); mouseMovedGlobalMonitor = nil }
        if let m = mouseMovedLocalMonitor { NSEvent.removeMonitor(m); mouseMovedLocalMonitor = nil }
    }
    
    private func handleEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            if event.keyCode == UInt16(kVK_Escape) { deactivate() }
        } else if event.type == .mouseMoved {
            updateZoomCenter(NSEvent.mouseLocation)
        } else if event.type == .scrollWheel {
            // Adjust zoom level
            let delta = event.scrollingDeltaY
            if delta != 0 {
                let newLevel = max(1.25, min(4.0, magnificationLevel + (delta > 0 ? zoomIncrement : -zoomIncrement)))
                magnificationLevel = newLevel
            }
        }
    }
    
    private func updateZoomCenter(_ location: NSPoint) {
        for entry in overlayWindows {
            // Convert global screen coordinates to window-local coordinates
            let windowLoc = entry.window.convertPoint(fromScreen: location)
            entry.view.updateCenter(windowLoc)
        }
    }
    
    private func updateZoomLevel() {
        for entry in overlayWindows {
            entry.view.zoomLevel = magnificationLevel
        }
    }
}

// MARK: - Stream Output Delegate

private class StreamOutput: NSObject, SCStreamOutput {
    let displayID: UInt32
    weak var model: ZoomItModel?
    
    init(displayID: UInt32, model: ZoomItModel) {
        self.displayID = displayID
        self.model = model
    }
    
    // Runs on the model's dedicated frame queue (not the main thread).
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // Convert CVImageBuffer to CGImage efficiently
        var cgImage: CGImage?
        VTCreateCGImageFromCVPixelBuffer(imageBuffer, options: nil, imageOut: &cgImage)
        
        if let cgImage = cgImage {
            let model = self.model
            let displayID = self.displayID
            Task { @MainActor in
                model?.updateLiveImage(cgImage, for: displayID)
            }
        }
    }
}
