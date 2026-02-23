import SwiftUI
import AppKit

enum Feature: Hashable {
    case colorPicker
}

struct ContentView: View {
    @EnvironmentObject var model: ColorModel
    @State private var activeFeature: Feature? = nil

    var body: some View {
        Group {
            if let feature = activeFeature {
                featureView(for: feature)
            } else {
                featureHub
            }
        }
        .padding(12)
    }

    // MARK: - Feature Hub (main menu)

    private var featureHub: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text("Mac Powertoys")
                    .font(.system(.headline, design: .rounded))
            }

            Divider()

            // Color Picker module in Control Center style
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        activeFeature = .colorPicker
                    }
                } label: {
                    HStack {
                        Text("Color Picker")
                            .font(.system(.title3, design: .rounded))
                            .fontWeight(.semibold)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                HStack(spacing: 10) {
                    Button {
                        model.pickFromScreen()
                    } label: {
                        Image(systemName: "eyedropper")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 30, height: 30)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(.white.opacity(0.14))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(.white.opacity(0.18), lineWidth: 0.8)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Pick from screen")

                    SwatchView(
                        nsColor: model.nsColor,
                        swatchHeight: 22,
                        swatchCornerRadius: 5,
                        onSelect: { shade in
                            model.selectFromHistory(shade)
                        }
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        model.copy(model.hexString)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 30, height: 30)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(.white.opacity(0.14))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(.white.opacity(0.18), lineWidth: 0.8)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Copy \(model.hexString)")

                    Circle()
                        .fill(Color(nsColor: model.nsColor))
                        .frame(width: 26, height: 26)
                        .overlay(Circle().stroke(.secondary.opacity(0.4), lineWidth: 0.7))
                        .help(model.hexString)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(.quaternary.opacity(0.45))
            )

            Divider()

            // Footer
            HStack {
                Spacer()
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("Quit", systemImage: "power")
                        .labelStyle(.titleAndIcon)
                }
                .keyboardShortcut("q")
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Feature Views

    @ViewBuilder
    private func featureView(for feature: Feature) -> some View {
        switch feature {
        case .colorPicker:
            ColorPickerView(onBack: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    activeFeature = nil
                }
            })
            .environmentObject(model)
        }
    }
}
