import SwiftUI

struct WebhookNotifierView: View {
    @EnvironmentObject var model: WebhookNotifierModel
    let onBack: () -> Void
    
    @State private var showingAddAlert = false
    @State private var newTopicLabel = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                
                Text("Webhook Notifier")
                    .font(.system(.title3, design: .rounded))
                    .fontWeight(.semibold)
                
                Spacer()
                
                Toggle("", isOn: $model.isEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            
            Text("Receive macOS notifications from webhooks.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
            
            Divider()
            
            if model.isEnabled {
                // Topics List
                VStack(alignment: .leading, spacing: 12) {
                    Text("Webhooks")
                        .font(.system(.headline, design: .rounded))
                    
                    if model.topics.isEmpty {
                        Text("No webhooks configured.")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.tertiary)
                            .padding(.vertical, 8)
                    } else {
                        ScrollView {
                            VStack(spacing: 10) {
                                ForEach(model.topics) { topic in
                                    topicRow(for: topic)
                                }
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 2)
                        }
                        .frame(maxHeight: 200)
                    }
                    
                    Button {
                        newTopicLabel = "Webhook #\(model.topics.count + 1)"
                        showingAddAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Add Webhook")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
                Divider()
                
                // Settings
                VStack(alignment: .leading, spacing: 12) {
                    Text("Settings")
                        .font(.system(.headline, design: .rounded))
                    
                    HStack {
                        Text("Notification Sound")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Toggle("", isOn: $model.notificationSound)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .controlSize(.mini)
                    }
                    
                    HStack {
                        Text("Server URL")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.secondary)
                        Spacer()
                        TextField("Server URL", text: $model.serverURL)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 180)
                            .font(.system(.caption, design: .monospaced))
                    }
                }
                
                // Last Message
                if let last = model.lastMessage {
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Last Message")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                        
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(last.label)
                                    .font(.system(.caption, design: .rounded))
                                    .fontWeight(.semibold)
                                if let title = last.title {
                                    Text(title)
                                        .font(.system(.caption, design: .rounded))
                                        .fontWeight(.medium)
                                }
                                Text(last.body)
                                    .font(.system(.caption2, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Text(last.date, style: .time)
                                .font(.system(.caption2, design: .rounded))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
                    }
                }
            } else {
                Spacer()
            }
        }
        .padding(16)
        .alert("Add Webhook", isPresented: $showingAddAlert) {
            TextField("Label (e.g. GitHub, CI/CD)", text: $newTopicLabel)
            Button("Cancel", role: .cancel) { }
            Button("Add") {
                if !newTopicLabel.isEmpty {
                    model.addTopic(label: newTopicLabel)
                }
            }
        } message: {
            Text("Enter a label for the new webhook.")
        }
    }
    
    @ViewBuilder
    private func topicRow(for topic: WebhookTopic) -> some View {
        let url = "\(model.serverURL)/\(topic.topicID)"
        let isConnected = model.connectionStates[topic.id] ?? false
        
        HStack(spacing: 12) {
            // Toggle
            Toggle("", isOn: Binding(
                get: { topic.isActive },
                set: { _ in model.toggleTopic(id: topic.id) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.small)
            
            // Label & URL
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(topic.isActive ? (isConnected ? Color.green : Color.orange) : Color.gray)
                        .frame(width: 6, height: 6)
                        .help(topic.isActive ? (isConnected ? "Connected" : "Connecting...") : "Inactive")
                    
                    Text(topic.label)
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.medium)
                }
                
                Text(url)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            
            Spacer()
            
            // Test Button
            Button {
                model.sendTestNotification(for: topic)
            } label: {
                Image(systemName: "paperplane.fill")
                    .foregroundStyle(.blue.opacity(0.8))
            }
            .buttonStyle(.plain)
            .help("Send Test Notification")
            .disabled(!topic.isActive)
            
            // Copy Button
            Button {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(url, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Copy URL")
            
            // Delete Button
            Button {
                model.removeTopic(id: topic.id)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red.opacity(0.8))
            }
            .buttonStyle(.plain)
            .help("Delete Webhook")
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
    }
}
