import AppKit

class ZoomItOverlayView: NSView {
    var zoomLevel: CGFloat = 2.0 {
        didSet {
            updateTransform(animated: animateZoom)
        }
    }
    
    var animateZoom: Bool = true
    
    private var centerPoint: NSPoint = .zero
    private let imageLayer = CALayer()
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        
        imageLayer.frame = bounds
        imageLayer.contentsGravity = .resize
        imageLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        imageLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        layer?.addSublayer(imageLayer)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func updateImage(_ image: CGImage) {
        // Disable implicit animation for contents update
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.contents = image
        CATransaction.commit()
    }
    
    func updateCenter(_ point: NSPoint) {
        self.centerPoint = point
        updateTransform(animated: false)
    }
    
    private func updateTransform(animated: Bool) {
        let viewWidth = bounds.width
        let viewHeight = bounds.height
        
        // Clamp centerPoint to bounds so that screens without the cursor 
        // just zoom towards their closest edge, keeping the screen fully covered.
        let clampedX = max(0, min(viewWidth, centerPoint.x))
        let clampedY = max(0, min(viewHeight, centerPoint.y))
        
        // Calculate the offset from the center of the screen to the clamped cursor
        let offsetX = clampedX - (viewWidth / 2)
        let offsetY = clampedY - (viewHeight / 2)
        
        // To keep the cursor at the same screen position while zooming the image around it,
        // we need to translate the layer in the opposite direction of the cursor offset,
        // scaled by the zoom factor.
        
        let translateX = -offsetX * (zoomLevel - 1)
        let translateY = -offsetY * (zoomLevel - 1)
        
        var transform = CATransform3DIdentity
        transform = CATransform3DTranslate(transform, translateX, translateY, 0)
        transform = CATransform3DScale(transform, zoomLevel, zoomLevel, 1)
        
        if animated {
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.2)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
            imageLayer.transform = transform
            CATransaction.commit()
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            imageLayer.transform = transform
            CATransaction.commit()
        }
    }
}
