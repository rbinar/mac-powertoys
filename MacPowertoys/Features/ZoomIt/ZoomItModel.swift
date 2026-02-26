import Foundation
import AppKit
import ScreenCaptureKit
import Carbon.HIToolbox
import VideoToolbox

// Global C callback for ZoomIt hotkeys
private func zoomItHotKeyHandler(nextHandler: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let userData, let event else { return OSStatus(eventNotHandledErr) }
    let model = Unmanaged<ZoomItModel>.fromOpaque(userData).takeUnretainedValue()
    
    var hotKeyID = EventHotKeyID()
    GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
    
    print("[ZoomIt] Hotkey pressed with ID: \(hotKeyID.id)")
    
    var handled = true
    Task { @MainActor in
        switch hotKeyID.id {
        case 4: // ⌃⌥Z toggle Screen Zoom
            print("[ZoomIt] Toggle Screen Zoom")
            if model.isZooming {
                model.isEnabled = false
            } else {
                model.isEnabled = true
            }
        case 5: // ⌃⌥L toggle Live Zoom
            print("[ZoomIt] Toggle Live Zoom")
            if model.isLiveZooming {
                model.liveZoomEnabled = false
            } else {
                model.liveZoomEnabled = true
            }
        case 6, 3: // ESC close (3 is ScreenRuler's ESC ID, we catch it too just in case)
            print("[ZoomIt] ESC pressed")
            if model.isZooming || model.isLiveZooming {
                model.isEnabled = false
                model.liveZoomEnabled = false
            }
        default:
            handled = false
            break
        }
    }
    
    return handled ? noErr : OSStatus(eventNotHandledErr)
}

@MainActor
final class ZoomItModel: ObservableObject {
    // MARK: - Settings
    @Published var isEnabled: Bool = false {
        didSet {
            if isEnabled {
                if !isZooming && !isLiveZooming {
                    activateScreenZoom()
                }
            } else {
                if isZooming || isLiveZooming {
                    deactivate()
                }
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
    @Published var liveZoomEnabled: Bool = false {
        didSet {
            if liveZoomEnabled {
                if !isLiveZooming {
                    activateLiveZoom()
                }
            } else {
                if isLiveZooming {
                    deactivate()
                }
            }
        }
    }
    
    // MARK: - Runtime State
    @Published private(set) var isZooming: Bool = false
    @Published private(set) var isLiveZooming: Bool = false
    
    // MARK: - Private
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
    
    init() {
        print("[ZoomIt] ZoomItModel initialized")
        registerCarbonHotKeys()
    }
    
    func stopMonitoring() {
        deactivate()
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
        if let zoomHotKeyRef { UnregisterEventHotKey(zoomHotKeyRef) }
        if let liveZoomHotKeyRef { UnregisterEventHotKey(liveZoomHotKeyRef) }
        if let escHotKeyRef { UnregisterEventHotKey(escHotKeyRef) }
    }
    
    // MARK: - Global Shortcuts
    
    private func registerCarbonHotKeys() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), zoomItHotKeyHandler, 1, &eventType, selfPtr, &eventHandlerRef)
        
        let modifiers: UInt32 = UInt32(controlKey | optionKey)
        
        // ⌃⌥Z (keyCode kVK_ANSI_Z = 6)
        var zoomHotKeyID = EventHotKeyID(signature: OSType(0x5A4F4F4D), id: 4) // "ZOOM"
        RegisterEventHotKey(UInt32(kVK_ANSI_Z), modifiers, zoomHotKeyID, GetApplicationEventTarget(), 0, &zoomHotKeyRef)
        
        // ⌃⌥L (keyCode kVK_ANSI_L = 37)
        var liveZoomHotKeyID = EventHotKeyID(signature: OSType(0x5A4F4F4D), id: 5)
        RegisterEventHotKey(UInt32(kVK_ANSI_L), modifiers, liveZoomHotKeyID, GetApplicationEventTarget(), 0, &liveZoomHotKeyRef)
        
        // ESC (no modifiers) to close
        var escHotKeyID = EventHotKeyID(signature: OSType(0x5A4F4F4D), id: 6)
        RegisterEventHotKey(UInt32(kVK_Escape), 0, escHotKeyID, GetApplicationEventTarget(), 0, &escHotKeyRef)
    }
    
    // MARK: - Activation
    
    func activateScreenZoom() {
        print("[ZoomIt] activateScreenZoom called. isEnabled: \(isEnabled), isZooming: \(isZooming), isLiveZooming: \(isLiveZooming)")
        if isLiveZooming { deactivate() }
        guard !isZooming else { return }
        
        if !checkScreenRecordingPermission() { 
            print("[ZoomIt] Screen recording permission denied")
            isEnabled = false
            return 
        }
        
        isZooming = true
        isEnabled = true
        liveZoomEnabled = false
        print("[ZoomIt] Starting screen capture...")
        
        Task {
            await captureScreensAsync()
            print("[ZoomIt] Screen capture finished. Creating overlay windows...")
            createOverlayWindows(isLive: false)
            registerActiveMonitors()
            updateZoomCenter(NSEvent.mouseLocation)
            print("[ZoomIt] Overlay windows created and monitors registered.")
        }
    }
    
    func activateLiveZoom() {
        print("[ZoomIt] activateLiveZoom called. isEnabled: \(isEnabled), liveZoomEnabled: \(liveZoomEnabled), isZooming: \(isZooming), isLiveZooming: \(isLiveZooming)")
        if isZooming { deactivate() }
        guard !isLiveZooming else { return }
        
        if !checkScreenRecordingPermission() { 
            print("[ZoomIt] Screen recording permission denied")
            liveZoomEnabled = false
            return 
        }
        
        isLiveZooming = true
        isEnabled = true
        liveZoomEnabled = true
        print("[ZoomIt] Starting live streams...")
        
        Task {
            createOverlayWindows(isLive: true)
            await startLiveStreams()
            registerActiveMonitors()
            updateZoomCenter(NSEvent.mouseLocation)
            print("[ZoomIt] Live zoom overlay windows created and streams started.")
        }
    }
    
    func deactivate() {
        guard isZooming || isLiveZooming else { return }
        let wasZooming = isZooming
        isZooming = false
        isLiveZooming = false
        isEnabled = false
        liveZoomEnabled = false
        
        removeActiveMonitors()
        removeOverlayWindows(wasZooming: wasZooming)
        stopLiveStreams()
        capturedScreens.removeAll()
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
            isEnabled = false
            return false
        }
        return true
    }
    
    // MARK: - Screen Capture
    
    private func captureScreensAsync() async {
        capturedScreens.removeAll()
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            print("[ZoomIt] Found \(content.displays.count) displays")
            
            for display in content.displays {
                let filter = SCContentFilter(display: display, excludingWindows: [])
                let config = SCStreamConfiguration()
                config.width = display.width
                config.height = display.height
                config.capturesAudio = false
                config.showsCursor = false
                
                print("[ZoomIt] Capturing display \(display.displayID) (\(display.width)x\(display.height))...")
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                capturedScreens[display.displayID] = image
                print("[ZoomIt] Captured image for display \(display.displayID): \(image.width)x\(image.height)")
            }
        } catch {
            print("[ZoomIt] Screen capture failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Live Stream
    
    private func startLiveStreams() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            print("[ZoomIt] Live stream found \(content.displays.count) displays")
            
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
                
                print("[ZoomIt] Starting stream for display \(display.displayID)...")
                let stream = SCStream(filter: filter, configuration: config, delegate: nil)
                let output = StreamOutput(displayID: display.displayID, model: self)
                
                try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: .main)
                try await stream.startCapture()
                
                streams[display.displayID] = stream
                streamOutputs[display.displayID] = output
                print("[ZoomIt] Stream started for display \(display.displayID)")
            }
        } catch {
            print("[ZoomIt] Live stream failed: \(error.localizedDescription)")
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
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .scrollWheel]
        
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
        if event.type == .mouseMoved {
            updateZoomCenter(NSEvent.mouseLocation)
        } else if event.type == .scrollWheel {
            // Adjust zoom level
            let delta = event.scrollingDeltaY
            if delta != 0 {
                let newLevel = max(1.25, min(4.0, magnificationLevel + (delta > 0 ? 0.1 : -0.1)))
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
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // Convert CVImageBuffer to CGImage efficiently
        var cgImage: CGImage?
        VTCreateCGImageFromCVPixelBuffer(imageBuffer, options: nil, imageOut: &cgImage)
        
        if let cgImage = cgImage {
            Task { @MainActor in
                model?.updateLiveImage(cgImage, for: displayID)
            }
        }
    }
}
