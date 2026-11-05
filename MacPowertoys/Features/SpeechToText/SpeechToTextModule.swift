import SwiftUI

extension SpeechToTextModel: ModuleModel {}

enum SpeechToTextModule {
    @MainActor static let module = ModuleDescriptor(
        id: "speechToText",
        title: "Speech to Text", icon: "waveform.badge.mic",
        make: { SpeechToTextModel() },
        status: { $0.hubStatusText },
        view: { AnyView(SpeechToTextView(onBack: $0)) },
        commands: { m in [
            PaletteCommand(id: "speechToText.open", title: "Speech to Text", subtitle: "Transcribe audio", symbol: "waveform.badge.mic", group: .tools, keywords: ["whisper", "transcribe"])
        ] }
    ).erased()
}
