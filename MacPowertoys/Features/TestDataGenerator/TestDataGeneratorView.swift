import SwiftUI

struct TestDataGeneratorView: View {
    let onBack: () -> Void
    @EnvironmentObject var model: TestDataGeneratorModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Navigation header
            FeatureHeader(title: "Test Data Generator", onBack: onBack)

            
            Divider()
            
            ScrollView {
                VStack(spacing: 20) {
                    
                    // Generated Data Display
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Last Generated (Copied to Clipboard):")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Text(model.generatedData.isEmpty ? "No data generated yet." : model.generatedData)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .cardBackground()
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    
                    Divider()
                    
                    // Actions
                    VStack(alignment: .leading, spacing: 16) {
                        Group {
                            SectionHeader("Identifiers")
                            
                            actionButton(title: "UUID", icon: "number") {
                                model.generateUUID()
                            }
                        }
                        
                        Group {
                            SectionHeader("Names & Dates")
                            
                            HStack(spacing: 12) {
                                actionButton(title: "Random Name", icon: "person") {
                                    model.generateName()
                                }
                                
                                actionButton(title: "Random Date", icon: "calendar") {
                                    model.generateDate()
                                }
                            }
                        }
                        
                        Group {
                            SectionHeader("Lorem Ipsum")
                            
                            HStack(spacing: 12) {
                                actionButton(title: "Short", icon: "text.alignleft") {
                                    model.generateLoremIpsum(length: .short)
                                }
                                
                                actionButton(title: "Medium", icon: "text.alignleft") {
                                    model.generateLoremIpsum(length: .medium)
                                }
                            }
                            
                            actionButton(title: "Long", icon: "text.alignleft") {
                                model.generateLoremIpsum(length: .long)
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func actionButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .frame(width: 20)
                Text(title)
                Spacer()
                Image(systemName: "doc.on.doc")
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .cardBackground()
        }
        .buttonStyle(.plain)
    }
}
