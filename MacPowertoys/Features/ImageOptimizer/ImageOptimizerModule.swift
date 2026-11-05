import SwiftUI

extension ImageOptimizerModel: ModuleModel {}

enum ImageOptimizerModule {
    @MainActor static let module = ModuleDescriptor(
        id: "imageOptimizer",
        title: "Image Optimizer", icon: "photo.badge.arrow.down",
        make: { ImageOptimizerModel() },
        status: { $0.items.isEmpty ? "Ready" : "\($0.items.count) images" },
        view: { AnyView(ImageOptimizerView(onBack: $0)) },
        commands: { m in [
            PaletteCommand(id: "imageOptimizer.open", title: "Image Optimizer", subtitle: "Compress and resize images", symbol: "photo.badge.arrow.down", group: .tools, keywords: ["compress"])
        ] }
    ).erased()
}
