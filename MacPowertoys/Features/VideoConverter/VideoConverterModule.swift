import SwiftUI

extension VideoConverterModel: ModuleModel {}

enum VideoConverterModule {
    @MainActor static let module = ModuleDescriptor(
        id: "videoConverter",
        title: "Video Converter", icon: "film",
        make: { VideoConverterModel() },
        view: { AnyView(VideoConverterView(onBack: $0)) },
        commands: { m in [
            PaletteCommand(id: "videoConverter.open", title: "Video Converter", subtitle: "Convert video files", symbol: "film", group: .tools, keywords: ["ffmpeg"])
        ] }
    ).erased()
}
