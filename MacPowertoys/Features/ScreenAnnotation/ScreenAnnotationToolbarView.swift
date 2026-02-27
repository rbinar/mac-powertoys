import AppKit

// MARK: - Screen Annotation Toolbar View

class ScreenAnnotationToolbarView: NSView {
    var currentTool: AnnotationTool = .freehand {
        didSet { setNeedsDisplay(bounds) }
    }
    var currentColor: NSColor = .systemRed {
        didSet { setNeedsDisplay(bounds) }
    }
    var currentLineWidth: CGFloat = 4.0 {
        didSet { setNeedsDisplay(bounds) }
    }
    var hasSelection: Bool = false {
        didSet { setNeedsDisplay(bounds) }
    }

    private let onToolChange: (AnnotationTool) -> Void
    private let onColorChange: (NSColor) -> Void
    private let onLineWidthChange: (CGFloat) -> Void
    private let onUndo: () -> Void
    private let onDeleteSelected: () -> Void
    private let onClearAll: () -> Void
    private let onSave: () -> Void
    private let onClose: () -> Void

    private var customTrackingAreas: [NSTrackingArea] = []
    private var hoveredItem: ItemID? = nil

    // MARK: - Item Model

    private enum ItemID: Equatable {
        case tool(Int)
        case color(Int)
        case width(Int)
        case action(Int)
    }

    private struct ToolItem {
        let tool: AnnotationTool
        let sfSymbol: String
    }

    // SF Symbols for tools
    private let tools: [ToolItem] = [
        ToolItem(tool: .freehand, sfSymbol: "pencil.tip"),
        ToolItem(tool: .line, sfSymbol: "line.diagonal"),
        ToolItem(tool: .arrow, sfSymbol: "arrow.up.right"),
        ToolItem(tool: .rectangle, sfSymbol: "rectangle"),
        ToolItem(tool: .ellipse, sfSymbol: "circle"),
        ToolItem(tool: .text, sfSymbol: "textformat"),
    ]

    private let colorOptions: [NSColor] = annotationPresetColors

    private let lineWidthOptions: [CGFloat] = [2.0, 4.0, 8.0]

    private struct ActionItem {
        let id: String
        let sfSymbol: String
    }

    private let actions: [ActionItem] = [
        ActionItem(id: "undo", sfSymbol: "arrow.uturn.backward"),
        ActionItem(id: "delete", sfSymbol: "trash"),
        ActionItem(id: "clear", sfSymbol: "xmark.circle"),
        ActionItem(id: "save", sfSymbol: "square.and.arrow.down"),
        ActionItem(id: "close", sfSymbol: "xmark"),
    ]

    // Layout
    private let itemSize: CGFloat = 32
    private let colorDotSize: CGFloat = 16
    private let padding: CGFloat = 8
    private let gap: CGFloat = 2
    private let separatorGap: CGFloat = 12

    init(
        frame: NSRect,
        onToolChange: @escaping (AnnotationTool) -> Void,
        onColorChange: @escaping (NSColor) -> Void,
        onLineWidthChange: @escaping (CGFloat) -> Void,
        onUndo: @escaping () -> Void,
        onDeleteSelected: @escaping () -> Void,
        onClearAll: @escaping () -> Void,
        onSave: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.onToolChange = onToolChange
        self.onColorChange = onColorChange
        self.onLineWidthChange = onLineWidthChange
        self.onUndo = onUndo
        self.onDeleteSelected = onDeleteSelected
        self.onClearAll = onClearAll
        self.onSave = onSave
        self.onClose = onClose
        super.init(frame: frame)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Tracking

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
        let newHovered = hitTest(at: point)
        if newHovered != hoveredItem {
            hoveredItem = newHovered
            setNeedsDisplay(bounds)
        }
    }

    override func mouseExited(with event: NSEvent) {
        hoveredItem = nil
        setNeedsDisplay(bounds)
    }

    // MARK: - Click Handling

    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let item = hitTest(at: point) else { return }

        switch item {
        case .tool(let i):
            currentTool = tools[i].tool
            onToolChange(currentTool)
        case .color(let i):
            currentColor = colorOptions[i]
            onColorChange(currentColor)
        case .width(let i):
            currentLineWidth = lineWidthOptions[i]
            onLineWidthChange(currentLineWidth)
        case .action(let i):
            let action = actions[i]
            switch action.id {
            case "undo": onUndo()
            case "delete": onDeleteSelected()
            case "clear": onClearAll()
            case "save": onSave()
            case "close": onClose()
            default: break
            }
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let y = (bounds.height - itemSize) / 2
        var x = padding

        // ── Tools ──
        for (i, tool) in tools.enumerated() {
            let rect = CGRect(x: x, y: y, width: itemSize, height: itemSize)
            let isSelected = tool.tool == currentTool
            let isHovered = hoveredItem == .tool(i)

            if isSelected {
                drawPill(ctx, rect: rect, color: NSColor.controlAccentColor.withAlphaComponent(0.25))
            } else if isHovered {
                drawPill(ctx, rect: rect, color: NSColor.labelColor.withAlphaComponent(0.1))
            }

            drawSFSymbol(tool.sfSymbol, in: rect, size: 14, color: isSelected ? .controlAccentColor : .labelColor)
            x += itemSize + gap
        }

        // ── Separator ──
        x += separatorGap / 2 - gap
        drawSeparator(ctx, at: x)
        x += separatorGap / 2

        // ── Colors ──
        for (i, color) in colorOptions.enumerated() {
            let cellRect = CGRect(x: x, y: y, width: itemSize, height: itemSize)
            let isSelected = colorsAreEqual(color, currentColor)
            let isHovered = hoveredItem == .color(i)

            if isHovered && !isSelected {
                drawPill(ctx, rect: cellRect, color: NSColor.labelColor.withAlphaComponent(0.08))
            }

            let dotRect = CGRect(
                x: cellRect.midX - colorDotSize / 2,
                y: cellRect.midY - colorDotSize / 2,
                width: colorDotSize,
                height: colorDotSize
            )
            ctx.setFillColor(color.cgColor)
            ctx.fillEllipse(in: dotRect)

            if isSelected {
                let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                let ringColor: NSColor = isDark ? .white : .labelColor
                ctx.setStrokeColor(ringColor.cgColor)
                ctx.setLineWidth(2.0)
                ctx.strokeEllipse(in: dotRect.insetBy(dx: -3, dy: -3))
            }

            x += itemSize + gap
        }

        // ── Separator ──
        x += separatorGap / 2 - gap
        drawSeparator(ctx, at: x)
        x += separatorGap / 2

        // ── Line Widths ──
        for (i, width) in lineWidthOptions.enumerated() {
            let rect = CGRect(x: x, y: y, width: itemSize, height: itemSize)
            let isSelected = width == currentLineWidth
            let isHovered = hoveredItem == .width(i)

            if isSelected {
                drawPill(ctx, rect: rect, color: NSColor.controlAccentColor.withAlphaComponent(0.25))
            } else if isHovered {
                drawPill(ctx, rect: rect, color: NSColor.labelColor.withAlphaComponent(0.1))
            }
            let dotSize = max(4, min(width * 1.8, 14))
            let dotRect = CGRect(
                x: rect.midX - dotSize / 2,
                y: rect.midY - dotSize / 2,
                width: dotSize,
                height: dotSize
            )
            ctx.setFillColor((isSelected ? NSColor.controlAccentColor : NSColor.labelColor).cgColor)
            ctx.fillEllipse(in: dotRect)

            x += itemSize + gap
        }

        // ── Separator ──
        x += separatorGap / 2 - gap
        drawSeparator(ctx, at: x)
        x += separatorGap / 2

        // ── Actions ──
        for (i, action) in actions.enumerated() {
            let rect = CGRect(x: x, y: y, width: itemSize, height: itemSize)
            let isHovered = hoveredItem == .action(i)
            let isDisabled = action.id == "delete" && !hasSelection

            if !isDisabled && isHovered {
                let hoverColor: NSColor = action.id == "close" ? .systemRed.withAlphaComponent(0.2) : NSColor.labelColor.withAlphaComponent(0.1)
                drawPill(ctx, rect: rect, color: hoverColor)
            }

            let symbolColor: NSColor
            if isDisabled {
                symbolColor = .tertiaryLabelColor
            } else if action.id == "close" {
                symbolColor = .secondaryLabelColor
            } else {
                symbolColor = .labelColor
            }

            drawSFSymbol(action.sfSymbol, in: rect, size: 13, color: symbolColor)
            x += itemSize + gap
        }
    }

    // MARK: - Hit Testing

    private func hitTest(at point: CGPoint) -> ItemID? {
        let y = (bounds.height - itemSize) / 2
        var x = padding

        for i in 0..<tools.count {
            let rect = CGRect(x: x, y: y, width: itemSize, height: itemSize)
            if rect.contains(point) { return .tool(i) }
            x += itemSize + gap
        }
        x += separatorGap - gap

        for i in 0..<colorOptions.count {
            let rect = CGRect(x: x, y: y, width: itemSize, height: itemSize)
            if rect.contains(point) { return .color(i) }
            x += itemSize + gap
        }
        x += separatorGap - gap

        for i in 0..<lineWidthOptions.count {
            let rect = CGRect(x: x, y: y, width: itemSize, height: itemSize)
            if rect.contains(point) { return .width(i) }
            x += itemSize + gap
        }
        x += separatorGap - gap

        for i in 0..<actions.count {
            let rect = CGRect(x: x, y: y, width: itemSize, height: itemSize)
            if rect.contains(point) { return .action(i) }
            x += itemSize + gap
        }

        return nil
    }

    // MARK: - Drawing Helpers

    private func drawPill(_ ctx: CGContext, rect: CGRect, color: NSColor) {
        let path = CGPath(roundedRect: rect.insetBy(dx: 2, dy: 2), cornerWidth: 8, cornerHeight: 8, transform: nil)
        ctx.setFillColor(color.cgColor)
        ctx.addPath(path)
        ctx.fillPath()
    }

    private func drawSeparator(_ ctx: CGContext, at x: CGFloat) {
        ctx.setStrokeColor(NSColor.separatorColor.cgColor)
        ctx.setLineWidth(0.5)
        ctx.move(to: CGPoint(x: x, y: 10))
        ctx.addLine(to: CGPoint(x: x, y: bounds.height - 10))
        ctx.strokePath()
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

    private func colorsAreEqual(_ c1: NSColor, _ c2: NSColor) -> Bool {
        guard let c1RGB = c1.usingColorSpace(.deviceRGB),
              let c2RGB = c2.usingColorSpace(.deviceRGB) else { return false }
        return abs(c1RGB.redComponent - c2RGB.redComponent) < 0.01
            && abs(c1RGB.greenComponent - c2RGB.greenComponent) < 0.01
            && abs(c1RGB.blueComponent - c2RGB.blueComponent) < 0.01
    }

    /// Calculate the required toolbar width for the current layout
    static func computeWidth() -> CGFloat {
        let itemSize: CGFloat = 32
        let gap: CGFloat = 2
        let padding: CGFloat = 8
        let separatorGap: CGFloat = 12
        let toolCount = 6
        let colorCount = annotationPresetColors.count
        let widthCount = 3
        let actionCount = 5
        let totalItems = toolCount + colorCount + widthCount + actionCount
        let totalGaps = CGFloat(totalItems - 4) * gap // subtract 4 because 4 sections have no trailing gap
        let totalSeparators: CGFloat = 3 * separatorGap
        return padding * 2 + CGFloat(totalItems) * itemSize + totalGaps + totalSeparators
    }
}
