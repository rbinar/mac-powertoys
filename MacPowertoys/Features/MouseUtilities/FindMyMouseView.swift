import SwiftUI

struct FindMyMouseView: View {
    @EnvironmentObject var model: FindMyMouseModel
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Navigation header
            HStack {
                Button {
                    onBack()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)

                Text("Find My Mouse")
                    .font(.system(.headline, design: .rounded))

                Spacer()
            }

            Divider()

            // Enable toggle
            Toggle(isOn: $model.isEnabled) {
                Label("Enable Find My Mouse", systemImage: "cursorarrow.rays")
                    .font(.system(.body, design: .rounded))
            }
            .toggleStyle(.switch)

            HStack(spacing: 4) {
                Image(systemName: "keyboard")
                    .font(.caption2)
                Text("Toggle: Double ⌃")
                    .font(.system(.caption, design: .rounded))
            }
            .foregroundStyle(.tertiary)

            if model.isEnabled {
                Divider()

                // Activation method
                HStack {
                    Text("Activation")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("", selection: $model.activationMethod) {
                        ForEach(ActivationMethod.allCases) { method in
                            Text(method.rawValue).tag(method)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }

                // Overlay opacity
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Overlay Opacity")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(model.overlayOpacity * 100))%")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    Slider(value: $model.overlayOpacity, in: 0.1...1.0, step: 0.05)
                }

                // Background color
                HStack {
                    Text("Background")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                    ColorPicker("", selection: Binding(
                        get: { Color(nsColor: model.backgroundColor) },
                        set: { model.backgroundColor = NSColor($0) }
                    ))
                    .labelsHidden()
                }

                // Spotlight radius
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Spotlight Radius")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(model.spotlightRadius))px")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    Slider(value: $model.spotlightRadius, in: 50...300, step: 10)
                }

                // Animation duration
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Animation Duration")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(model.animationDurationMs))ms")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    Slider(value: $model.animationDurationMs, in: 100...2000, step: 50)
                }

                Divider()

                // Test button
                Button {
                    if model.isSpotlightActive {
                        model.dismissSpotlight()
                    } else {
                        model.activateSpotlight()
                    }
                } label: {
                    HStack {
                        Image(systemName: model.isSpotlightActive ? "eye.slash" : "eye")
                        Text(model.isSpotlightActive ? "Dismiss Spotlight" : "Test Spotlight")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}
