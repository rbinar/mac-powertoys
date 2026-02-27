import AppKit

// MARK: - Screen Ruler Overlay View

class ScreenRulerOverlayView: NSView {
    var lineColor: NSColor = .systemYellow
    var showFeet: Bool = true
    var measurementMode: MeasurementMode = .spacing
    var cursorPosition: NSPoint = .zero
    var isActiveScreen: Bool = false
    var edges: EdgeDistances = EdgeDistances()
    var boundsStart: NSPoint? = nil
    var boundsEnd: NSPoint? = nil
    var extraUnit: ExtraUnit = .none
    var screenDPI: CGFloat = 72.0

    private let feetLength: CGFloat = 6
    private let lineThickness: CGFloat = 1.5
    private let labelFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
    private let labelPadding: CGFloat = 4
    private let labelCornerRadius: CGFloat = 4

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

        switch measurementMode {
        case .spacing:
            drawSpacingLines(ctx)
        case .horizontal:
            drawHorizontalLine(ctx)
        case .vertical:
            drawVerticalLine(ctx)
        case .bounds:
            drawBoundsRect(ctx)
        }
    }

    // MARK: - Spacing Mode

    private func drawSpacingLines(_ ctx: CGContext) {
        drawHorizontalLine(ctx)
        drawVerticalLine(ctx)
    }

    // MARK: - Horizontal Line

    private func drawHorizontalLine(_ ctx: CGContext) {
        let p = cursorPosition
        let leftX = p.x - CGFloat(edges.left)
        let rightX = p.x + CGFloat(edges.right)
        let totalH = max(1, edges.left + edges.right)

        // Draw line
        ctx.setStrokeColor(lineColor.withAlphaComponent(0.9).cgColor)
        ctx.setLineWidth(lineThickness)
        ctx.move(to: CGPoint(x: leftX, y: p.y))
        ctx.addLine(to: CGPoint(x: rightX, y: p.y))
        ctx.strokePath()

        // Draw feet
        if showFeet {
            drawFoot(ctx, at: CGPoint(x: leftX, y: p.y), vertical: true)
            drawFoot(ctx, at: CGPoint(x: rightX, y: p.y), vertical: true)
        }

        // Draw label
        let label = formatLabel(pixels: totalH)
        drawLabel(ctx, text: label, at: CGPoint(x: p.x, y: p.y + 14))
    }

    // MARK: - Vertical Line

    private func drawVerticalLine(_ ctx: CGContext) {
        let p = cursorPosition
        let bottomY = p.y - CGFloat(edges.bottom)
        let topY = p.y + CGFloat(edges.top)
        let totalV = max(1, edges.top + edges.bottom)

        // Draw line
        ctx.setStrokeColor(lineColor.withAlphaComponent(0.9).cgColor)
        ctx.setLineWidth(lineThickness)
        ctx.move(to: CGPoint(x: p.x, y: bottomY))
        ctx.addLine(to: CGPoint(x: p.x, y: topY))
        ctx.strokePath()

        // Draw feet
        if showFeet {
            drawFoot(ctx, at: CGPoint(x: p.x, y: bottomY), vertical: false)
            drawFoot(ctx, at: CGPoint(x: p.x, y: topY), vertical: false)
        }

        // Draw label
        let label = formatLabel(pixels: totalV)
        drawLabel(ctx, text: label, at: CGPoint(x: p.x + 14, y: p.y))
    }

    // MARK: - Bounds Mode

    private func drawBoundsRect(_ ctx: CGContext) {
        guard let start = boundsStart, let end = boundsEnd else { return }

        let rect = CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )

        // Draw dashed rectangle
        ctx.setStrokeColor(lineColor.withAlphaComponent(0.9).cgColor)
        ctx.setLineWidth(lineThickness)
        ctx.setLineDash(phase: 0, lengths: [6, 4])
        ctx.stroke(rect)
        ctx.setLineDash(phase: 0, lengths: [])

        // Semi-transparent fill
        ctx.setFillColor(lineColor.withAlphaComponent(0.08).cgColor)
        ctx.fill(rect)

        // Draw dimension label
        let w = Int(abs(end.x - start.x))
        let h = Int(abs(end.y - start.y))
        var label = "\(w) × \(h) px"
        if extraUnit != .none {
            let wUnit = convertPixels(w)
            let hUnit = convertPixels(h)
            if let wU = wUnit, let hU = hUnit {
                label += "\n\(wU) × \(hU)"
            }
        }
        drawLabel(ctx, text: label, at: CGPoint(x: rect.midX, y: rect.midY))
    }

    // MARK: - Drawing Helpers

    private func drawFoot(_ ctx: CGContext, at point: CGPoint, vertical: Bool) {
        ctx.setStrokeColor(lineColor.withAlphaComponent(0.9).cgColor)
        ctx.setLineWidth(lineThickness)
        if vertical {
            // Vertical foot (perpendicular to horizontal line)
            ctx.move(to: CGPoint(x: point.x, y: point.y - feetLength))
            ctx.addLine(to: CGPoint(x: point.x, y: point.y + feetLength))
        } else {
            // Horizontal foot (perpendicular to vertical line)
            ctx.move(to: CGPoint(x: point.x - feetLength, y: point.y))
            ctx.addLine(to: CGPoint(x: point.x + feetLength, y: point.y))
        }
        ctx.strokePath()
    }

    private func drawLabel(_ ctx: CGContext, text: String, at center: CGPoint) {
        let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        let attrs: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraphStyle
        ]
        let attrStr = NSAttributedString(string: text, attributes: attrs)
        let textSize = attrStr.size()

        let bgRect = CGRect(
            x: center.x - textSize.width / 2 - labelPadding,
            y: center.y - textSize.height / 2 - labelPadding,
            width: textSize.width + labelPadding * 2,
            height: textSize.height + labelPadding * 2
        )

        // Background
        let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: labelCornerRadius, yRadius: labelCornerRadius)
        NSColor.black.withAlphaComponent(0.7).setFill()
        bgPath.fill()

        // Text
        let textOrigin = CGPoint(
            x: center.x - textSize.width / 2,
            y: center.y - textSize.height / 2
        )
        attrStr.draw(at: textOrigin)

        NSGraphicsContext.restoreGraphicsState()
    }

    private func formatLabel(pixels: Int) -> String {
        var label = "\(pixels) px"
        if let unitStr = convertPixels(pixels) {
            label += "  (\(unitStr))"
        }
        return label
    }

    private func convertPixels(_ pixels: Int) -> String? {
        guard extraUnit != .none else { return nil }
        let inches = CGFloat(pixels) / screenDPI
        switch extraUnit {
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
}

// MARK: - Toolbar View

class ScreenRulerToolbarView: NSView {
    var currentMode: MeasurementMode = .spacing {
        didSet { setNeedsDisplay(bounds) }
    }

    private let onModeChange: (MeasurementMode) -> Void
    private let onClose: () -> Void
    private var customTrackingAreas: [NSTrackingArea] = []
    private var hoveredItem: Int? = nil  // 0..<modes.count = mode buttons, last = close

    private struct ModeItem {
        let mode: MeasurementMode
        let sfSymbol: String
    }

    private let modes: [ModeItem] = [
        ModeItem(mode: .bounds, sfSymbol: "rectangle.dashed"),
        ModeItem(mode: .spacing, sfSymbol: "arrow.left.and.right"),
        ModeItem(mode: .horizontal, sfSymbol: "arrow.left.and.line.vertical.and.arrow.right"),
        ModeItem(mode: .vertical, sfSymbol: "arrow.up.and.line.horizontal.and.arrow.down"),
    ]

    private let itemSize: CGFloat = 32
    private let padding: CGFloat = 8
    private let gap: CGFloat = 2
    private let separatorGap: CGFloat = 12

    init(frame: NSRect, onModeChange: @escaping (MeasurementMode) -> Void, onClose: @escaping () -> Void) {
        self.onModeChange = onModeChange
        self.onClose = onClose
        super.init(frame: frame)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in customTrackingAreas { removeTrackingArea(area) }
        customTrackingAreas.removeAll()
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(area)
        customTrackingAreas.append(area)
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let newHovered = hitTestItem(at: point)
        if newHovered != hoveredItem {
            hoveredItem = newHovered
            setNeedsDisplay(bounds)
        }
    }

    override func mouseExited(with event: NSEvent) {
        hoveredItem = nil
        setNeedsDisplay(bounds)
    }

    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let idx = hitTestItem(at: point) else { return }
        if idx < modes.count {
            onModeChange(modes[idx].mode)
        } else {
            onClose()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let y = (bounds.height - itemSize) / 2
        var x = padding

        // ── Mode buttons ──
        for (i, item) in modes.enumerated() {
            let rect = CGRect(x: x, y: y, width: itemSize, height: itemSize)
            let isSelected = item.mode == currentMode
            let isHovered = hoveredItem == i

            if isSelected {
                drawPill(ctx, rect: rect, color: NSColor.controlAccentColor.withAlphaComponent(0.25))
            } else if isHovered {
                drawPill(ctx, rect: rect, color: NSColor.labelColor.withAlphaComponent(0.1))
            }

            drawSFSymbol(item.sfSymbol, in: rect, size: 14, color: isSelected ? .controlAccentColor : .labelColor)
            x += itemSize + gap
        }

        // ── Separator ──
        x += separatorGap / 2 - gap
        ctx.setStrokeColor(NSColor.separatorColor.cgColor)
        ctx.setLineWidth(0.5)
        ctx.move(to: CGPoint(x: x, y: 10))
        ctx.addLine(to: CGPoint(x: x, y: bounds.height - 10))
        ctx.strokePath()
        x += separatorGap / 2

        // ── Close button ──
        let closeRect = CGRect(x: x, y: y, width: itemSize, height: itemSize)
        let closeIdx = modes.count
        if hoveredItem == closeIdx {
            drawPill(ctx, rect: closeRect, color: NSColor.systemRed.withAlphaComponent(0.2))
        }
        drawSFSymbol("xmark", in: closeRect, size: 12, color: .secondaryLabelColor)
    }

    // MARK: - Hit Testing

    private func hitTestItem(at point: CGPoint) -> Int? {
        let y = (bounds.height - itemSize) / 2
        var x = padding

        for i in 0..<modes.count {
            let rect = CGRect(x: x, y: y, width: itemSize, height: itemSize)
            if rect.contains(point) { return i }
            x += itemSize + gap
        }
        x += separatorGap - gap

        let closeRect = CGRect(x: x, y: y, width: itemSize, height: itemSize)
        if closeRect.contains(point) { return modes.count }

        return nil
    }

    // MARK: - Drawing Helpers

    private func drawPill(_ ctx: CGContext, rect: CGRect, color: NSColor) {
        let path = CGPath(roundedRect: rect.insetBy(dx: 2, dy: 2), cornerWidth: 8, cornerHeight: 8, transform: nil)
        ctx.setFillColor(color.cgColor)
        ctx.addPath(path)
        ctx.fillPath()
    }

    private func drawSFSymbol(_ name: String, in rect: CGRect, size: CGFloat, color: NSColor) {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return }
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: .medium)
        let configured = image.withSymbolConfiguration(config) ?? image

        let tinted = NSImage(size: configured.size, flipped: false) { drawRect in
            color.setFill()
            drawRect.fill()
            configured.draw(in: drawRect, from: .zero, operation: .destinationIn, fraction: 1.0)
            return true
        }

        let imgSize = tinted.size
        let origin = CGPoint(
            x: rect.midX - imgSize.width / 2,
            y: rect.midY - imgSize.height / 2
        )
        tinted.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1.0)
    }

    /// Calculate required toolbar width
    static func computeWidth() -> CGFloat {
        let itemSize: CGFloat = 32
        let gap: CGFloat = 2
        let padding: CGFloat = 8
        let separatorGap: CGFloat = 12
        let modeCount = 4
        let closeCount = 1
        return padding * 2 + CGFloat(modeCount + closeCount) * itemSize + CGFloat(modeCount - 1 + closeCount - 1) * gap + separatorGap
    }
}
