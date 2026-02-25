import SwiftUI
import AppKit

enum Feature: Hashable {
    case colorPicker
    case mouseUtilitiesHub
    case findMyMouse
    case mouseHighlighter
    case crosshairs
    case cursorWrap
    case screenRuler
}

struct ContentView: View {
    @EnvironmentObject var model: ColorModel
    @EnvironmentObject var findMyMouseModel: FindMyMouseModel
    @EnvironmentObject var mouseHighlighterModel: MouseHighlighterModel
    @EnvironmentObject var crosshairsModel: CrosshairsModel
    @EnvironmentObject var cursorWrapModel: CursorWrapModel
    @EnvironmentObject var screenRulerModel: ScreenRulerModel
    @State private var activeFeature: Feature? = nil
    @State private var showingQuitAlert = false

    var body: some View {
        Group {
            if let feature = activeFeature {
                featureView(for: feature)
            } else {
                ScrollView {
                    featureHub
                }
                .frame(maxHeight: 500)
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
                Text("Mac PowerToys")
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

            // Screen Ruler module
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        activeFeature = .screenRuler
                    }
                } label: {
                    HStack {
                        Text("Screen Ruler")
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
                    Image(systemName: "ruler")
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

                    Text(screenRulerModel.isEnabled ? "Active" : "Disabled")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer()

                    Toggle("", isOn: $screenRulerModel.isEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .controlSize(.mini)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(.quaternary.opacity(0.45))
            )

            // Mouse Utilities module
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        activeFeature = .mouseUtilitiesHub
                    }
                } label: {
                    HStack {
                        Text("Mouse Utilities")
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
                    Image(systemName: "cursorarrow.rays")
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

                    Text(mouseUtilitiesStatusText)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer()
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
                    showingQuitAlert = true
                } label: {
                    Label("Quit", systemImage: "power")
                        .labelStyle(.titleAndIcon)
                }
                .keyboardShortcut("q")
                .buttonStyle(.bordered)
                .alert("Quit Mac PowerToys?", isPresented: $showingQuitAlert) {
                    Button("Cancel", role: .cancel) { }
                    Button("Quit", role: .destructive) {
                        NSApplication.shared.terminate(nil)
                    }
                } message: {
                    Text("Are you sure you want to quit?")
                }
            }
        }
    }

    // MARK: - Feature Views

    @ViewBuilder
    private func featureView(for feature: Feature) -> some View {
        switch feature {
        case .colorPicker:
            ColorPickerView(onBack: { goBack() })
                .environmentObject(model)
        case .mouseUtilitiesHub:
            mouseUtilitiesHubView
        case .findMyMouse:
            FindMyMouseView(onBack: { goBack(to: .mouseUtilitiesHub) })
                .environmentObject(findMyMouseModel)
        case .mouseHighlighter:
            MouseHighlighterView(onBack: { goBack(to: .mouseUtilitiesHub) })
                .environmentObject(mouseHighlighterModel)
        case .crosshairs:
            CrosshairsView(onBack: { goBack(to: .mouseUtilitiesHub) })
                .environmentObject(crosshairsModel)
        case .cursorWrap:
            CursorWrapView(onBack: { goBack(to: .mouseUtilitiesHub) })
                .environmentObject(cursorWrapModel)
        case .screenRuler:
            ScreenRulerView(onBack: { goBack() })
                .environmentObject(screenRulerModel)
        }
    }

    private func goBack(to feature: Feature? = nil) {
        withAnimation(.easeInOut(duration: 0.15)) {
            activeFeature = feature
        }
    }

    // MARK: - Mouse Utilities Hub

    private var mouseUtilitiesHubView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Navigation header
            HStack {
                Button { goBack() } label: {
                    Label("Back", systemImage: "chevron.left")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)

                Text("Mouse Utilities")
                    .font(.system(.headline, design: .rounded))

                Spacer()
            }

            Divider()

            mouseUtilityRow(
                title: "Find My Mouse",
                icon: "cursorarrow.rays",
                description: "Spotlight on cursor",
                shortcut: "Double ⌃",
                isEnabled: $findMyMouseModel.isEnabled,
                feature: .findMyMouse
            )

            mouseUtilityRow(
                title: "Mouse Highlighter",
                icon: "hand.tap",
                description: "Highlight clicks",
                shortcut: "Double Left ⌥",
                isEnabled: $mouseHighlighterModel.isEnabled,
                feature: .mouseHighlighter
            )

            mouseUtilityRow(
                title: "Mouse Crosshairs",
                icon: "plus.circle",
                description: "Crosshair overlay",
                shortcut: "Double Right ⌥",
                isEnabled: $crosshairsModel.isEnabled,
                feature: .crosshairs
            )

            mouseUtilityRow(
                title: "Cursor Wrap",
                icon: "arrow.trianglehead.2.counterclockwise",
                description: "Wrap at edges",
                shortcut: nil,
                isEnabled: $cursorWrapModel.isEnabled,
                feature: .cursorWrap
            )
        }
    }

    private func mouseUtilityRow(
        title: String,
        icon: String,
        description: String,
        shortcut: String?,
        isEnabled: Binding<Bool>,
        feature: Feature
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(.white.opacity(0.14))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(.white.opacity(0.18), lineWidth: 0.8)
                )

            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    activeFeature = feature
                }
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.medium)
                    HStack(spacing: 4) {
                        Text(description)
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.tertiary)
                        if let shortcut {
                            Text("·")
                                .font(.system(.caption2, design: .rounded))
                                .foregroundStyle(.quaternary)
                            Text(shortcut)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.quaternary)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            Toggle("", isOn: isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.mini)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helper

    private var mouseUtilitiesStatusText: String {
        let count = [
            findMyMouseModel.isEnabled,
            mouseHighlighterModel.isEnabled,
            crosshairsModel.isEnabled,
            cursorWrapModel.isEnabled
        ].filter { $0 }.count

        if count == 0 { return "All disabled" }
        return "\(count) of 4 enabled"
    }
}
