import SwiftUI

struct ScreenAnnotationView: View {
    @EnvironmentObject var model: ScreenAnnotationModel
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

                Text("Screen Annotation")
                    .font(.system(.headline, design: .rounded))

                Spacer()
            }

            Divider()

            ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {

            Toggle(isOn: $model.isEnabled) {
                Label("Enable Screen Annotation", systemImage: "pencil.tip.crop.circle")
                    .font(.system(.body, design: .rounded))
            }
            .toggleStyle(.switch)

            if model.isEnabled {
                HStack {
                    Image(systemName: "circle.fill")
                        .foregroundColor(.green)
                        .font(.caption2)
                    Text("Annotation mode active — draw on screen")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // Default color
            HStack {
                Text("Default Color")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                ColorPicker("", selection: Binding(
                    get: { Color(nsColor: model.defaultColor) },
                    set: { model.defaultColor = NSColor($0) }
                ))
                .labelsHidden()
            }

            // Default line width
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Default Line Width")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(model.defaultLineWidth))px")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                Slider(value: $model.defaultLineWidth, in: 1...12, step: 1)
            }

            // Dim background
            Toggle(isOn: $model.dimBackground) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Dim Background")
                        .font(.system(.subheadline, design: .rounded))
                    Text("Slightly darkens the screen for better visibility")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
            }
            .toggleStyle(.switch)

            Divider()

            // Shortcuts info
            VStack(alignment: .leading, spacing: 4) {
                Text("Shortcuts")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                Group {
                    shortcutRow("⌃⌥D", "Toggle annotation mode")
                    shortcutRow("⌘Z", "Undo last drawing")
                    shortcutRow("Right Click", "Undo last drawing")
                    shortcutRow("Esc", "Close annotation")
                }
            }

            // Tools info
            VStack(alignment: .leading, spacing: 4) {
                Text("Available Tools")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                Group {
                    toolRow("pencil", "Freehand drawing")
                    toolRow("line.diagonal", "Straight line")
                    toolRow("arrow.right", "Arrow")
                    toolRow("rectangle", "Rectangle")
                    toolRow("circle", "Ellipse")
                    toolRow("textformat", "Text annotation")
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
                .frame(width: 80, alignment: .trailing)
            Text(desc)
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.tertiary)
        }
    }

    private func toolRow(_ icon: String, _ desc: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.quaternary)
                .frame(width: 20, alignment: .center)
            Text(desc)
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.tertiary)
        }
    }
}
