import SwiftUI

struct FindMyMouseView: View {
    @EnvironmentObject var model: FindMyMouseModel
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Navigation header
            FeatureHeader(title: "Find My Mouse", onBack: onBack)

            Divider()

            ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {

            // Enable toggle
            HStack {
                Label("Enable Find My Mouse", systemImage: "cursorarrow.rays")
                    .font(.body)
                Spacer()
                Toggle("Enable Find My Mouse", isOn: $model.isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            HStack(spacing: 4) {
                Image(systemName: "keyboard")
                    .font(.caption2)
                Text(model.isEnabled
                     ? "Double-tap \(model.activationMethod.rawValue.replacingOccurrences(of: "Double ", with: "")) to show · ESC or click to dismiss"
                     : "Enable to use the double-tap shortcut")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)

            Group {
                Divider()

                // Activation method
                HStack {
                    Text("Activation")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("Activation Method", selection: $model.activationMethod) {
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
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(model.overlayOpacity * 100))%")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $model.overlayOpacity, in: 0.1...1.0, step: 0.05)
                        .accessibilityLabel("Overlay Opacity")
                        .accessibilityValue("\(Int(model.overlayOpacity * 100))%")
                }

                // Background color
                HStack {
                    Text("Background")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    ColorPicker("Background", selection: Binding(
                        get: { Color(nsColor: model.backgroundColor) },
                        set: { model.backgroundColor = NSColor($0) }
                    ))
                    .labelsHidden()
                }

                // Spotlight radius
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Spotlight Radius")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(model.spotlightRadius))px")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $model.spotlightRadius, in: 50...300, step: 10)
                        .accessibilityLabel("Spotlight Radius")
                        .accessibilityValue("\(Int(model.spotlightRadius)) pixels")
                }

                // Animation duration
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Animation Duration")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(model.animationDurationMs))ms")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $model.animationDurationMs, in: 100...2000, step: 50)
                        .accessibilityLabel("Animation Duration")
                        .accessibilityValue("\(Int(model.animationDurationMs)) milliseconds")
                }

                Divider()

                // Test button
                Button {
                    model.toggleSpotlightFromButton()
                } label: {
                    HStack {
                        Image(systemName: model.isSpotlightActive ? "eye.slash" : "eye")
                        Text(model.isSpotlightActive ? "Dismiss Spotlight" : "Test Spotlight")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            } // VStack inside ScrollView
            } // ScrollView
        }
    }
}
