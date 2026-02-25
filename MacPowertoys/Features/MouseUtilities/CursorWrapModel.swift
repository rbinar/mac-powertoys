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

        var newX = mouseLocation.x
        var newY = mouseLocation.y
        var shouldWarp = false

        if wrapHorizontal {
            if mouseLocation.x <= unionFrame.minX + edgeMargin && mouseLocation.x < lastCursorPosition.x {
                newX = unionFrame.maxX - edgeMargin - 1
                shouldWarp = true
            } else if mouseLocation.x >= unionFrame.maxX - edgeMargin && mouseLocation.x > lastCursorPosition.x {
                newX = unionFrame.minX + edgeMargin + 1
                shouldWarp = true
            }
        }

        if wrapVertical {
            if mouseLocation.y <= unionFrame.minY + edgeMargin && mouseLocation.y < lastCursorPosition.y {
                newY = unionFrame.maxY - edgeMargin - 1
                shouldWarp = true
            } else if mouseLocation.y >= unionFrame.maxY - edgeMargin && mouseLocation.y > lastCursorPosition.y {
                newY = unionFrame.minY + edgeMargin + 1
                shouldWarp = true
            }
        }

        if shouldWarp {
            // CGWarpMouseCursorPosition uses top-left coordinate system
            let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
            let cgPoint = CGPoint(x: newX, y: primaryHeight - newY)
            CGWarpMouseCursorPosition(cgPoint)
            lastCursorPosition = NSPoint(x: newX, y: newY)
        } else {
            lastCursorPosition = mouseLocation
        }
    }
}
