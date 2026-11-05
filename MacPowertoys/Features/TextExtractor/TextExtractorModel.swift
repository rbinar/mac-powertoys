import Foundation
import AppKit
import ScreenCaptureKit
import Vision
import Carbon.HIToolbox

// Global C callback for the Text Extractor hotkey (⌃⌥T)
private func textExtractorHotKeyHandler(nextHandler: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let userData, let event else { return OSStatus(eventNotHandledErr) }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
    guard status == noErr else { return status }
    // Only handle our own hotkey; returning noErr for others would swallow them.
    guard hotKeyID.signature == OSType(0x54585452) else { return OSStatus(eventNotHandledErr) } // "TXTR"

    let model = Unmanaged<TextExtractorModel>.fromOpaque(userData).takeUnretainedValue()
    Task { @MainActor in
        model.toggleSession()
    }
    return noErr
}

// MARK: - OCR text ordering (pure)

/// One recognized text run. `box` is Vision's normalized bounding box (origin bottom-left, y grows up).
struct RecognizedText: Equatable {
    let text: String
    let box: CGRect
}

enum TextExtractorOCR {
    /// Joins runs top-to-bottom; runs on the same line go left-to-right, separated by a space.
    /// Returns nil when nothing readable is left.
    static func join(_ items: [RecognizedText]) -> String? {
        let runs = items.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !runs.isEmpty else { return nil }

        var lines: [[RecognizedText]] = []
        for run in runs.sorted(by: { $0.box.midY > $1.box.midY }) {
            if let last = lines.last, let ref = last.first,
               abs(run.box.midY - ref.box.midY) <= 0.5 * min(run.box.height, ref.box.height) {
                lines[lines.count - 1].append(run)
            } else {
                lines.append([run])
            }
        }
        return lines
            .map { $0.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: " ") }
            .joined(separator: "\n")
    }

    /// Runs Vision on the image. Synchronous and CPU heavy: call off the main thread.
    static func recognize(_ image: CGImage) throws -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["tr-TR", "en-US"]
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = false // use the list above, in order (Turkish first)
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        let items = (request.results ?? []).compactMap { obs -> RecognizedText? in
            guard let top = obs.topCandidates(1).first else { return nil }
            return RecognizedText(text: top.string, box: obs.boundingBox)
        }
        return join(items)
    }
}

// MARK: - Selection overlay

private final class TextExtractorOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Fills one screen; the drag belongs to the screen (window) that received the mouse-down.
private final class TextExtractorSelectionView: NSView {
    /// Called with the selection in this view's coordinates (points, origin bottom-left).
    var onSelect: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?
    private var start: NSPoint?
    private var current: NSPoint?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    private func clamped(_ p: NSPoint) -> NSPoint {
        NSPoint(x: min(max(p.x, bounds.minX), bounds.maxX), y: min(max(p.y, bounds.minY), bounds.maxY))
    }

    private var selection: CGRect? {
        guard let s = start, let c = current else { return nil }
        return CGRect(x: min(s.x, c.x), y: min(s.y, c.y), width: abs(s.x - c.x), height: abs(s.y - c.y))
    }

    override func mouseDown(with event: NSEvent) {
        start = clamped(convert(event.locationInWindow, from: nil))
        current = start
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        current = clamped(convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        current = clamped(convert(event.locationInWindow, from: nil))
        let rect = selection
        start = nil
        current = nil
        needsDisplay = true
        if let rect, rect.width >= 4, rect.height >= 4 { onSelect?(rect) } else { onCancel?() }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.25).setFill()
        bounds.fill()
        guard let r = selection else { return }
        NSGraphicsContext.current?.compositingOperation = .clear
        r.fill()
        NSGraphicsContext.current?.compositingOperation = .sourceOver
        NSColor.white.setStroke()
        let path = NSBezierPath(rect: r)
        path.lineWidth = 1
        path.stroke()
    }
}

// MARK: - Text Extractor Model

@MainActor
final class TextExtractorModel: ObservableObject {
    // MARK: - Settings
    /// Arms the ⌃⌥T shortcut.
    @Published var isEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "textExtractor.isEnabled")
            if isEnabled {
                registerHotKey()
            } else {
                cancelSession()
                unregisterHotKey()
            }
        }
    }

    // MARK: - Runtime State
    @Published private(set) var isActive: Bool = false
    @Published private(set) var lastText: String = ""
    @Published private(set) var permissionMessage: String?

    // MARK: - Private
    private var overlays: [(window: NSWindow, screen: NSScreen)] = []
    private var keyGlobalMonitor: Any?
    private var keyLocalMonitor: Any?
    private var hudWindow: NSWindow?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    // MARK: - Init
    init() {
        installHotKeyHandler()
        isEnabled = UserDefaults.standard.bool(forKey: "textExtractor.isEnabled")
        if isEnabled { registerHotKey() }
    }

    // MARK: - Global Shortcut (⌃⌥T) via Carbon HotKey

    private func installHotKeyHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), textExtractorHotKeyHandler, 1, &eventType, selfPtr, &eventHandlerRef)
    }

    private func registerHotKey() {
        guard hotKeyRef == nil else { return }
        let hotKeyID = EventHotKeyID(signature: OSType(0x54585452), id: 1) // "TXTR"
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_T), UInt32(controlKey | optionKey), hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr { NSLog("[TextExtractor] Failed to register Carbon HotKey: %d", status) }
    }

    private func unregisterHotKey() {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref); hotKeyRef = nil }
    }

    // MARK: - Session

    fileprivate func toggleSession() {
        if isActive { cancelSession() } else { startSession() }
    }

    /// Starts a selection without touching `isEnabled` (palette / button).
    func startSession() {
        guard !isActive else { return }
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            permissionMessage = "Screen Recording permission is required. Enable MacPowerToys in System Settings › Privacy & Security › Screen Recording, then try again."
            return
        }
        permissionMessage = nil
        isActive = true
        hudWindow?.orderOut(nil)
        hudWindow = nil

        for screen in NSScreen.screens {
            let window = TextExtractorOverlayPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.setFrame(screen.frame, display: false)
            window.level = .screenSaver
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            let view = TextExtractorSelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.onSelect = { [weak self] rect in self?.finishSelection(rect, on: screen) }
            view.onCancel = { [weak self] in self?.cancelSession() }
            window.contentView = view
            window.orderFrontRegardless()
            overlays.append((window, screen))
        }
        overlays.first { NSMouseInRect(NSEvent.mouseLocation, $0.screen.frame, false) }?.window.makeKey()
        registerEscMonitors()
    }

    private func registerEscMonitors() {
        keyGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return }
            Task { @MainActor in self?.cancelSession() }
        }
        keyLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            Task { @MainActor in self?.cancelSession() }
            return nil
        }
    }

    private func teardownOverlay() {
        if let m = keyGlobalMonitor { NSEvent.removeMonitor(m); keyGlobalMonitor = nil }
        if let m = keyLocalMonitor { NSEvent.removeMonitor(m); keyLocalMonitor = nil }
        for o in overlays { o.window.orderOut(nil) }
        overlays.removeAll()
        isActive = false
    }

    func cancelSession() {
        guard isActive else { return }
        teardownOverlay()
    }

    // MARK: - Capture + OCR

    /// `rect`: selection in screen-local points, origin bottom-left (AppKit).
    private func finishSelection(_ rect: CGRect, on screen: NSScreen) {
        teardownOverlay()
        let globalRect = rect.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
        // SCStreamConfiguration.sourceRect: display-local points, origin top-left.
        let sourceRect = CGRect(x: rect.minX, y: screen.frame.height - rect.maxY, width: rect.width, height: rect.height)
        let scale = screen.backingScaleFactor
        let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32) ?? 0

        Task { [weak self] in
            // Let the window server drop the overlay before the screenshot.
            try? await Task.sleep(nanoseconds: 80_000_000)
            do {
                let image = try await Self.capture(displayID: displayID, sourceRect: sourceRect, scale: scale)
                let text = try await Task.detached(priority: .userInitiated) { try TextExtractorOCR.recognize(image) }.value
                self?.present(text, near: globalRect, on: screen)
            } catch {
                NSLog("[TextExtractor] Extraction failed: %@", error.localizedDescription)
                self?.present(nil, near: globalRect, on: screen)
            }
        }
    }

    nonisolated private static func capture(displayID: UInt32, sourceRect: CGRect, scale: CGFloat) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw NSError(domain: "TextExtractor", code: 1, userInfo: [NSLocalizedDescriptionKey: "Display \(displayID) not found"])
        }
        // Leave out our own windows (selection overlay, menu-bar popover).
        let ownApp = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ownApp, exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.sourceRect = sourceRect
        config.width = max(1, Int((sourceRect.width * scale).rounded()))
        config.height = max(1, Int((sourceRect.height * scale).rounded()))
        config.showsCursor = false
        config.capturesAudio = false
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    private func present(_ text: String?, near rect: CGRect, on screen: NSScreen) {
        if let text {
            lastText = text
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            showHUD("Copied \(text.count) characters", near: rect, on: screen)
        } else {
            showHUD("No text found", near: rect, on: screen)
        }
    }

    func copyLastText() {
        guard !lastText.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastText, forType: .string)
    }

    // MARK: - HUD

    private func showHUD(_ text: String, near rect: CGRect, on screen: NSScreen) {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.sizeToFit()

        let hudW = label.frame.width + 32
        let hudH: CGFloat = 36
        let effect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: hudW, height: hudH))
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.appearance = NSAppearance(named: .darkAqua)
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        label.frame.origin = NSPoint(x: 16, y: (hudH - label.frame.height) / 2)
        effect.addSubview(label)

        // Just below the selection, above it when there is no room; kept inside the visible screen area.
        let vis = screen.visibleFrame
        var y = rect.minY - hudH - 8
        if y < vis.minY { y = min(rect.maxY + 8, vis.maxY - hudH) }
        let x = min(max(rect.midX - hudW / 2, vis.minX), vis.maxX - hudW)

        let window = NSWindow(contentRect: NSRect(x: x, y: y, width: hudW, height: hudH), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = effect
        window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.animationBehavior = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? .none : .utilityWindow
        window.orderFrontRegardless()

        hudWindow?.orderOut(nil)
        hudWindow = window
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self, weak window] in
            window?.orderOut(nil)
            if self?.hudWindow === window { self?.hudWindow = nil }
        }
    }

    // MARK: - Monitoring

    func stopMonitoring() {
        cancelSession()
        hudWindow?.orderOut(nil)
        hudWindow = nil
        unregisterHotKey()
        if let ref = eventHandlerRef { RemoveEventHandler(ref); eventHandlerRef = nil }
    }
}
