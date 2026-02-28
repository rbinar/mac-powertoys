import Foundation
import AppKit
import UserNotifications

@MainActor
final class PomodoroTimerModel: ObservableObject {

    // MARK: - Phase

    enum Phase: String {
        case idle = "Idle"
        case focus = "Focus"
        case shortBreak = "Short Break"
        case longBreak = "Long Break"
    }

    // MARK: - Settings

    @Published var isEnabled: Bool = false {
        didSet {
            if isEnabled { startMonitoring() } else { stopMonitoring() }
        }
    }

    @Published var focusMinutes: Int = 25 {
        didSet { UserDefaults.standard.set(focusMinutes, forKey: "pomodoroTimer.focusMinutes") }
    }
    @Published var shortBreakMinutes: Int = 5 {
        didSet { UserDefaults.standard.set(shortBreakMinutes, forKey: "pomodoroTimer.shortBreakMinutes") }
    }
    @Published var longBreakMinutes: Int = 15 {
        didSet { UserDefaults.standard.set(longBreakMinutes, forKey: "pomodoroTimer.longBreakMinutes") }
    }
    @Published var sessionsBeforeLongBreak: Int = 4 {
        didSet { UserDefaults.standard.set(sessionsBeforeLongBreak, forKey: "pomodoroTimer.sessionsBeforeLongBreak") }
    }
    @Published var autoStartBreaks: Bool = true {
        didSet { UserDefaults.standard.set(autoStartBreaks, forKey: "pomodoroTimer.autoStartBreaks") }
    }
    @Published var autoStartFocus: Bool = false {
        didSet { UserDefaults.standard.set(autoStartFocus, forKey: "pomodoroTimer.autoStartFocus") }
    }
    @Published var soundEnabled: Bool = true {
        didSet { UserDefaults.standard.set(soundEnabled, forKey: "pomodoroTimer.soundEnabled") }
    }

    // MARK: - Runtime State

    @Published private(set) var currentPhase: Phase = .idle
    @Published private(set) var remainingSeconds: Int = 0
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var completedSessions: Int = 0
    @Published private(set) var totalCompletedSessions: Int = 0

    var formattedRemaining: String {
        let m = remainingSeconds / 60
        let s = remainingSeconds % 60
        return String(format: "%d:%02d", m, s)
    }

    var progress: Double {
        guard totalSecondsForCurrentPhase > 0 else { return 0 }
        return 1.0 - Double(remainingSeconds) / Double(totalSecondsForCurrentPhase)
    }

    var phaseColor: String {
        switch currentPhase {
        case .idle: return "secondary"
        case .focus: return "red"
        case .shortBreak: return "green"
        case .longBreak: return "blue"
        }
    }

    // MARK: - Private

    private var countdownTimer: Timer?
    private var totalSecondsForCurrentPhase: Int = 0

    // MARK: - Init

    init() {
        loadSettings()
        requestNotificationPermission()
    }

    // MARK: - Lifecycle

    func startMonitoring() {
        guard isEnabled else { return }
        if currentPhase == .idle {
            startFocus()
        }
    }

    func stopMonitoring() {
        stopTimer()
        currentPhase = .idle
        remainingSeconds = 0
        isRunning = false
        completedSessions = 0
    }

    // MARK: - Controls

    func startFocus() {
        currentPhase = .focus
        totalSecondsForCurrentPhase = focusMinutes * 60
        remainingSeconds = totalSecondsForCurrentPhase
        isRunning = true
        startTimer()
    }

    func togglePause() {
        if isRunning {
            stopTimer()
            isRunning = false
        } else {
            isRunning = true
            startTimer()
        }
    }

    func skipPhase() {
        phaseCompleted()
    }

    func resetSession() {
        stopTimer()
        completedSessions = 0
        currentPhase = .idle
        remainingSeconds = 0
        isRunning = false
        totalSecondsForCurrentPhase = 0
    }

    // MARK: - Phase Transitions

    private func phaseCompleted() {
        stopTimer()

        if currentPhase == .focus {
            completedSessions += 1
            totalCompletedSessions += 1
            UserDefaults.standard.set(totalCompletedSessions, forKey: "pomodoroTimer.totalCompletedSessions")

            if completedSessions >= sessionsBeforeLongBreak {
                sendNotification(title: "Long Break Time!", body: "You completed \(sessionsBeforeLongBreak) sessions. Take a long break.")
                playSound()
                startLongBreak()
            } else {
                sendNotification(title: "Break Time!", body: "Session \(completedSessions)/\(sessionsBeforeLongBreak) done. Take a short break.")
                playSound()
                startShortBreak()
            }
        } else {
            // Break completed
            if currentPhase == .longBreak {
                completedSessions = 0
            }
            sendNotification(title: "Back to Work!", body: "Break is over. Time to focus.")
            playSound()
            if autoStartFocus {
                startFocus()
            } else {
                currentPhase = .idle
                remainingSeconds = 0
                isRunning = false
                totalSecondsForCurrentPhase = 0
            }
        }
    }

    private func startShortBreak() {
        currentPhase = .shortBreak
        totalSecondsForCurrentPhase = shortBreakMinutes * 60
        remainingSeconds = totalSecondsForCurrentPhase
        if autoStartBreaks {
            isRunning = true
            startTimer()
        } else {
            isRunning = false
        }
    }

    private func startLongBreak() {
        currentPhase = .longBreak
        totalSecondsForCurrentPhase = longBreakMinutes * 60
        remainingSeconds = totalSecondsForCurrentPhase
        if autoStartBreaks {
            isRunning = true
            startTimer()
        } else {
            isRunning = false
        }
    }

    // MARK: - Timer

    private func startTimer() {
        stopTimer()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.remainingSeconds > 1 {
                    self.remainingSeconds -= 1
                } else {
                    self.phaseCompleted()
                }
            }
        }
        RunLoop.main.add(countdownTimer!, forMode: .common)
    }

    private func stopTimer() {
        countdownTimer?.invalidate()
        countdownTimer = nil
    }

    // MARK: - Notifications

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    // MARK: - Sound

    private func playSound() {
        guard soundEnabled else { return }
        NSSound.beep()
    }

    // MARK: - Persistence

    private func loadSettings() {
        let d = UserDefaults.standard
        if d.object(forKey: "pomodoroTimer.focusMinutes") != nil {
            focusMinutes = d.integer(forKey: "pomodoroTimer.focusMinutes")
        }
        if d.object(forKey: "pomodoroTimer.shortBreakMinutes") != nil {
            shortBreakMinutes = d.integer(forKey: "pomodoroTimer.shortBreakMinutes")
        }
        if d.object(forKey: "pomodoroTimer.longBreakMinutes") != nil {
            longBreakMinutes = d.integer(forKey: "pomodoroTimer.longBreakMinutes")
        }
        if d.object(forKey: "pomodoroTimer.sessionsBeforeLongBreak") != nil {
            sessionsBeforeLongBreak = d.integer(forKey: "pomodoroTimer.sessionsBeforeLongBreak")
        }
        if d.object(forKey: "pomodoroTimer.autoStartBreaks") != nil {
            autoStartBreaks = d.bool(forKey: "pomodoroTimer.autoStartBreaks")
        }
        if d.object(forKey: "pomodoroTimer.autoStartFocus") != nil {
            autoStartFocus = d.bool(forKey: "pomodoroTimer.autoStartFocus")
        }
        if d.object(forKey: "pomodoroTimer.soundEnabled") != nil {
            soundEnabled = d.bool(forKey: "pomodoroTimer.soundEnabled")
        }
        totalCompletedSessions = d.integer(forKey: "pomodoroTimer.totalCompletedSessions")
    }
}
