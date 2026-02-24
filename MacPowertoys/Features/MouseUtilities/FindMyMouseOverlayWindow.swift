import AppKit

// MARK: - Overlay Window (wrapper, not subclass)

class FindMyMouseOverlayWindow {
    let window: NSWindow
    private let overlayView: FindMyMouseOverlayView
    let screenFrame: NSRect

    init(
        screen: NSScreen,
        overlayOpacity: Double,
        backgroundColor: NSColor,
        spotlightRadius: CGFloat,
        animationDurationMs: Double
    ) {
        let frame = screen.frame
        self.screenFrame = frame

        overlayView = FindMyMouseOverlayView(
            frame: NSRect(origin: .zero, size: frame.size),
            overlayOpacity: overlayOpacity,
            backgroundColor: backgroundColor,
            spotlightRadius: spotlightRadius,
            animationDurationMs: animationDurationMs
        )

        window = NSWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )

        window.contentView = overlayView
        window.level = .screenSaver
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.animationBehavior = .none
    }

    func showOverlay() {
        let mouseLocation = NSEvent.mouseLocation
        let localPoint = screenToLocal(mouseLocation)
        overlayView.setInitialCursorPosition(localPoint)
        window.orderFrontRegardless()
        overlayView.animateIn()
    }

    func hideOverlay() {
        overlayView.animateOut()
    }

    func updateSpotlight(at screenPoint: NSPoint) {
        let localPoint = screenToLocal(screenPoint)
        overlayView.updateCursorPosition(localPoint)
    }

    private func screenToLocal(_ screenPoint: NSPoint) -> NSPoint {
        NSPoint(x: screenPoint.x - screenFrame.origin.x,
                y: screenPoint.y - screenFrame.origin.y)
    }

    func close() {
        overlayView.stopAnimations()
        window.orderOut(nil)
    }
}

// MARK: - Overlay View

class FindMyMouseOverlayView: NSView {
    private let overlayOpacity: Double
    private let bgColor: NSColor
    private let spotlightRadius: CGFloat
    private let animationDurationMs: Double

    private var cursorPosition: NSPoint = .zero
    private var currentRadius: CGFloat = 0
    private var currentOpacity: CGFloat = 0

    private var animationTimer: Timer?
    private var targetRadius: CGFloat = 0
    private var targetOpacity: CGFloat = 0
    private var animationStartTime: CFTimeInterval = 0
    private var animationDuration: CFTimeInterval = 0
    private var startRadius: CGFloat = 0
    private var startOpacity: CGFloat = 0
    private var isAnimating: Bool = false

    init(
        frame: NSRect,
        overlayOpacity: Double,
        backgroundColor: NSColor,
        spotlightRadius: CGFloat,
        animationDurationMs: Double
    ) {
        self.overlayOpacity = overlayOpacity
        self.bgColor = backgroundColor
        self.spotlightRadius = spotlightRadius
        self.animationDurationMs = animationDurationMs
        self.targetRadius = spotlightRadius
        super.init(frame: frame)
        wantsLayer = true
        layer?.isOpaque = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let viewPoint = cursorPosition

        // Fill background
        ctx.setFillColor(bgColor.withAlphaComponent(currentOpacity).cgColor)
        ctx.fill(bounds)

        // Punch spotlight hole using clear blend mode
        ctx.setBlendMode(.clear)

        // Draw soft-edge spotlight using radial gradient for smooth falloff
        let innerRadius = max(currentRadius - 20, 0)
        let outerRadius = currentRadius

        // Clear the inner circle completely
        let circlePath = CGPath(
            ellipseIn: CGRect(
                x: viewPoint.x - innerRadius,
                y: viewPoint.y - innerRadius,
                width: innerRadius * 2,
                height: innerRadius * 2
            ),
            transform: nil
        )
        ctx.addPath(circlePath)
        ctx.fillPath()

        // Draw gradient ring for soft edge
        ctx.setBlendMode(.normal)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let gradientColors = [
            CGColor(gray: 0, alpha: 0),
            bgColor.withAlphaComponent(currentOpacity).cgColor
        ] as CFArray
        let gradientLocations: [CGFloat] = [0.0, 1.0]

        if let gradient = CGGradient(colorsSpace: colorSpace, colors: gradientColors, locations: gradientLocations) {
            ctx.drawRadialGradient(
                gradient,
                startCenter: viewPoint,
                startRadius: innerRadius,
                endCenter: viewPoint,
                endRadius: outerRadius,
                options: []
            )
        }
    }

    // MARK: - Position Updates

    func setInitialCursorPosition(_ localPoint: NSPoint) {
        cursorPosition = localPoint
    }

    func updateCursorPosition(_ localPoint: NSPoint) {
        cursorPosition = localPoint
        setNeedsDisplay(bounds)
    }

    // MARK: - Animations

    func animateIn() {
        startRadius = spotlightRadius * 4
        currentRadius = startRadius
        startOpacity = 0
        currentOpacity = 0
        targetRadius = spotlightRadius
        targetOpacity = CGFloat(overlayOpacity)
        animationDuration = animationDurationMs / 1000.0
        animationStartTime = CACurrentMediaTime()
        isAnimating = true
        startAnimationTimer()
    }

    func animateOut() {
        startRadius = currentRadius
        startOpacity = currentOpacity
        targetRadius = spotlightRadius * 4
        targetOpacity = 0
        animationDuration = (animationDurationMs / 1000.0) * 0.6
        animationStartTime = CACurrentMediaTime()
        isAnimating = true
        startAnimationTimer()
    }

    // MARK: - Animation Timer

    private func startAnimationTimer() {
        guard animationTimer == nil else { return }
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.animationTick()
            }
        }
        RunLoop.main.add(animationTimer!, forMode: .common)
    }

    private func stopAnimationTimer() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    private func animationTick() {
        if isAnimating {
            let elapsed = CACurrentMediaTime() - animationStartTime
            let progress = min(elapsed / animationDuration, 1.0)
            // Ease out cubic
            let eased = 1.0 - pow(1.0 - progress, 3.0)

            currentRadius = startRadius + CGFloat(eased) * (targetRadius - startRadius)
            currentOpacity = startOpacity + CGFloat(eased) * (targetOpacity - startOpacity)

            if progress >= 1.0 {
                isAnimating = false
                currentRadius = targetRadius
                currentOpacity = targetOpacity

                // If animated out, stop the timer
                if targetOpacity == 0 {
                    stopAnimationTimer()
                }
            }
        }

        setNeedsDisplay(bounds)
    }

    // MARK: - Cleanup

    func stopAnimations() {
        stopAnimationTimer()
    }

    deinit {
        stopAnimationTimer()
    }
}
