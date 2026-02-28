import Foundation
import AppKit

@MainActor
final class MouseJigglerModel: ObservableObject {
    @Published var isEnabled: Bool = false {
        didSet {
            if isEnabled { startMonitoring() } else { stopMonitoring() }
        }
    }
    @Published var jiggleIntervalSeconds: Int = 30 {
        didSet {
            if isEnabled {
                stopMonitoring()
                startMonitoring()
            }
        }
    }

    private var jiggleTimer: Timer?
    private var jiggleOffset: Bool = false

    func startMonitoring() {
        guard isEnabled else { return }
        stopMonitoring()
        jiggleTimer = Timer.scheduledTimer(withTimeInterval: Double(jiggleIntervalSeconds), repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.jiggleMouse()
            }
        }
        RunLoop.main.add(jiggleTimer!, forMode: .common)
    }

    func stopMonitoring() {
        jiggleTimer?.invalidate()
        jiggleTimer = nil
    }

    private func jiggleMouse() {
        let currentPos = NSEvent.mouseLocation
        let screenHeight = NSScreen.main?.frame.height ?? 0
        // Convert from AppKit (bottom-left) to CG (top-left) coordinates
        let cgY = screenHeight - currentPos.y

        let delta: CGFloat = jiggleOffset ? -1 : 1
        jiggleOffset.toggle()

        if let moveEvent = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                                   mouseCursorPosition: CGPoint(x: currentPos.x + delta, y: cgY),
                                   mouseButton: .left) {
            moveEvent.post(tap: CGEventTapLocation.cghidEventTap)
        }
    }
}
