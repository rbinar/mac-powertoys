import SwiftUI

extension PomodoroTimerModel: ModuleModel {}

enum PomodoroTimerModule {
    @MainActor static let module = ModuleDescriptor(
        id: "pomodoroTimer",
        title: "Pomodoro Timer", icon: "timer",
        make: { PomodoroTimerModel() },
        status: { m in
            guard m.isEnabled else { return "Off" }
            switch m.currentPhase {
            case .idle: return "Ready"
            case .focus: return "Focus \(m.formattedRemaining)"
            case .shortBreak: return "Break \(m.formattedRemaining)"
            case .longBreak: return "Break \(m.formattedRemaining)"
            }
        },
        toggle: \.isEnabled,
        view: { AnyView(PomodoroTimerView(onBack: $0)) },
        commands: { m in [
            PaletteCommand(id: "pomodoro.toggle", title: "Pomodoro", subtitle: "Start a focus session", symbol: "timer", group: .modes, keywords: ["focus", "timer"], isOn: { m.isEnabled }, run: { m.isEnabled.toggle() })
        ] }
    ).erased()
}
