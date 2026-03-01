import SwiftUI

struct PortManagerView: View {
    @EnvironmentObject var model: PortManagerModel
    let onBack: () -> Void

    @State private var portToKill: PortInfo? = nil
    @State private var showKillConfirm = false
    @State private var showForceKillConfirm = false
    @State private var showKillError = false
    @State private var showCopiedToast = false
    @State private var selectedPort: PortInfo? = nil

    var body: some View {
        if let selected = selectedPort {
            PortDetailView(portInfo: selected) {
                selectedPort = nil
            }
            .environmentObject(model)
        } else {
            portListView
        }
    }
    
    private var portListView: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Button(action: onBack) {
                    Label("Back", systemImage: "chevron.left")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)

                Text("Port Manager")
                    .font(.system(.headline, design: .rounded))

                Spacer()
            }

            Divider()

                // Search bar + menu
                HStack(spacing: 6) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search port, process, service...", text: $model.searchText)
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
                        // Sort
                        Section("Sort") {
                            Picker("Sort", selection: $model.sortOrder) {
                                ForEach(PortSortOrder.allCases, id: \.self) { order in
                                    Text(order.rawValue).tag(order)
                                }
                            }
                        }
                        
                        // Filter by category
                        Section("Filter") {
                            Picker("Category", selection: $model.categoryFilter) {
                                ForEach(PortCategory.allCases, id: \.self) { cat in
                                    Text(cat.rawValue).tag(cat)
                                }
                            }
                        }

                        Section("Refresh") {
                            Picker("Interval", selection: $model.refreshInterval) {
                                Text("1 second").tag(1.0)
                                Text("2 seconds").tag(2.0)
                                Text("5 seconds").tag(5.0)
                                Text("10 seconds").tag(10.0)
                            }
                            
                            Button(action: {
                                Task { await model.refreshPorts() }
                            }) {
                                Label("Refresh Now", systemImage: "arrow.clockwise")
                            }
                        }
                        
                        Divider()
                        
                        Button(action: {
                            model.copyAllPortsInfo()
                            flashCopiedToast()
                        }) {
                            Label("Copy All to Clipboard", systemImage: "doc.on.doc")
                        }
                        .disabled(model.filteredPorts.isEmpty)
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 16))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }

                // Status bar: count + active filters
                HStack(spacing: 6) {
                    Text("\(model.filteredPorts.count) port\(model.filteredPorts.count == 1 ? "" : "s")")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)

                    if model.categoryFilter != .all {
                        filterBadge(model.categoryFilter.rawValue) {
                            model.categoryFilter = .all
                        }
                    }
                    
                    Spacer()
                    
                    if showCopiedToast {
                        Text("Copied!")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(.green)
                            .transition(.opacity)
                    }
                }

                // Port list
                if model.ports.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "network.slash")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                        Text("No listening ports found")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundColor(.secondary)
                        Text("No TCP ports are currently in LISTEN state")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else if model.filteredPorts.isEmpty {
                    VStack(spacing: 8) {
                        Spacer()
                        Text("No matching ports")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundColor(.secondary)
                        if model.categoryFilter != .all {
                            Button("Clear Filter") { model.categoryFilter = .all }
                                .font(.system(.caption, design: .rounded))
                                .buttonStyle(.plain)
                                .foregroundColor(.accentColor)
                        }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(model.filteredPorts) { portInfo in
                                PortInfoRow(
                                    portInfo: portInfo,
                                    onKill: {
                                        portToKill = portInfo
                                        showKillConfirm = true
                                    },
                                    onForceKill: {
                                        portToKill = portInfo
                                        showForceKillConfirm = true
                                    },
                                    onCopy: { text in
                                        model.copyToClipboard(text)
                                        flashCopiedToast()
                                    },
                                    onSelect: {
                                        selectedPort = portInfo
                                    }
                                )
                            }
                        }
                        .padding(.trailing, 4)
                    }
                }
        }
        // SIGTERM confirmation
        .alert("Terminate Process", isPresented: $showKillConfirm) {
            Button("Cancel", role: .cancel) { portToKill = nil }
            Button("Terminate", role: .destructive) {
                if let port = portToKill {
                    if !model.killProcess(port) {
                        showKillError = true
                    }
                }
                portToKill = nil
            }
        } message: {
            if let port = portToKill {
                Text("Send SIGTERM to \"\(port.command)\" (PID \(port.pid)) on port \(port.port)?")
            }
        }
        // SIGKILL confirmation
        .alert("Force Kill Process", isPresented: $showForceKillConfirm) {
            Button("Cancel", role: .cancel) { portToKill = nil }
            Button("Force Kill", role: .destructive) {
                if let port = portToKill {
                    if !model.killProcess(port, force: true) {
                        showKillError = true
                    }
                }
                portToKill = nil
            }
        } message: {
            if let port = portToKill {
                Text("Send SIGKILL to \"\(port.command)\" (PID \(port.pid))? This will immediately terminate the process without cleanup.")
            }
        }
        // Error
        .alert("Permission Denied", isPresented: $showKillError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Could not terminate the process. You may need to run as administrator for system processes.")
        }
    }
    
    // MARK: - Helpers
    
    private func filterBadge(_ text: String, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 3) {
            Text(text)
                .font(.system(.caption2, design: .rounded))
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .bold))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color.accentColor.opacity(0.2)))
        .foregroundColor(.accentColor)
    }
    
    private func flashCopiedToast() {
        withAnimation { showCopiedToast = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation { showCopiedToast = false }
        }
    }
}

// MARK: - Port Row

struct PortInfoRow: View {
    let portInfo: PortInfo
    let onKill: () -> Void
    let onForceKill: () -> Void
    let onCopy: (String) -> Void
    let onSelect: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            // Port number + service
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(portInfo.port)")
                    .font(.system(.subheadline, design: .monospaced))
                    .fontWeight(.semibold)
                if let svc = portInfo.serviceName {
                    Text(svc)
                        .font(.system(size: 9, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(minWidth: 58, alignment: .trailing)

            // Category dot
            Circle()
                .fill(categoryColor)
                .frame(width: 6, height: 6)
                .help(portInfo.category.rawValue + " port")

            // Process info
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(portInfo.command)
                        .font(.system(.subheadline, design: .rounded))
                        .fontWeight(.medium)
                        .lineLimit(1)
                    if portInfo.isLocalOnly {
                        Text("local")
                            .font(.system(size: 8, design: .rounded))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.blue.opacity(0.15)))
                            .foregroundColor(.blue)
                    }
                }
                HStack(spacing: 4) {
                    Text("PID \(portInfo.pid)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    Text("·")
                        .foregroundStyle(.quaternary)
                    Text(portInfo.address)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    Text("·")
                        .foregroundStyle(.quaternary)
                    Text(portInfo.user)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            // Kill button on hover
            if isHovered {
                Button(action: onKill) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help("Terminate (SIGTERM)")
                .transition(.opacity)
            }
            
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.quaternary)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color.white.opacity(0.06) : Color.clear)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onTapGesture { onSelect() }
        .contextMenu {
            Button(action: { onCopy(String(portInfo.port)) }) {
                Label("Copy Port", systemImage: "doc.on.doc")
            }
            Button(action: { onCopy(String(portInfo.pid)) }) {
                Label("Copy PID", systemImage: "doc.on.doc")
            }
            Button(action: { onCopy(portInfo.command) }) {
                Label("Copy Process Name", systemImage: "doc.on.doc")
            }
            Button(action: { onCopy(portInfo.summary) }) {
                Label("Copy Details", systemImage: "list.clipboard")
            }
            
            Divider()
            
            Button(action: { onCopy("lsof -i :\(portInfo.port)") }) {
                Label("Copy lsof Command", systemImage: "terminal")
            }
            
            Divider()
            
            Button(role: .destructive, action: onKill) {
                Label("Terminate (SIGTERM)", systemImage: "xmark.circle")
            }
            Button(role: .destructive, action: onForceKill) {
                Label("Force Kill (SIGKILL)", systemImage: "bolt.circle")
            }
        }
    }
    
    private var categoryColor: Color {
        switch portInfo.category {
        case .system:  return .red
        case .user:    return .orange
        case .dynamic: return .green
        case .all:     return .gray
        }
    }
}
