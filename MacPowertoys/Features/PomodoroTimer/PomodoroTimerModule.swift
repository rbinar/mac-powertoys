import SwiftUI

extension PomodoroTimerModel: ModuleModel {}

enum PomodoroTimerModule {
    @MainActor static let module = ModuleDescriptor(
        id: "pomodoroTimer",
        make: { PomodoroTimerModel() },
        view: { AnyView(PomodoroTimerView(onBack: $0)) },
        commands: { m in [
            PaletteCommand(id: "pomodoro.toggle", title: "Pomodoro", subtitle: "Start a focus session", symbol: "timer", group: .modes, keywords: ["focus", "timer"], isOn: { m.isEnabled }, run: { m.isEnabled.toggle() })
        ] }
    ).erased()
}
