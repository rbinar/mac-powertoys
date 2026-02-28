import SwiftUI
import UniformTypeIdentifiers

struct SpeechToTextView: View {
    @EnvironmentObject var model: SpeechToTextModel
    let onBack: () -> Void
    @State private var showTimestamped: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerSection

            Divider()

            ScrollView(.vertical, showsIndicators: false) {
                switch model.viewState {
                case .idle:
                    dropZoneSection
                case .processing(let message):
                    processingSection(message: message)
                case .completed:
                    completedSection
                case .error(let message):
                    errorSection(message: message)
                }
            }

            Divider()

            footerSection
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            Button(action: onBack) {
                Label("Back", systemImage: "chevron.left")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.plain)

            Label("Speech to Text", systemImage: "waveform.and.mic")
                .font(.system(.headline, design: .rounded))

            Spacer()

            Picker(selection: $model.selectedLanguage) {
                ForEach(model.availableLanguages) { lang in
                    Text(lang.displayName).tag(lang)
                }
            } label: {
                Label(model.selectedLanguage.displayName, systemImage: "globe")
            }
            .pickerStyle(.menu)
            .controlSize(.small)

            Picker(selection: $model.selectedModel) {
                ForEach(model.availableModels) { availableModel in
                    Text(availableModel.displayName).tag(availableModel)
                }
            } label: {
                Label(model.selectedModel.displayName, systemImage: "cpu")
            }
            .pickerStyle(.menu)
            .controlSize(.small)
        }
    }

    // MARK: - Drop Zone (idle)

    private var dropZoneSection: some View {
        VStack(spacing: 10) {
            Image(systemName: "waveform.badge.mic")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)

            Text("Drop audio or video here")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)

            Text("or click to browse")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    model.isDragTargeted ? Color.accentColor : Color.white.opacity(0.15),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6])
                )
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(model.isDragTargeted ? Color.accentColor.opacity(0.08) : Color.white.opacity(0.03))
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { model.selectInputFile() }
        .onDrop(of: [.fileURL], isTargeted: $model.isDragTargeted) { providers in
            handleDrop(providers)
        }
    }

    // MARK: - Processing

    private func processingSection(message: String) -> some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)

            Text(message)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)

            if model.progress > 0 {
                ProgressView(value: model.progress)
                    .padding(.horizontal, 20)
                Text("\(Int(model.progress * 100))%")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    // MARK: - Completed

    private var completedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "globe")
                        .font(.system(.caption, design: .rounded))
                    Text(model.detectedLanguage)
                        .font(.system(.caption, design: .rounded))
                        .fontWeight(.semibold)
                }

                Spacer()

                Picker(selection: $showTimestamped) {
                    Text("Plain").tag(false)
                    Text("Timestamped").tag(true)
                } label: {
                    EmptyView()
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
                .frame(width: 160)
            }

            ScrollView(.vertical, showsIndicators: true) {
                Text(showTimestamped ? model.timestampedTranscriptText : model.transcriptText)
                    .font(.system(showTimestamped ? .caption : .caption, design: showTimestamped ? .monospaced : .rounded))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 120, maxHeight: 200)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.white.opacity(0.15), lineWidth: 0.8)
            )

            HStack(spacing: 8) {
                Button {
                    model.copyTranscript()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                        Text("Copy")
                            .font(.system(.caption, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.white.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)

                Button {
                    model.saveTimestampedTranscript()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.down")
                        Text("Save")
                            .font(.system(.caption, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.white.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)

                Button {
                    model.resetForNewFile()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.badge.plus")
                        Text("New File")
                            .font(.system(.caption, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.white.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Error

    private func errorSection(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundStyle(.orange)

            Text(message)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 8) {
                Button {
                    Task { await model.transcribeSelectedFile() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text("Try Again")
                            .font(.system(.caption, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.white.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)

                Button {
                    model.resetForNewFile()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.badge.plus")
                        Text("New File")
                            .font(.system(.caption, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.white.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Footer

    private var footerSection: some View {
        Text(model.statusMessage)
            .font(.system(.caption, design: .rounded))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Helpers

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            Task { @MainActor in
                model.setInputFile(url)
            }
        }
        return true
    }
}
