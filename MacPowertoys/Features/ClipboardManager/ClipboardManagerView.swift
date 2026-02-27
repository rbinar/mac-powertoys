import SwiftUI

struct ClipboardManagerView: View {
    @EnvironmentObject var model: ClipboardManagerModel
    let onBack: () -> Void
    
    @State private var showingClearConfirm = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Button(action: onBack) {
                    Label("Back", systemImage: "chevron.left")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
                
                Text("Clipboard Manager")
                    .font(.system(.headline, design: .rounded))
                
                Spacer()
                
                Toggle("", isOn: $model.isEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }
            
            Divider()
            
            if model.isEnabled {
                // Search and Settings
                HStack {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search...", text: $model.searchText)
                            .textFieldStyle(.plain)
                        if !model.searchText.isEmpty {
                            Button(action: { model.searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.1)))
                    
                    Menu {
                        Picker("History Limit", selection: $model.maxHistoryCount) {
                            Text("10 items").tag(10)
                            Text("25 items").tag(25)
                            Text("50 items").tag(50)
                            Text("100 items").tag(100)
                        }
                        
                        Divider()
                        
                        Button(role: .destructive, action: { showingClearConfirm = true }) {
                            Label("Clear Unpinned", systemImage: "trash")
                        }
                        .disabled(model.clipboardItems.filter { !$0.isPinned }.isEmpty)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 16))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                
                // List
                if model.clipboardItems.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                        Text("Clipboard history is empty")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundColor(.secondary)
                        Text("Copy text or images to see them here")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else if model.filteredItems.isEmpty {
                    VStack {
                        Spacer()
                        Text("No results found")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(model.filteredItems) { item in
                                ClipboardItemRow(item: item)
                            }
                        }
                        .padding(.trailing, 4)
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "doc.on.clipboard.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("Clipboard Manager is disabled")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundColor(.secondary)
                    Text("Enable it to start saving your clipboard history")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .alert("Clear History", isPresented: $showingClearConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                model.clearHistory()
            }
        } message: {
            Text("Are you sure you want to clear all unpinned clipboard history?")
        }
    }
}

struct ClipboardItemRow: View {
    @EnvironmentObject var model: ClipboardManagerModel
    let item: ClipboardItem
    @State private var isHovered = false
    @State private var showCopiedFeedback = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Content
            if item.type == .text, let text = item.textContent {
                Text(text)
                    .font(.system(.subheadline, design: .rounded))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if item.type == .image, let url = item.imageURL, let nsImage = NSImage(contentsOf: url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                
                VStack(alignment: .leading) {
                    Text("Image")
                        .font(.system(.subheadline, design: .rounded))
                    Text("\(Int(nsImage.size.width)) × \(Int(nsImage.size.height))")
                        .font(.system(.caption, design: .rounded))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            // Actions
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 8) {
                    if item.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.accentColor)
                    }
                    
                    Text(timeAgo(from: item.createdAt))
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
                
                if isHovered {
                    HStack(spacing: 8) {
                        Button(action: {
                            model.copyItemToPasteboard(item)
                            withAnimation { showCopiedFeedback = true }
                            Task {
                                try? await Task.sleep(nanoseconds: 1_500_000_000)
                                withAnimation { showCopiedFeedback = false }
                            }
                        }) {
                            Image(systemName: showCopiedFeedback ? "checkmark" : "doc.on.doc")
                                .foregroundColor(showCopiedFeedback ? .green : .primary)
                        }
                        .buttonStyle(.plain)
                        .help("Copy to clipboard")
                        
                        Button(action: { model.togglePin(item) }) {
                            Image(systemName: item.isPinned ? "pin.slash" : "pin")
                        }
                        .buttonStyle(.plain)
                        .help(item.isPinned ? "Unpin" : "Pin")
                        
                        Button(action: { model.deleteItem(item) }) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                        .help("Delete")
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color.white.opacity(0.1) : Color.white.opacity(0.05))
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            Button(action: { model.copyItemToPasteboard(item) }) {
                Label("Copy", systemImage: "doc.on.doc")
            }
            Button(action: { model.togglePin(item) }) {
                Label(item.isPinned ? "Unpin" : "Pin", systemImage: item.isPinned ? "pin.slash" : "pin")
            }
            Divider()
            Button(role: .destructive, action: { model.deleteItem(item) }) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
    
    private func timeAgo(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
