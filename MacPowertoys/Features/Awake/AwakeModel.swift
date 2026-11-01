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
            UserDefaults.standard.set(keepDisplayOn, forKey: "awake.keepDisplayOn")
            if isEnabled { restartAssertion() }
        }
    }
    @Published var isIndefinite: Bool = true {
        didSet {
            UserDefaults.standard.set(isIndefinite, forKey: "awake.isIndefinite")
            if isEnabled { restartAssertion() }
        }
    }
    @Published var durationMinutes: Int = 30 {
        didSet {
            UserDefaults.standard.set(durationMinutes, forKey: "awake.durationMinutes")
            if isEnabled && !isIndefinite { restartAssertion() }
        }
    }

    // MARK: - Runtime State
    @Published private(set) var remainingSeconds: Int = 0

    var formattedRemaining: String { Self.formatRemaining(remainingSeconds) }

    /// "29:59" below one hour, "4:00:00" from one hour up.
    static func formatRemaining(_ seconds: Int) -> String {
        guard seconds >= 3600 else { return String(format: "%d:%02d", seconds / 60, seconds % 60) }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .positional
        formatter.allowedUnits = [.hour, .minute, .second]
        return formatter.string(from: TimeInterval(seconds)) ?? ""
    }

    // MARK: - Private
    private var assertionID: IOPMAssertionID = 0
    private var hasAssertion = false
    private var countdownTimer: Timer?

    // MARK: - Init

    init() {
        // isEnabled stays false here, so the didSets below never touch the assertion.
        let d = UserDefaults.standard
        if d.object(forKey: "awake.keepDisplayOn") != nil { keepDisplayOn = d.bool(forKey: "awake.keepDisplayOn") }
        if d.object(forKey: "awake.isIndefinite") != nil { isIndefinite = d.bool(forKey: "awake.isIndefinite") }
        if d.object(forKey: "awake.durationMinutes") != nil { durationMinutes = d.integer(forKey: "awake.durationMinutes") }
    }

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
