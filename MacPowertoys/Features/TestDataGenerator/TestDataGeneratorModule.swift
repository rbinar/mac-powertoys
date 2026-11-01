import SwiftUI

extension TestDataGeneratorModel: ModuleModel {}

enum TestDataGeneratorModule {
    @MainActor static let module = ModuleDescriptor(
        id: "testDataGenerator",
        make: { TestDataGeneratorModel() },
        view: { AnyView(TestDataGeneratorView(onBack: $0)) },
        commands: { m in [
            PaletteCommand(id: "testDataGenerator.open", title: "Test Data Generator", subtitle: "Generate fake data", symbol: "wand.and.stars", group: .tools, keywords: ["fake", "mock"])
        ] }
    ).erased()
}
