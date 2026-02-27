import SwiftUI

struct ScreenRulerView: View {
    @EnvironmentObject var model: ScreenRulerModel
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

                Text("Screen Ruler")
                    .font(.system(.headline, design: .rounded))

                Spacer()
            }

            Divider()

            ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {

            Toggle(isOn: $model.isEnabled) {
                Label("Enable Screen Ruler", systemImage: "ruler")
                    .font(.system(.body, design: .rounded))
            }
            .toggleStyle(.switch)

            // Capture status (diagnostic)
            if model.isActive {
                Text("Edges: L=\(model.currentEdges.left) R=\(model.currentEdges.right) T=\(model.currentEdges.top) B=\(model.currentEdges.bottom)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.orange)
                Text("Measure: H=\(max(1, model.currentEdges.left + model.currentEdges.right)) V=\(max(1, model.currentEdges.top + model.currentEdges.bottom))")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.orange)
            }

            if model.isEnabled {
                Divider()

                // Default mode
                VStack(alignment: .leading, spacing: 4) {
                    Text("Default Mode")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                    Picker("", selection: $model.measurementMode) {
                        ForEach(MeasurementMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                // Pixel tolerance
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Pixel Tolerance")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(model.pixelTolerance))")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    Slider(value: $model.pixelTolerance, in: 0...255, step: 1)
                }

                // Per-channel edge detection
                Toggle(isOn: $model.perChannelDetection) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Per-Channel Edge Detection")
                            .font(.system(.subheadline, design: .rounded))
                        Text("Test each color channel individually")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.tertiary)
                    }
                }
                .toggleStyle(.switch)

                // Continuous capture
                Toggle(isOn: $model.continuousCapture) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Continuous Capture")
                            .font(.system(.subheadline, design: .rounded))
                        Text("Uses more resources when enabled")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.tertiary)
                    }
                }
                .toggleStyle(.switch)

                // Extra unit
                HStack {
                    Text("Extra Unit")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("", selection: $model.extraUnit) {
                        ForEach(ExtraUnit.allCases, id: \.self) { unit in
                            Text(unit.rawValue).tag(unit)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 130)
                }

                // Line color
                HStack {
                    Text("Line Color")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                    ColorPicker("", selection: Binding(
                        get: { Color(nsColor: model.lineColor) },
                        set: { model.lineColor = NSColor($0) }
                    ))
                    .labelsHidden()
                }

                // Draw feet
                Toggle(isOn: $model.showFeet) {
                    Text("Draw Feet on Lines")
                        .font(.system(.subheadline, design: .rounded))
                }
                .toggleStyle(.switch)

                Divider()

                // Keyboard shortcuts info
                VStack(alignment: .leading, spacing: 4) {
                    Text("Shortcuts while active")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                    Group {
                        shortcutRow("⌘1", "Bounds mode")
                        shortcutRow("⌘2", "Spacing mode")
                        shortcutRow("⌘3", "Horizontal mode")
                        shortcutRow("⌘4", "Vertical mode")
                        shortcutRow("Esc", "Close ruler")
                        shortcutRow("Scroll ↕", "Adjust tolerance")
                        shortcutRow("Click", "Copy to clipboard")
                    }
                }
            }
            } // VStack inside ScrollView
            } // ScrollView
        }
    }

    private func shortcutRow(_ key: String, _ desc: String) -> some View {
        HStack(spacing: 6) {
            Text(key)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.quaternary)
                .frame(width: 60, alignment: .trailing)
            Text(desc)
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.tertiary)
        }
    }
}
