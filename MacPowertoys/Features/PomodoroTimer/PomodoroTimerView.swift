import SwiftUI

struct PomodoroTimerView: View {
    @EnvironmentObject var model: PomodoroTimerModel
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Navigation header
            HStack {
                Button { onBack() } label: {
                    Label("Back", systemImage: "chevron.left")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)

                Text("Pomodoro Timer")
                    .font(.system(.headline, design: .rounded))

                Spacer()
            }

            Divider()

            // Enable toggle
            Toggle(isOn: $model.isEnabled) {
                Label("Enable Pomodoro", systemImage: "timer")
                    .font(.system(.body, design: .rounded))
            }
            .toggleStyle(.switch)

            if model.isEnabled {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
                        timerDisplay
                        controlButtons
                        sessionIndicator
                        Divider()
                        settingsSection
                    }
                    .padding(.top, 6)
                }
            } else {
                Spacer()
            }
        }
    }

    // MARK: - Timer Display

    private var timerDisplay: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: 8)

            // Progress ring
            Circle()
                .trim(from: 0, to: model.progress)
                .stroke(phaseColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: model.progress)

            // Center content
            VStack(spacing: 4) {
                Text(model.currentPhase.rawValue)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Text(model.formattedRemaining)
                    .font(.system(size: 36, weight: .medium, design: .rounded))
                    .monospacedDigit()
            }
        }
        .frame(width: 160, height: 160)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Controls

    private var controlButtons: some View {
        HStack(spacing: 12) {
            // Reset
            Button {
                model.resetSession()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.body.weight(.semibold))
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(.quaternary)
                    )
            }
            .buttonStyle(.plain)
            .help("Reset")

            // Start / Pause
            Button {
                if model.currentPhase == .idle {
                    model.startFocus()
                } else {
                    model.togglePause()
                }
            } label: {
                Image(systemName: model.isRunning ? "pause.fill" : "play.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(
                        Circle()
                            .fill(phaseColor)
                    )
            }
            .buttonStyle(.plain)
            .help(model.isRunning ? "Pause" : "Start")

            // Skip
            Button {
                model.skipPhase()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.body.weight(.semibold))
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(.quaternary)
                    )
            }
            .buttonStyle(.plain)
            .help("Skip to next phase")
            .disabled(model.currentPhase == .idle)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Session Indicator

    private var sessionIndicator: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                ForEach(0..<model.sessionsBeforeLongBreak, id: \.self) { i in
                    Circle()
                        .fill(i < model.completedSessions ? phaseColor : Color.secondary.opacity(0.3))
                        .frame(width: 10, height: 10)
                }
            }
            Text("Session \(model.completedSessions)/\(model.sessionsBeforeLongBreak)")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.secondary)

            if model.totalCompletedSessions > 0 {
                Text("\(model.totalCompletedSessions) total sessions completed")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Settings

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Settings")
                .font(.system(.subheadline, design: .rounded))
                .fontWeight(.semibold)

            settingRow("Focus Duration", value: $model.focusMinutes, range: 5...60, step: 5, unit: "min")
            settingRow("Short Break", value: $model.shortBreakMinutes, range: 1...30, step: 1, unit: "min")
            settingRow("Long Break", value: $model.longBreakMinutes, range: 5...60, step: 5, unit: "min")

            HStack {
                Text("Sessions before long break")
                    .font(.system(.caption, design: .rounded))
                Spacer()
                Stepper("\(model.sessionsBeforeLongBreak)", value: $model.sessionsBeforeLongBreak, in: 2...8)
                    .font(.system(.caption, design: .rounded))
                    .labelsHidden()
                Text("\(model.sessionsBeforeLongBreak)")
                    .font(.system(.caption, design: .rounded))
                    .monospacedDigit()
                    .frame(width: 20, alignment: .trailing)
            }

            Divider()

            Toggle(isOn: $model.autoStartBreaks) {
                Text("Auto-start breaks")
                    .font(.system(.caption, design: .rounded))
            }
            .toggleStyle(.switch)
            .controlSize(.mini)

            Toggle(isOn: $model.autoStartFocus) {
                Text("Auto-start focus after break")
                    .font(.system(.caption, design: .rounded))
            }
            .toggleStyle(.switch)
            .controlSize(.mini)

            Toggle(isOn: $model.soundEnabled) {
                Text("Sound notification")
                    .font(.system(.caption, design: .rounded))
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
    }

    // MARK: - Helpers

    private func settingRow(_ label: String, value: Binding<Int>, range: ClosedRange<Int>, step: Int, unit: String) -> some View {
        HStack {
            Text(label)
                .font(.system(.caption, design: .rounded))
            Spacer()
            Stepper("", value: value, in: range, step: step)
                .labelsHidden()
            Text("\(value.wrappedValue) \(unit)")
                .font(.system(.caption, design: .rounded))
                .monospacedDigit()
                .frame(width: 46, alignment: .trailing)
        }
    }

    private var phaseColor: Color {
        switch model.currentPhase {
        case .idle: return .secondary
        case .focus: return .red
        case .shortBreak: return .green
        case .longBreak: return .blue
        }
    }
}
