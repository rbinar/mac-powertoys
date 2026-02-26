import Foundation
import AppKit
import IOKit.pwr_mgt

@MainActor
final class AwakeModel: ObservableObject {
    // MARK: - Settings
    @Published var isEnabled: Bool = false {
        didSet {
            if isEnabled { startMonitoring() } else { stopMonitoring() }
        }
    }
    @Published var keepDisplayOn: Bool = true {
        didSet {
            if isEnabled { restartAssertion() }
        }
    }
    @Published var isIndefinite: Bool = true {
        didSet {
            if isEnabled { restartAssertion() }
        }
    }
    @Published var durationMinutes: Int = 30 {
        didSet {
            if isEnabled && !isIndefinite { restartAssertion() }
        }
    }

    // MARK: - Runtime State
    @Published private(set) var remainingSeconds: Int = 0

    var formattedRemaining: String {
        let m = remainingSeconds / 60
        let s = remainingSeconds % 60
        return String(format: "%d:%02d", m, s)
    }

    // MARK: - Private
    private var assertionID: IOPMAssertionID = 0
    private var hasAssertion = false
    private var countdownTimer: Timer?

    // MARK: - Monitoring

    func startMonitoring() {
        guard isEnabled else { return }
        releaseAssertion()
        createAssertion()

        if !isIndefinite {
            remainingSeconds = durationMinutes * 60
            startCountdown()
        } else {
            remainingSeconds = 0
        }
    }

    func stopMonitoring() {
        releaseAssertion()
        stopCountdown()
        remainingSeconds = 0
    }

    // MARK: - IOPMAssertion

    private func createAssertion() {
        let assertionType: String = keepDisplayOn
            ? kIOPMAssertionTypePreventUserIdleDisplaySleep as String
            : kIOPMAssertionTypePreventUserIdleSystemSleep as String

        let reason = "Mac PowerToys Awake" as CFString
        var id: IOPMAssertionID = 0

        let result = IOPMAssertionCreateWithName(
            assertionType as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &id
        )

        if result == kIOReturnSuccess {
            assertionID = id
            hasAssertion = true
        }
    }

    private func releaseAssertion() {
        if hasAssertion {
            IOPMAssertionRelease(assertionID)
            hasAssertion = false
            assertionID = 0
        }
    }

    private func restartAssertion() {
        stopMonitoring()
        startMonitoring()
    }

    // MARK: - Countdown Timer

    private func startCountdown() {
        stopCountdown()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.remainingSeconds > 1 {
                    self.remainingSeconds -= 1
                } else {
                    self.isEnabled = false
                }
            }
        }
        RunLoop.main.add(countdownTimer!, forMode: .common)
    }

    private func stopCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
    }
}
