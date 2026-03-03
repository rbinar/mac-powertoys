import AppKit

class ScreenCaptureOverlayView: NSView {
    // Updated by model on every mouseDragged event — triggers redraw automatically
    var selectionRect: NSRect? {
        didSet { setNeedsDisplay(bounds) }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        // wantsLayer intentionally NOT set — punch-through blend mode requires layer-free rendering
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // Step 1: Dark dim overlay over entire bounds
        NSColor.black.withAlphaComponent(0.45).setFill()
        bounds.fill()

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

        // Small rounded pill background behind label
        let pillRect = NSRect(
            x: max(4, labelX - 6),
            y: labelY - 3,
            width: strSize.width + 12,
            height: strSize.height + 6
        )
        NSColor.black.withAlphaComponent(0.65).setFill()
        NSBezierPath(roundedRect: pillRect, xRadius: 4, yRadius: 4).fill()

        str.draw(at: NSPoint(x: max(10, labelX), y: labelY))
    }
}
