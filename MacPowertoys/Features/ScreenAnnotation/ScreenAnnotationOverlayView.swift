import AppKit

// MARK: - Screen Annotation Overlay View

class ScreenAnnotationOverlayView: NSView {
    var annotations: [Annotation] = []
    var currentAnnotation: Annotation? = nil
    var dimBackground: Bool = true
    var selectedAnnotationIndex: Int? = nil

    private let arrowHeadLength: CGFloat = 16
    private let arrowHeadAngle: CGFloat = .pi / 6 // 30 degrees

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

        // Dim background
        if dimBackground {
            ctx.setFillColor(NSColor.black.withAlphaComponent(0.15).cgColor)
            ctx.fill(bounds)
        }

        // Draw completed annotations
        for (index, annotation) in annotations.enumerated() {
            drawAnnotation(ctx, annotation: annotation)
            if index == selectedAnnotationIndex {
                drawSelectionHighlight(ctx, annotation: annotation)
            }
        }

        // Draw in-progress annotation
        if let current = currentAnnotation {
            drawAnnotation(ctx, annotation: current)
        }
    }

    // MARK: - Drawing Dispatch

    private func drawAnnotation(_ ctx: CGContext, annotation: Annotation) {
        ctx.saveGState()
        ctx.setStrokeColor(annotation.color.cgColor)
        ctx.setFillColor(annotation.color.cgColor)
        ctx.setLineWidth(annotation.lineWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        switch annotation.tool {
        case .freehand:
            drawFreehand(ctx, points: annotation.points)
        case .line:
            drawLine(ctx, points: annotation.points)
        case .arrow:
            drawArrow(ctx, points: annotation.points)
        case .rectangle:
            drawRectangle(ctx, points: annotation.points, filled: annotation.isFilled)
        case .ellipse:
            drawEllipse(ctx, points: annotation.points, filled: annotation.isFilled)
        case .text:
            drawText(ctx, annotation: annotation)
        }
        ctx.restoreGState()
    }

    // MARK: - Freehand

    private func drawFreehand(_ ctx: CGContext, points: [CGPoint]) {
        guard points.count >= 2 else { return }
        ctx.beginPath()
        ctx.move(to: points[0])
        for i in 1..<points.count {
            ctx.addLine(to: points[i])
        }
        ctx.strokePath()
    }

    // MARK: - Line

    private func drawLine(_ ctx: CGContext, points: [CGPoint]) {
        guard points.count >= 2 else { return }
        ctx.beginPath()
        ctx.move(to: points[0])
        ctx.addLine(to: points[1])
        ctx.strokePath()
    }

    // MARK: - Arrow

    private func drawArrow(_ ctx: CGContext, points: [CGPoint]) {
        guard points.count >= 2 else { return }
        let start = points[0]
        let end = points[1]

        // Draw line
        ctx.beginPath()
        ctx.move(to: start)
        ctx.addLine(to: end)
        ctx.strokePath()

        // Draw arrowhead
        let angle = atan2(end.y - start.y, end.x - start.x)

        let arrowPoint1 = CGPoint(
            x: end.x - arrowHeadLength * cos(angle - arrowHeadAngle),
            y: end.y - arrowHeadLength * sin(angle - arrowHeadAngle)
        )
        let arrowPoint2 = CGPoint(
            x: end.x - arrowHeadLength * cos(angle + arrowHeadAngle),
            y: end.y - arrowHeadLength * sin(angle + arrowHeadAngle)
        )

        ctx.beginPath()
        ctx.move(to: end)
        ctx.addLine(to: arrowPoint1)
        ctx.addLine(to: arrowPoint2)
        ctx.closePath()
        ctx.fillPath()
    }

    // MARK: - Rectangle

    private func drawRectangle(_ ctx: CGContext, points: [CGPoint], filled: Bool) {
        guard points.count >= 2 else { return }
        let rect = rectFromPoints(points[0], points[1])
        if filled {
            ctx.fill(rect)
        } else {
            ctx.stroke(rect)
        }
    }

    // MARK: - Ellipse

    private func drawEllipse(_ ctx: CGContext, points: [CGPoint], filled: Bool) {
        guard points.count >= 2 else { return }
        let rect = rectFromPoints(points[0], points[1])
        if filled {
            ctx.fillEllipse(in: rect)
        } else {
            ctx.strokeEllipse(in: rect)
        }
    }

    // MARK: - Text

    private func drawText(_ ctx: CGContext, annotation: Annotation) {
        guard let text = annotation.text, !text.isEmpty, let point = annotation.points.first else { return }

        let fontSize = max(16, annotation.lineWidth * 4)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: annotation.color
        ]
        let attrStr = NSAttributedString(string: text, attributes: attrs)
        let size = attrStr.size()

        // Draw background pill
        let padding: CGFloat = 6
        let bgRect = CGRect(
            x: point.x - padding,
            y: point.y - padding,
            width: size.width + padding * 2,
            height: size.height + padding * 2
        )
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.6).cgColor)
        let path = CGPath(roundedRect: bgRect, cornerWidth: 4, cornerHeight: 4, transform: nil)
        ctx.addPath(path)
        ctx.fillPath()

        // Draw text
        NSGraphicsContext.saveGraphicsState()
        let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.current = nsCtx
        attrStr.draw(at: point)
        NSGraphicsContext.restoreGraphicsState()
    }

    // MARK: - Selection Highlight

    private func drawSelectionHighlight(_ ctx: CGContext, annotation: Annotation) {
        let bbox = boundingBox(for: annotation)
        guard !bbox.isNull, !bbox.isEmpty else { return }
        let highlightRect = bbox.insetBy(dx: -6, dy: -6)

        ctx.saveGState()
        ctx.setStrokeColor(NSColor.controlAccentColor.withAlphaComponent(0.8).cgColor)
        ctx.setLineWidth(1.5)
        ctx.setLineDash(phase: 0, lengths: [5, 3])
        let path = CGPath(roundedRect: highlightRect, cornerWidth: 4, cornerHeight: 4, transform: nil)
        ctx.addPath(path)
        ctx.strokePath()

        // Draw corner handles
        let handleSize: CGFloat = 6
        ctx.setFillColor(NSColor.textBackgroundColor.cgColor)
        ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
        ctx.setLineWidth(1)
        ctx.setLineDash(phase: 0, lengths: [])
        let corners = [
            CGPoint(x: highlightRect.minX, y: highlightRect.minY),
            CGPoint(x: highlightRect.maxX, y: highlightRect.minY),
            CGPoint(x: highlightRect.minX, y: highlightRect.maxY),
            CGPoint(x: highlightRect.maxX, y: highlightRect.maxY),
        ]
        for corner in corners {
            let handleRect = CGRect(x: corner.x - handleSize / 2, y: corner.y - handleSize / 2, width: handleSize, height: handleSize)
            ctx.fillEllipse(in: handleRect)
            ctx.strokeEllipse(in: handleRect)
        }
        ctx.restoreGState()
    }

    private func boundingBox(for annotation: Annotation) -> CGRect {
        guard !annotation.points.isEmpty else { return .null }

        switch annotation.tool {
        case .text:
            guard let text = annotation.text, let p = annotation.points.first else { return .null }
            let fontSize = max(16, annotation.lineWidth * 4)
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: fontSize, weight: .semibold)]
            let size = (text as NSString).size(withAttributes: attrs)
            return CGRect(x: p.x, y: p.y, width: size.width, height: size.height)
        default:
            var minX = CGFloat.greatestFiniteMagnitude
            var minY = CGFloat.greatestFiniteMagnitude
            var maxX = -CGFloat.greatestFiniteMagnitude
            var maxY = -CGFloat.greatestFiniteMagnitude
            for p in annotation.points {
                minX = min(minX, p.x)
                minY = min(minY, p.y)
                maxX = max(maxX, p.x)
                maxY = max(maxY, p.y)
            }
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }
    }

    // MARK: - Helpers

    private func rectFromPoints(_ p1: CGPoint, _ p2: CGPoint) -> CGRect {
        CGRect(
            x: min(p1.x, p2.x),
            y: min(p1.y, p2.y),
            width: abs(p2.x - p1.x),
            height: abs(p2.y - p1.y)
        )
    }
}
