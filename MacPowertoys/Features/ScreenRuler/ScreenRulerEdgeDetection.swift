import Foundation
import CoreGraphics

// MARK: - Bitmap Edge Scanner
//
// Extracted, behavior-preserving refactor of the pixel-scanning concern that
// previously lived inline in `ScreenRulerModel.detectEdges(in:at:screenFrame:)`.
//
// IMPORTANT — equivalence contract:
// The pixel arithmetic and edge-scan logic in this type is intentionally a
// 1:1 transcription of the original nested local functions (`getPixel`,
// `getComponents`, `averageColor`, `pixelsCloseToStart`, `detectForY`) and the
// top-origin vs bottom-origin selection. Same clamping, same tolerance
// handling, same per-channel vs summed comparison, same `averageColor` radius,
// same left/right/top/bottom scan semantics, and the same
// `spanTop >= spanBottom ? top : bottom` selection. Do not "improve" the
// algorithm here.
//
// The scanner is created *inside* `CapturedScreen.pixelData.withUnsafeBytes`
// and holds the raw byte pointer for the lifetime of that closure only, so the
// unsafe-memory access semantics are identical to the original implementation.
struct BitmapEdgeScanner {
    // BGRA format: B=0, G=1, R=2, A=3 (byteOrder32Little + premultipliedFirst)
    private let ptr: UnsafePointer<UInt8>
    private let imgWidth: Int
    private let imgHeight: Int
    private let bytesPerRow: Int
    private let scaleX: CGFloat
    private let scaleY: CGFloat
    private let tolerance: Int
    private let usePerChannel: Bool

    init(
        ptr: UnsafePointer<UInt8>,
        imgWidth: Int,
        imgHeight: Int,
        bytesPerRow: Int,
        scaleX: CGFloat,
        scaleY: CGFloat,
        tolerance: Int,
        usePerChannel: Bool
    ) {
        self.ptr = ptr
        self.imgWidth = imgWidth
        self.imgHeight = imgHeight
        self.bytesPerRow = bytesPerRow
        self.scaleX = scaleX
        self.scaleY = scaleY
        self.tolerance = tolerance
        self.usePerChannel = usePerChannel
    }

    // MARK: - Pixel Access

    private func getPixel(_ x: Int, _ y: Int) -> UInt32 {
        let offset = y * bytesPerRow + x * 4
        return UnsafeRawPointer(ptr + offset).load(as: UInt32.self)
    }

    private func getComponents(_ p: UInt32) -> (b: Int, g: Int, r: Int) {
        (
            Int(p & 0xFF),
            Int((p >> 8) & 0xFF),
            Int((p >> 16) & 0xFF)
        )
    }

    /// Average a small neighborhood to reduce sensitivity to antialiasing/noise.
    private func averageColor(at x: Int, _ y: Int, radius: Int = 1) -> (b: Int, g: Int, r: Int) {
        var sb = 0
        var sg = 0
        var sr = 0
        var count = 0

        for yy in max(0, y - radius)...min(imgHeight - 1, y + radius) {
            for xx in max(0, x - radius)...min(imgWidth - 1, x + radius) {
                let c = getComponents(getPixel(xx, yy))
                sb += c.b
                sg += c.g
                sr += c.r
                count += 1
            }
        }

        guard count > 0 else { return (0, 0, 0) }
        return (sb / count, sg / count, sr / count)
    }

    private func pixelsCloseToStart(_ c: (b: Int, g: Int, r: Int), _ start: (b: Int, g: Int, r: Int)) -> Bool {
        let b0 = abs(c.b - start.b)
        let g0 = abs(c.g - start.g)
        let r0 = abs(c.r - start.r)
        if usePerChannel {
            return b0 <= tolerance && g0 <= tolerance && r0 <= tolerance
        } else {
            return (b0 + g0 + r0) <= tolerance
        }
    }

    // MARK: - Single-Orientation Scan

    /// Scan the four edges starting from the pixel at (`clampedX`, clamped `yInput`).
    private func detectForY(clampedX: Int, _ yInput: Int) -> EdgeDistances {
        let clampedY = max(1, min(yInput, imgHeight - 2))
        let startColor = averageColor(at: clampedX, clampedY)

        // Scan left — find last similar pixel position.
        var leftEdge = 0
        do {
            var x = clampedX
            while x > 0 {
                x -= 1
                let c = getComponents(getPixel(x, clampedY))
                if !pixelsCloseToStart(c, startColor) {
                    break
                }
            }
            leftEdge = x + 1
            let c = getComponents(getPixel(x, clampedY))
            if pixelsCloseToStart(c, startColor) {
                leftEdge = 0
            }
        }

        // Scan right.
        var rightEdge = imgWidth - 1
        do {
            var x = clampedX
            while x < imgWidth - 1 {
                x += 1
                let c = getComponents(getPixel(x, clampedY))
                if !pixelsCloseToStart(c, startColor) {
                    break
                }
            }
            rightEdge = x - 1
            let c = getComponents(getPixel(x, clampedY))
            if pixelsCloseToStart(c, startColor) {
                rightEdge = imgWidth - 1
            }
        }

        // Scan up (decreasing y in image coords).
        var topEdge = 0
        do {
            var y = clampedY
            while y > 0 {
                y -= 1
                let c = getComponents(getPixel(clampedX, y))
                if !pixelsCloseToStart(c, startColor) {
                    break
                }
            }
            topEdge = y + 1
            let c = getComponents(getPixel(clampedX, y))
            if pixelsCloseToStart(c, startColor) {
                topEdge = 0
            }
        }

        // Scan down (increasing y in image coords).
        var bottomEdge = imgHeight - 1
        do {
            var y = clampedY
            while y < imgHeight - 1 {
                y += 1
                let c = getComponents(getPixel(clampedX, y))
                if !pixelsCloseToStart(c, startColor) {
                    break
                }
            }
            bottomEdge = y - 1
            let c = getComponents(getPixel(clampedX, y))
            if pixelsCloseToStart(c, startColor) {
                bottomEdge = imgHeight - 1
            }
        }

        return EdgeDistances(
            left: Int(CGFloat(clampedX - leftEdge) / scaleX),
            right: Int(CGFloat(rightEdge - clampedX) / scaleX),
            top: Int(CGFloat(clampedY - topEdge) / scaleY),
            bottom: Int(CGFloat(bottomEdge - clampedY) / scaleY)
        )
    }

    // MARK: - Orientation-Selecting Scan

    /// Run the scan for both bitmap orientations and pick the one with the
    /// larger total span (top-origin wins ties), matching the original logic.
    func scan(clampedX: Int, pixelYTopOrigin: Int, pixelYBottomOrigin: Int) -> EdgeDistances {
        let edgesTopOrigin = detectForY(clampedX: clampedX, pixelYTopOrigin)
        let edgesBottomOrigin = detectForY(clampedX: clampedX, pixelYBottomOrigin)

        let spanTop = edgesTopOrigin.left + edgesTopOrigin.right + edgesTopOrigin.top + edgesTopOrigin.bottom
        let spanBottom = edgesBottomOrigin.left + edgesBottomOrigin.right + edgesBottomOrigin.top + edgesBottomOrigin.bottom

        return spanTop >= spanBottom ? edgesTopOrigin : edgesBottomOrigin
    }
}
