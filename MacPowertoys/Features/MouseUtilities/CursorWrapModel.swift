import Foundation
import AppKit

@MainActor
final class CursorWrapModel: ObservableObject {
    // MARK: - Settings
    @Published var isEnabled: Bool = false {
        didSet {
            if isEnabled { startMonitoring() } else { stopMonitoring() }
        }
    }
    @Published var wrapHorizontal: Bool = true
    @Published var wrapVertical: Bool = true
    @Published var edgeMargin: CGFloat = 2

    // MARK: - Private
    private var trackingTimer: Timer?
    private var lastCursorPosition: NSPoint = .zero

    // #74: consecutive-tick debounce — edge condition must persist for at least
    // 2 polling ticks before a wrap fires, so a single stray HID frame doesn't
    // trigger a spurious warp (2 ticks @ 60 Hz ≈ 33 ms, imperceptible to users).
    private struct EdgeState: Equatable {
        var xEdge: Int = 0  // -1 = left, +1 = right, 0 = none
        var yEdge: Int = 0  // -1 = bottom, +1 = top, 0 = none
    }
    private var edgeState = EdgeState()
    private var edgeTickCount: Int = 0
    private static let requiredEdgeTicks = 2

    // MARK: - Monitoring

    func startMonitoring() {
        guard isEnabled else { return }
        stopMonitoring()

        lastCursorPosition = NSEvent.mouseLocation

        trackingTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkAndWrap()
            }
        }
        RunLoop.main.add(trackingTimer!, forMode: .common)
    }

    func stopMonitoring() {
        trackingTimer?.invalidate()
        trackingTimer = nil
    }

    // MARK: - Wrap Logic

    private func checkAndWrap() {
        let mouseLocation = NSEvent.mouseLocation
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }

        // Compute the union of all screen frames
        let unionFrame = screens.reduce(NSRect.zero) { $0.union($1.frame) }

        // Determine which edges are currently being touched, per axis.
        // A direction is only active when the cursor is both at the edge AND
        // moving in the direction of that edge (matches existing logic).
        var currentXEdge = 0
        var currentYEdge = 0

        if wrapHorizontal {
            if mouseLocation.x <= unionFrame.minX + edgeMargin && mouseLocation.x < lastCursorPosition.x {
                currentXEdge = -1  // left edge
            } else if mouseLocation.x >= unionFrame.maxX - edgeMargin && mouseLocation.x > lastCursorPosition.x {
                currentXEdge = 1   // right edge
            }
        }

        if wrapVertical {
            if mouseLocation.y <= unionFrame.minY + edgeMargin && mouseLocation.y < lastCursorPosition.y {
                currentYEdge = -1  // bottom edge
            } else if mouseLocation.y >= unionFrame.maxY - edgeMargin && mouseLocation.y > lastCursorPosition.y {
                currentYEdge = 1   // top edge
            }
        }

        let currentState = EdgeState(xEdge: currentXEdge, yEdge: currentYEdge)
        let noEdge = currentXEdge == 0 && currentYEdge == 0

        if noEdge {
            // #74: cursor left the edge — reset debounce counter.
            edgeState = EdgeState()
            edgeTickCount = 0
            lastCursorPosition = mouseLocation
            return
        }

        // #74: debounce — count consecutive ticks with the same edge condition.
        if currentState == edgeState {
            edgeTickCount += 1
        } else {
            // Edge state changed (e.g. different edge or new axis added) — restart.
            edgeState = currentState
            edgeTickCount = 1
        }

        guard edgeTickCount >= CursorWrapModel.requiredEdgeTicks else {
            // Not yet confirmed — update position but don't warp.
            lastCursorPosition = mouseLocation
            return
        }

        // Edge has been stable for the required number of ticks — warp now.
        // #78: per-axis independence — only move the coordinate for the axis
        // that actually hit an edge; leave the other axis at its current position.
        // When both axes simultaneously reach their edges (corner), X takes
        // priority this tick so the cursor lands on the opposite horizontal edge
        // rather than jumping diagonally to the opposite corner.
        var newX = mouseLocation.x
        var newY = mouseLocation.y
        var warpX = false
        var warpY = false

        if currentXEdge == -1 {
            newX = unionFrame.maxX - edgeMargin - 1
            warpX = true
        } else if currentXEdge == 1 {
            newX = unionFrame.minX + edgeMargin + 1
            warpX = true
        }

        if currentYEdge == -1 {
            newY = unionFrame.maxY - edgeMargin - 1
            warpY = true
        } else if currentYEdge == 1 {
            newY = unionFrame.minY + edgeMargin + 1
            warpY = true
        }

        // #78 corner case: both axes triggered — only apply one axis per warp
        // so the cursor doesn't leap to the diagonally opposite corner.
        if warpX && warpY {
            // Prefer horizontal; vertical will fire on the next edge encounter.
            newY = mouseLocation.y
        }

        // CGWarpMouseCursorPosition uses top-left (Quartz) coordinate system.
        let primaryHeight = NSScreen.main?.frame.height ?? 0
        let cgPoint = CGPoint(x: newX, y: primaryHeight - newY)
        CGWarpMouseCursorPosition(cgPoint)
        lastCursorPosition = NSPoint(x: newX, y: newY)

        // Reset debounce after a successful warp so the next edge encounter
        // requires a fresh 2-tick confirmation.
        edgeState = EdgeState()
        edgeTickCount = 0
    }
}
