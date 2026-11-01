import AppKit

/// Borderless, non-activating overlay panel: it takes the selection clicks itself
/// (so they never reach the app underneath) without changing the frontmost app.
final class ScreenCaptureOverlayPanel: NSPanel {
    // Key status lets the overlay's cursor rect (crosshair) apply while the app is inactive.
    override var canBecomeKey: Bool { true }
}

class ScreenCaptureOverlayView: NSView {
    // Updated by model on every mouseDragged event — triggers redraw automatically
    var selectionRect: NSRect? {
        didSet { setNeedsDisplay(bounds) }
    }

    // Selection input, reported in global screen coordinates (NSEvent.mouseLocation).
    var onMouseDown: (() -> Void)?
    var onMouseDragged: (() -> Void)?
    var onMouseUp: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        // wantsLayer intentionally NOT set — punch-through blend mode requires layer-free rendering
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) { onMouseDown?() }
    override func mouseDragged(with event: NSEvent) { onMouseDragged?() }
    override func mouseUp(with event: NSEvent) { onMouseUp?() }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // Step 1: Dark dim overlay over entire bounds
        NSColor.black.withAlphaComponent(0.45).setFill()
        bounds.fill()

        // Hint pill (hidden once a selection starts)
        if selectionRect == nil {
            let hint = NSAttributedString(string: "Drag to capture · ESC to cancel", attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor.white
            ])
            let hs = hint.size()
            let hintPill = NSRect(x: bounds.midX - hs.width / 2 - 12, y: bounds.maxY - hs.height - 60, width: hs.width + 24, height: hs.height + 12)
            NSColor.black.withAlphaComponent(0.65).setFill()
            NSBezierPath(roundedRect: hintPill, xRadius: hintPill.height / 2, yRadius: hintPill.height / 2).fill()
            hint.draw(at: NSPoint(x: hintPill.minX + 12, y: hintPill.minY + 6))
        }

        // Step 2: Punch-through + border + label for selection rect
        guard let rect = selectionRect, rect.width > 1, rect.height > 1 else { return }

        // Cut through the dim — reveal underlying screen content
        ctx.setBlendMode(.copy)
        NSColor.clear.setFill()
        rect.fill()
        ctx.setBlendMode(.normal)

        // White selection border
        NSColor.white.withAlphaComponent(0.9).setStroke()
        let borderPath = NSBezierPath(rect: rect)
        borderPath.lineWidth = 1.5
        borderPath.stroke()

        // Dimension label: "1280 × 720"
        let label = "\(Int(rect.width)) × \(Int(rect.height))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let str = NSAttributedString(string: label, attributes: attrs)
        let strSize = str.size()

        // Position: above rect if space, otherwise below
        let labelX = rect.midX - strSize.width / 2
        let labelY: CGFloat
        if rect.maxY + 6 + strSize.height + 6 < bounds.height {
            labelY = rect.maxY + 6
        } else if rect.minY - 6 - strSize.height - 6 > 0 {
            labelY = rect.minY - 6 - strSize.height
        } else {
            labelY = rect.maxY + 4 // fallback: overlap top
        }

        // Small rounded pill background behind label, clamped inside bounds on all edges
        let pillW = strSize.width + 12
        let pillH = strSize.height + 6
        let pillRect = NSRect(
            x: min(max(4, labelX - 6), bounds.maxX - pillW - 4),
            y: min(max(4, labelY - 3), bounds.maxY - pillH - 4),
            width: pillW,
            height: pillH
        )
        NSColor.black.withAlphaComponent(0.65).setFill()
        NSBezierPath(roundedRect: pillRect, xRadius: 4, yRadius: 4).fill()

        str.draw(at: NSPoint(x: pillRect.minX + 6, y: pillRect.minY + 3))
    }
}
