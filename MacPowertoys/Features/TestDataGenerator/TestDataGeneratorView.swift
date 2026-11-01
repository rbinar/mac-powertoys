import SwiftUI

struct TestDataGeneratorView: View {
    let onBack: () -> Void
    @EnvironmentObject var model: TestDataGeneratorModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Navigation header
            HStack {
                Button { onBack() } label: {
                    Label("Back", systemImage: "chevron.left")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)

                Text("Test Data Generator")
                    .font(.system(.headline, design: .rounded))
                
                Spacer()
            }
            
            
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
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            )
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    
                    Divider()
                    
                    // Actions
                    VStack(alignment: .leading, spacing: 16) {
                        Group {
                            Text("Identifiers")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            actionButton(title: "UUID", icon: "number") {
                                model.generateUUID()
                            }
                        }
                        
                        Group {
                            Text("Names & Dates")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
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
                            Text("Lorem Ipsum")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
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
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
