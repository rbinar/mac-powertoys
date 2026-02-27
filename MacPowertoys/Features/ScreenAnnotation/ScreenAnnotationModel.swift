import Foundation
import AppKit
import Carbon.HIToolbox

// MARK: - Enums & Data Types

enum AnnotationTool: String, CaseIterable {
    case freehand = "Freehand"
    case line = "Line"
    case arrow = "Arrow"
    case rectangle = "Rectangle"
    case ellipse = "Ellipse"
    case text = "Text"
}

struct Annotation {
    let tool: AnnotationTool
    var points: [CGPoint]
    var color: NSColor
    var lineWidth: CGFloat
    var text: String?
    var isFilled: Bool
}

// MARK: - Preset Colors

let annotationPresetColors: [NSColor] = [
    .systemRed,
    .systemBlue,
    .systemGreen,
    .systemYellow,
    .systemOrange,
    .white,
    .black,
    .systemPurple,
]

// MARK: - Keyable Window (borderless windows can't become key by default)

private class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

// MARK: - Hotkey Config

private struct AnnotationHotKey {
    static let signature = OSType(0x414E4F54) // "ANOT"
    static let toggleID: UInt32 = 1
    static let escID: UInt32 = 2
}

// MARK: - Global C callback

private func annotationHotKeyHandler(nextHandler: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let userData, let event else { return OSStatus(eventNotHandledErr) }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
    guard status == noErr else { return status }

    let model = Unmanaged<ScreenAnnotationModel>.fromOpaque(userData).takeUnretainedValue()

    Task { @MainActor in
        switch hotKeyID.id {
        case AnnotationHotKey.toggleID: // ⌃⌥D toggle
            model.isEnabled.toggle()
        case AnnotationHotKey.escID: // ESC close
            if model.isEnabled {
                model.isEnabled = false
            }
        default:
            break
        }
    }
    return noErr
}

// MARK: - Screen Annotation Model

@MainActor
final class ScreenAnnotationModel: ObservableObject {
    // MARK: - Settings
    @Published var isEnabled: Bool = false {
        didSet {
            if isEnabled { activate() } else { deactivate() }
        }
    }
    @Published var defaultColor: NSColor = .systemRed
    @Published var defaultLineWidth: CGFloat = 4.0
    @Published var dimBackground: Bool = true

    // MARK: - Runtime State
    @Published private(set) var isActive: Bool = false
    @Published var currentTool: AnnotationTool = .freehand
    @Published var currentColor: NSColor = .systemRed
    @Published var currentLineWidth: CGFloat = 4.0

    // MARK: - Drawing State
    var annotations: [Annotation] = []
    var currentAnnotation: Annotation? = nil
    var selectedAnnotationIndex: Int? = nil
    private var dragOffset: CGPoint = .zero
    private var isDraggingSelection: Bool = false

    // MARK: - Private
    private var overlayWindows: [(window: NSWindow, view: ScreenAnnotationOverlayView, displayID: UInt32, screen: NSScreen)] = []
    private var toolbarWindow: NSWindow?
    private var toolbarView: ScreenAnnotationToolbarView?
    private var textInputWindow: NSWindow?
    private var pendingTextPoint: NSPoint = .zero
    private var elevatedWindows: [NSWindow] = []

    // Event monitors
    private var mouseDownGlobalMonitor: Any?
    private var mouseDownLocalMonitor: Any?
    private var mouseDragGlobalMonitor: Any?
    private var mouseDragLocalMonitor: Any?
    private var mouseUpGlobalMonitor: Any?
    private var mouseUpLocalMonitor: Any?
    private var keyGlobalMonitor: Any?
    private var keyLocalMonitor: Any?
    private var rightMouseDownGlobalMonitor: Any?
    private var rightMouseDownLocalMonitor: Any?

    // Carbon hotkey
    private var hotKeyRef: EventHotKeyRef?
    private var escHotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    init() {
        registerCarbonHotKey()
    }

    // MARK: - Global Shortcut (⌃⌥D) via Carbon HotKey

    private func registerCarbonHotKey() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), annotationHotKeyHandler, 1, &eventType, selfPtr, &eventHandlerRef)

        // ⌃⌥D (keyCode kVK_ANSI_D = 2)
        let hotKeyID = EventHotKeyID(signature: AnnotationHotKey.signature, id: AnnotationHotKey.toggleID)
        let modifiers: UInt32 = UInt32(controlKey | optionKey)
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_D), modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status == noErr {
            print("[ScreenAnnotation] Carbon HotKey ⌃⌥D registered successfully")
        } else {
            print("[ScreenAnnotation] Failed to register Carbon HotKey: \(status)")
        }
    }

    private func registerEscHotKey() {
        guard escHotKeyRef == nil else { return }
        let escHotKeyID = EventHotKeyID(signature: AnnotationHotKey.signature, id: AnnotationHotKey.escID)
        let escStatus = RegisterEventHotKey(UInt32(kVK_Escape), 0, escHotKeyID, GetApplicationEventTarget(), 0, &escHotKeyRef)
        if escStatus == noErr {
            print("[ScreenAnnotation] Carbon HotKey ESC registered successfully")
        } else {
            print("[ScreenAnnotation] Failed to register ESC HotKey: \(escStatus)")
        }
    }

    private func unregisterEscHotKey() {
        if let ref = escHotKeyRef {
            UnregisterEventHotKey(ref)
            escHotKeyRef = nil
        }
    }

    // MARK: - Activation

    private func activate() {
        guard !isActive else { return }
        isActive = true
        currentColor = defaultColor
        currentLineWidth = defaultLineWidth
        annotations.removeAll()
        currentAnnotation = nil
        selectedAnnotationIndex = nil

        createOverlayWindows()
        showToolbar()
        elevateAppWindows()
        registerActiveMonitors()
        registerEscHotKey()
    }

    private func deactivate() {
        guard isActive else { return }
        isActive = false
        unregisterEscHotKey()
        removeActiveMonitors()
        dismissTextInput()
        hideToolbar()
        removeOverlayWindows()
        restoreAppWindows()
        annotations.removeAll()
        currentAnnotation = nil
    }

    private func elevateAppWindows() {
        for window in NSApplication.shared.windows {
            if overlayWindows.contains(where: { $0.window === window }) { continue }
            if window === toolbarWindow { continue }
            if window === textInputWindow { continue }
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

    // MARK: - Overlay Windows

    private func screenID(for screen: NSScreen) -> UInt32 {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32) ?? 0
    }

    private func createOverlayWindows() {
        for screen in NSScreen.screens {
            let frame = screen.frame
            let did = screenID(for: screen)
            let view = ScreenAnnotationOverlayView(frame: NSRect(origin: .zero, size: frame.size))
            view.dimBackground = dimBackground

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
            window.ignoresMouseEvents = true // We use event monitors instead
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

    private func updateAllOverlays() {
        for entry in overlayWindows {
            entry.view.annotations = annotations
            entry.view.currentAnnotation = currentAnnotation
            entry.view.selectedAnnotationIndex = selectedAnnotationIndex
            entry.view.setNeedsDisplay(entry.view.bounds)
        }
        toolbarView?.hasSelection = selectedAnnotationIndex != nil
    }

    // MARK: - Toolbar

    private func showToolbar() {
        guard let mainScreen = NSScreen.main else { return }

        let toolbarWidth = ScreenAnnotationToolbarView.computeWidth()
        let toolbarHeight: CGFloat = 48
        let x = mainScreen.frame.midX - toolbarWidth / 2
        let y = mainScreen.frame.maxY - 80

        let view = ScreenAnnotationToolbarView(
            frame: NSRect(x: 0, y: 0, width: toolbarWidth, height: toolbarHeight),
            onToolChange: { [weak self] tool in
                Task { @MainActor in self?.currentTool = tool }
            },
            onColorChange: { [weak self] color in
                Task { @MainActor in self?.currentColor = color }
            },
            onLineWidthChange: { [weak self] width in
                Task { @MainActor in self?.currentLineWidth = width }
            },
            onUndo: { [weak self] in
                Task { @MainActor in self?.undo() }
            },
            onDeleteSelected: { [weak self] in
                Task { @MainActor in self?.deleteSelected() }
            },
            onClearAll: { [weak self] in
                Task { @MainActor in self?.clearAll() }
            },
            onSave: { [weak self] in
                Task { @MainActor in self?.saveScreenshot() }
            },
            onClose: { [weak self] in
                Task { @MainActor in self?.isEnabled = false }
            }
        )
        view.currentTool = currentTool
        view.currentColor = currentColor
        view.currentLineWidth = currentLineWidth

        // Frosted glass background
        let effectView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: toolbarWidth, height: toolbarHeight))
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.appearance = NSAppearance(named: .darkAqua)
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 14
        effectView.layer?.masksToBounds = true
        effectView.addSubview(view)

        let window = NSWindow(
            contentRect: NSRect(x: x, y: y, width: toolbarWidth, height: toolbarHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = effectView
        window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.animationBehavior = .utilityWindow
        window.orderFrontRegardless()

        toolbarWindow = window
        toolbarView = view
    }

    private func hideToolbar() {
        toolbarWindow?.orderOut(nil)
        toolbarWindow = nil
        toolbarView = nil
    }

    // MARK: - Event Monitors

    private func registerActiveMonitors() {
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
        keyGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in self?.handleKeyDown(event) }
        }
        keyLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in self?.handleKeyDown(event) }
            return event
        }
        rightMouseDownGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            Task { @MainActor in self?.handleRightMouseDown(event) }
        }
        rightMouseDownLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            Task { @MainActor in self?.handleRightMouseDown(event) }
            return event
        }
    }

    private func removeActiveMonitors() {
        if let m = mouseDownGlobalMonitor { NSEvent.removeMonitor(m); mouseDownGlobalMonitor = nil }
        if let m = mouseDownLocalMonitor { NSEvent.removeMonitor(m); mouseDownLocalMonitor = nil }
        if let m = mouseDragGlobalMonitor { NSEvent.removeMonitor(m); mouseDragGlobalMonitor = nil }
        if let m = mouseDragLocalMonitor { NSEvent.removeMonitor(m); mouseDragLocalMonitor = nil }
        if let m = mouseUpGlobalMonitor { NSEvent.removeMonitor(m); mouseUpGlobalMonitor = nil }
        if let m = mouseUpLocalMonitor { NSEvent.removeMonitor(m); mouseUpLocalMonitor = nil }
        if let m = keyGlobalMonitor { NSEvent.removeMonitor(m); keyGlobalMonitor = nil }
        if let m = keyLocalMonitor { NSEvent.removeMonitor(m); keyLocalMonitor = nil }
        if let m = rightMouseDownGlobalMonitor { NSEvent.removeMonitor(m); rightMouseDownGlobalMonitor = nil }
        if let m = rightMouseDownLocalMonitor { NSEvent.removeMonitor(m); rightMouseDownLocalMonitor = nil }
    }

    // MARK: - Mouse Event Handling

    private func screenPointToLocal(_ screenPoint: NSPoint) -> (NSPoint, (window: NSWindow, view: ScreenAnnotationOverlayView, displayID: UInt32, screen: NSScreen))? {
        for entry in overlayWindows {
            let frame = entry.window.frame
            if frame.contains(screenPoint) {
                let localPoint = NSPoint(
                    x: screenPoint.x - frame.origin.x,
                    y: screenPoint.y - frame.origin.y
                )
                return (localPoint, entry)
            }
        }
        return nil
    }

    private func handleMouseDown(_ event: NSEvent) {
        let screenPoint = NSEvent.mouseLocation

        // Ignore clicks on toolbar or elevated windows
        if let tbFrame = toolbarWindow?.frame, tbFrame.contains(screenPoint) { return }
        if let tiFrame = textInputWindow?.frame, tiFrame.contains(screenPoint) { return }
        for window in elevatedWindows {
            if window.frame.contains(screenPoint) { return }
        }

        guard let (localPoint, _) = screenPointToLocal(screenPoint) else { return }

        // Try to select an existing annotation under the cursor (any tool)
        if hitTestAndSelect(at: localPoint) {
            return
        }

        // Deselect if clicking empty space
        if selectedAnnotationIndex != nil {
            selectedAnnotationIndex = nil
            updateAllOverlays()
        }

        if currentTool == .text {
            showTextInput(at: screenPoint, localPoint: localPoint)
            return
        }

        currentAnnotation = Annotation(
            tool: currentTool,
            points: [localPoint],
            color: currentColor,
            lineWidth: currentLineWidth,
            text: nil,
            isFilled: false
        )

        // For line/arrow/rect/ellipse, add second point (will be updated on drag)
        if currentTool != .freehand {
            currentAnnotation?.points.append(localPoint)
        }

        updateAllOverlays()
    }

    private func handleMouseDragged(_ event: NSEvent) {
        let screenPoint = NSEvent.mouseLocation
        guard let (localPoint, _) = screenPointToLocal(screenPoint) else { return }

        if isDraggingSelection {
            handleSelectMouseDragged(to: localPoint)
            return
        }

        guard currentAnnotation != nil else { return }

        switch currentAnnotation!.tool {
        case .freehand:
            currentAnnotation!.points.append(localPoint)
        case .line, .arrow, .rectangle, .ellipse:
            if currentAnnotation!.points.count >= 2 {
                currentAnnotation!.points[1] = localPoint
            }
        case .text:
            break
        }

        updateAllOverlays()
    }

    private func handleMouseUp(_ event: NSEvent) {
        if isDraggingSelection {
            isDraggingSelection = false
            return
        }

        guard var annotation = currentAnnotation else { return }
        let screenPoint = NSEvent.mouseLocation

        // Update final point
        if let (localPoint, _) = screenPointToLocal(screenPoint) {
            switch annotation.tool {
            case .freehand:
                annotation.points.append(localPoint)
            case .line, .arrow, .rectangle, .ellipse:
                if annotation.points.count >= 2 {
                    annotation.points[1] = localPoint
                }
            case .text:
                break
            }
        }

        // Only add if it has meaningful content
        let shouldAdd: Bool
        switch annotation.tool {
        case .freehand:
            shouldAdd = annotation.points.count > 1
        case .line, .arrow:
            shouldAdd = annotation.points.count >= 2 && annotation.points[0] != annotation.points[1]
        case .rectangle, .ellipse:
            if annotation.points.count >= 2 {
                let dx = abs(annotation.points[1].x - annotation.points[0].x)
                let dy = abs(annotation.points[1].y - annotation.points[0].y)
                shouldAdd = dx > 2 || dy > 2
            } else {
                shouldAdd = false
            }
        case .text:
            shouldAdd = false
        }

        if shouldAdd {
            annotations.append(annotation)
        }
        currentAnnotation = nil
        updateAllOverlays()
    }

    private func handleRightMouseDown(_ event: NSEvent) {
        // Right click to undo last annotation
        undo()
    }

    // MARK: - Select / Move

    /// Hit-test all annotations and select the topmost one under the cursor. Returns true if something was hit.
    private func hitTestAndSelect(at point: CGPoint) -> Bool {
        for i in stride(from: annotations.count - 1, through: 0, by: -1) {
            if hitTest(annotation: annotations[i], point: point) {
                selectedAnnotationIndex = i
                let center = annotationCenter(annotations[i])
                dragOffset = CGPoint(x: point.x - center.x, y: point.y - center.y)
                isDraggingSelection = true
                updateAllOverlays()
                return true
            }
        }
        return false
    }

    private func handleSelectMouseDragged(to point: CGPoint) {
        guard let idx = selectedAnnotationIndex, idx < annotations.count else { return }
        let center = annotationCenter(annotations[idx])
        let dx = point.x - dragOffset.x - center.x
        let dy = point.y - dragOffset.y - center.y
        for i in 0..<annotations[idx].points.count {
            annotations[idx].points[i].x += dx
            annotations[idx].points[i].y += dy
        }
        updateAllOverlays()
    }

    private func hitTest(annotation: Annotation, point: CGPoint) -> Bool {
        let threshold: CGFloat = max(annotation.lineWidth * 2, 12)

        switch annotation.tool {
        case .freehand:
            for p in annotation.points {
                if hypot(p.x - point.x, p.y - point.y) < threshold { return true }
            }
            return false
        case .line, .arrow:
            guard annotation.points.count >= 2 else { return false }
            return distanceToSegment(point: point, a: annotation.points[0], b: annotation.points[1]) < threshold
        case .rectangle, .ellipse:
            guard annotation.points.count >= 2 else { return false }
            let rect = rectFromTwoPoints(annotation.points[0], annotation.points[1]).insetBy(dx: -threshold, dy: -threshold)
            return rect.contains(point)
        case .text:
            guard let text = annotation.text, let p = annotation.points.first else { return false }
            let fontSize = max(16, annotation.lineWidth * 4)
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: fontSize, weight: .semibold)]
            let size = (text as NSString).size(withAttributes: attrs)
            let textRect = CGRect(x: p.x - 6, y: p.y - 6, width: size.width + 12, height: size.height + 12)
            return textRect.contains(point)
        }
    }

    private func annotationCenter(_ annotation: Annotation) -> CGPoint {
        guard !annotation.points.isEmpty else { return .zero }
        let sumX = annotation.points.reduce(0.0) { $0 + $1.x }
        let sumY = annotation.points.reduce(0.0) { $0 + $1.y }
        let n = CGFloat(annotation.points.count)
        return CGPoint(x: sumX / n, y: sumY / n)
    }

    private func distanceToSegment(point p: CGPoint, a: CGPoint, b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lenSq = dx * dx + dy * dy
        guard lenSq > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lenSq))
        let proj = CGPoint(x: a.x + t * dx, y: a.y + t * dy)
        return hypot(p.x - proj.x, p.y - proj.y)
    }

    private func rectFromTwoPoints(_ p1: CGPoint, _ p2: CGPoint) -> CGRect {
        CGRect(x: min(p1.x, p2.x), y: min(p1.y, p2.y), width: abs(p2.x - p1.x), height: abs(p2.y - p1.y))
    }

    // MARK: - Keyboard Handling

    private func handleKeyDown(_ event: NSEvent) {
        // Don't intercept keys when text input is active
        if textInputWindow != nil { return }
        // Delete / Backspace to remove selected annotation
        if event.keyCode == 51 || event.keyCode == 117 { // 51 = Backspace, 117 = Forward Delete
            deleteSelected()
            return
        }
        // ⌘Z for undo
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "z" {
            undo()
            return
        }
        // ESC to close (backup — Carbon hotkey should catch this too)
        if event.keyCode == 53 {
            isEnabled = false
            return
        }
    }

    // MARK: - Text Input

    private func showTextInput(at screenPoint: NSPoint, localPoint: NSPoint) {
        dismissTextInput()

        let inputWidth: CGFloat = 250
        let inputHeight: CGFloat = 36

        let textField = NSTextField(frame: NSRect(x: 8, y: 4, width: inputWidth - 16, height: inputHeight - 8))
        textField.placeholderString = "Type text and press Enter"
        textField.font = .systemFont(ofSize: 16, weight: .medium)
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.textColor = .white
        textField.target = self
        textField.action = #selector(textFieldAction(_:))

        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: inputWidth, height: inputHeight))
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.8).cgColor
        containerView.layer?.cornerRadius = 8
        containerView.addSubview(textField)

        let window = KeyableWindow(
            contentRect: NSRect(x: screenPoint.x, y: screenPoint.y - inputHeight - 4, width: inputWidth, height: inputHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = containerView
        window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(textField)

        pendingTextPoint = localPoint
        textInputWindow = window
    }

    @objc private func textFieldAction(_ sender: NSTextField) {
        let text = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            dismissTextInput()
            return
        }

        let annotation = Annotation(
            tool: .text,
            points: [pendingTextPoint],
            color: currentColor,
            lineWidth: currentLineWidth,
            text: text,
            isFilled: false
        )
        annotations.append(annotation)
        updateAllOverlays()

        dismissTextInput()
    }

    private func dismissTextInput() {
        textInputWindow?.orderOut(nil)
        textInputWindow = nil
    }

    // MARK: - Actions

    func undo() {
        guard !annotations.isEmpty else { return }
        annotations.removeLast()
        if let idx = selectedAnnotationIndex, idx >= annotations.count {
            selectedAnnotationIndex = nil
        }
        updateAllOverlays()
    }

    func deleteSelected() {
        guard let idx = selectedAnnotationIndex, idx < annotations.count else { return }
        annotations.remove(at: idx)
        selectedAnnotationIndex = nil
        updateAllOverlays()
    }

    func clearAll() {
        annotations.removeAll()
        currentAnnotation = nil
        selectedAnnotationIndex = nil
        updateAllOverlays()
    }

    func saveScreenshot() {
        guard let mainEntry = overlayWindows.first else { return }
        let view = mainEntry.view
        guard let bitmapRep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmapRep)

        guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let filename = "Annotation_\(formatter.string(from: Date())).png"

        let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        let fileURL = desktopURL.appendingPathComponent(filename)

        do {
            try pngData.write(to: fileURL)
            print("[ScreenAnnotation] Screenshot saved to \(fileURL.path)")
            // Show system sound feedback
            NSSound(named: "Tink")?.play()
        } catch {
            print("[ScreenAnnotation] Failed to save screenshot: \(error)")
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
