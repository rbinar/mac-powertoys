import SwiftUI

struct ScreenRulerView: View {
    @EnvironmentObject var model: ScreenRulerModel
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Navigation header
            FeatureHeader(title: "Screen Ruler", onBack: onBack)

            Divider()

            ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {

            Toggle(isOn: $model.isEnabled) {
                Label("Enable Screen Ruler", systemImage: "ruler")
                    .font(.body)
            }
            .toggleStyle(.switch)

            Text(model.isEnabled ? "Start: ⌃⌥R · ESC to exit" : "Enable to use ⌃⌥R")
                .font(.caption)
                .foregroundStyle(.secondary)

            Group {
                Divider()

                // Default mode
                VStack(alignment: .leading, spacing: 4) {
                    Text("Default Mode")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Picker("Default Mode", selection: $model.measurementMode) {
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
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(model.pixelTolerance))")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $model.pixelTolerance, in: 0...255, step: 1)
                        .accessibilityLabel("Pixel Tolerance")
                        .accessibilityValue("\(Int(model.pixelTolerance))")
                }

                // Per-channel edge detection
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Per-Channel Edge Detection")
                            .font(.subheadline)
                        Text("Test each color channel individually")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("Per-Channel Edge Detection", isOn: $model.perChannelDetection)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }

                // Continuous capture
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Continuous Capture")
                            .font(.subheadline)
                        Text("Uses more resources when enabled")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("Continuous Capture", isOn: $model.continuousCapture)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }

                // Extra unit
                HStack {
                    Text("Extra Unit")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("Extra Unit", selection: $model.extraUnit) {
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
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    ColorPicker("Line Color", selection: Binding(
                        get: { Color(nsColor: model.lineColor) },
                        set: { model.lineColor = NSColor($0) }
                    ))
                    .labelsHidden()
                }

                // Draw feet
                HStack {
                    Text("Draw Feet on Lines")
                        .font(.subheadline)
                    Spacer()
                    Toggle("Draw Feet on Lines", isOn: $model.showFeet)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }

                Divider()

                // Keyboard shortcuts info
                VStack(alignment: .leading, spacing: 4) {
                    SectionHeader("Shortcuts while active")
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
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)
            Text(desc)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
