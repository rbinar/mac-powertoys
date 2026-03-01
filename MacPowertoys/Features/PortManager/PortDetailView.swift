import SwiftUI

struct PortDetailView: View {
    @EnvironmentObject var model: PortManagerModel
    let portInfo: PortInfo
    let onBack: () -> Void
    
    @State private var connections: [ConnectionInfo] = []
    @State private var trafficStats: TrafficStats = TrafficStats()
    @State private var connectionTraffics: [ConnectionTraffic] = []
    @State private var isLoading = true
    @State private var refreshTimer: Timer?
    @State private var showKillConfirm = false
    @State private var showForceKillConfirm = false
    @State private var showKillError = false
    @State private var showCopiedToast = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Button(action: onBack) {
                    Label("Back", systemImage: "chevron.left")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
                
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(portInfo.command)
                            .font(.system(.headline, design: .rounded))
                            .lineLimit(1)
                        Text(":\(portInfo.port)")
                            .font(.system(.headline, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 4) {
                        Text("PID \(portInfo.pid)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.tertiary)
                        if let svc = portInfo.serviceName {
                            Text("·")
                                .foregroundStyle(.quaternary)
                            Text(svc)
                                .font(.system(.caption2, design: .rounded))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                
                Spacer()
                
                Menu {
                    Button(role: .destructive) {
                        showKillConfirm = true
                    } label: {
                        Label("Terminate (SIGTERM)", systemImage: "xmark.circle")
                    }
                    Button(role: .destructive) {
                        showForceKillConfirm = true
                    } label: {
                        Label("Force Kill (SIGKILL)", systemImage: "bolt.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 14))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            
            Divider()
            
            // Traffic Stats
            trafficSection
            
            Divider()
            
            // Connections - prefer traffic breakdown, fallback to lsof connections
            if !connectionTraffics.isEmpty {
                trafficConnectionsSection
            } else {
                connectionsSection
            }
        }
        .onAppear {
            startRefreshing()
            setMenuBarPanelPinned(true)
        }
        .onDisappear {
            stopRefreshing()
            setMenuBarPanelPinned(false)
        }
        .overlay(alignment: .bottom) {
            if showCopiedToast {
                Text("Copied!")
                    .font(.system(.caption2, design: .rounded))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.green.opacity(0.2)))
                    .foregroundStyle(.green)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 8)
            }
        }
        .alert("Terminate Process", isPresented: $showKillConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Terminate", role: .destructive) {
                if !model.killProcess(portInfo) {
                    showKillError = true
                } else {
                    onBack()
                }
            }
        } message: {
            Text("Send SIGTERM to \"\(portInfo.command)\" (PID \(portInfo.pid))?")
        }
        .alert("Force Kill Process", isPresented: $showForceKillConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Force Kill", role: .destructive) {
                if !model.killProcess(portInfo, force: true) {
                    showKillError = true
                } else {
                    onBack()
                }
            }
        } message: {
            Text("Send SIGKILL to \"\(portInfo.command)\" (PID \(portInfo.pid))? This will immediately terminate the process.")
        }
        .alert("Permission Denied", isPresented: $showKillError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Could not terminate the process. You may need to run as administrator.")
        }
    }
    
    // MARK: - Traffic Section
    
    private var trafficSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Network Traffic")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            
            HStack(spacing: 16) {
                trafficCard(
                    icon: "arrow.down.circle.fill",
                    color: .blue,
                    label: "Download",
                    total: TrafficStats.formatBytes(trafficStats.bytesIn),
                    rate: TrafficStats.formatRate(trafficStats.bytesInPerSec),
                    packets: trafficStats.packetsIn
                )
                
                trafficCard(
                    icon: "arrow.up.circle.fill",
                    color: .orange,
                    label: "Upload",
                    total: TrafficStats.formatBytes(trafficStats.bytesOut),
                    rate: TrafficStats.formatRate(trafficStats.bytesOutPerSec),
                    packets: trafficStats.packetsOut
                )
            }
        }
    }
    
    private func trafficCard(icon: String, color: Color, label: String, total: String, rate: String, packets: Int64) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(total)
                    .font(.system(.subheadline, design: .monospaced))
                    .fontWeight(.semibold)
                HStack(spacing: 4) {
                    Text(label)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.quaternary)
                    Text(rate)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 3) {
                    Image(systemName: "shippingbox")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                    Text("\(TrafficStats.formatPackets(packets)) pkts")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(color.opacity(0.06)))
    }
    
    // MARK: - Traffic Connections Section
    
    private var trafficConnectionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Connections by Traffic")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                
                Spacer()
                
                let activeCount = connectionTraffics.filter(\.isActive).count
                Text("\(activeCount) / \(connectionTraffics.count)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            
            if isLoading {
                VStack {
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                    Spacer()
                }
            } else {
                let totalBytes = connectionTraffics.reduce(Int64(0)) { $0 + $1.totalBytes }
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(connectionTraffics) { ct in
                            trafficConnectionRow(ct, totalBytes: totalBytes)
                        }
                    }
                    .padding(.trailing, 4)
                }
            }
        }
    }
    
    private func trafficConnectionRow(_ ct: ConnectionTraffic, totalBytes: Int64) -> some View {
        let displayEndpoint = (ct.remoteEndpoint == "*.*" || ct.remoteEndpoint == "*:*") ? ct.localEndpoint : ct.remoteEndpoint
        let share = totalBytes > 0 ? Double(ct.totalBytes) / Double(totalBytes) : 0
        let fillColor: Color = ct.bytesIn >= ct.bytesOut ? .blue : .orange
        
        return VStack(alignment: .leading, spacing: 3) {
            // Row 1: endpoint + service badge
            HStack {
                Text(displayEndpoint)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                
                Spacer()
                
                if let svc = ct.remoteServiceName {
                    Text(svc)
                        .font(.system(size: 9, design: .rounded))
                        .fontWeight(.medium)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
            }
            
            // Row 2: proto, download, upload, progress bar
            HStack(spacing: 6) {
                Text(ct.proto)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .fixedSize()
                
                HStack(spacing: 2) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 8))
                        .foregroundColor(.blue)
                    Text(TrafficStats.formatBytes(ct.bytesIn))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.blue)
                }
                .fixedSize()
                
                HStack(spacing: 2) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 8))
                        .foregroundColor(.orange)
                    Text(TrafficStats.formatBytes(ct.bytesOut))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.orange)
                }
                .fixedSize()
                
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white.opacity(0.06))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(fillColor.opacity(0.4))
                            .frame(width: geo.size.width * CGFloat(share))
                    }
                }
                .frame(height: 6)
                
                Text("\(Int(share * 100))%")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .fixedSize()
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.03)))
        .opacity(ct.isActive ? 1 : 0.5)
        .contextMenu {
            Button(action: { copyText(displayEndpoint) }) {
                Label("Copy Remote Address", systemImage: "doc.on.doc")
            }
            Button(action: {
                let svc = ct.remoteServiceName.map { " \($0)" } ?? ""
                let summary = "\(displayEndpoint)\(svc) ↓\(TrafficStats.formatBytes(ct.bytesIn)) ↑\(TrafficStats.formatBytes(ct.bytesOut))"
                copyText(summary)
            }) {
                Label("Copy Connection Summary", systemImage: "list.clipboard")
            }
        }
    }
    
    // MARK: - Connections Section (lsof fallback)
    
    private var connectionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Active Connections")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                
                Spacer()
                
                Text("\(connections.count)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            
            if isLoading {
                VStack {
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                    Spacer()
                }
            } else if connections.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.system(size: 24))
                        .foregroundStyle(.tertiary)
                    Text("No active connections")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(connections) { conn in
                            connectionRow(conn)
                        }
                    }
                    .padding(.trailing, 4)
                }
            }
        }
    }
    
    private func connectionRow(_ conn: ConnectionInfo) -> some View {
        HStack(spacing: 6) {
            // State badge
            Text(conn.state)
                .font(.system(size: 9, design: .monospaced))
                .fontWeight(.medium)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(stateColor(conn.state).opacity(0.15)))
                .foregroundColor(stateColor(conn.state))
                .fixedSize()
            
            // Connection details
            VStack(alignment: .leading, spacing: 1) {
                if conn.state == "LISTEN" {
                    Text("\(conn.localAddress):\(conn.localPort)")
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                } else {
                    Text(conn.displayRemote)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                    Text(":\(conn.localPort) → :\(conn.remotePort)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            
            Spacer()
            
            Text(conn.protocolType)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.quaternary)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.03)))
        .contextMenu {
            Button(action: { copyText(conn.displayRemote) }) {
                Label("Copy Remote Address", systemImage: "doc.on.doc")
            }
            Button(action: { copyText(conn.summary) }) {
                Label("Copy Connection Details", systemImage: "list.clipboard")
            }
        }
    }
    
    private func stateColor(_ state: String) -> Color {
        switch state {
        case "ESTABLISHED": return .green
        case "CLOSE_WAIT", "LAST_ACK", "FIN_WAIT1", "FIN_WAIT2": return .orange
        case "TIME_WAIT": return .yellow
        case "LISTEN": return .blue
        default: return .gray
        }
    }
    
    // MARK: - Data Loading
    
    private func startRefreshing() {
        Task { await loadData() }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { @MainActor in
                await loadData()
            }
        }
    }
    
    private func stopRefreshing() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    private func loadData() async {
        async let conns = model.fetchConnections(for: portInfo.pid)
        async let stats = model.fetchTrafficStats(for: portInfo.pid, previous: trafficStats)
        
        let (c, (s, ct)) = await (conns, stats)
        connections = c
        trafficStats = s
        connectionTraffics = ct.sorted { $0.totalBytes > $1.totalBytes }
        isLoading = false
    }
    
    private func copyText(_ text: String) {
        model.copyToClipboard(text)
        withAnimation { showCopiedToast = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation { showCopiedToast = false }
        }
    }
    
    /// Pin/unpin the MenuBarExtra panel so it stays visible when another app is focused.
    private func setMenuBarPanelPinned(_ pinned: Bool) {
        DispatchQueue.main.async {
            // The MenuBarExtra window is an NSPanel; find the one containing this view
            for window in NSApp.windows {
                let className = String(describing: type(of: window))
                print("[PortDetail] window: \(className) visible=\(window.isVisible) title='\(window.title)'")
                
                // Match the MenuBarExtra panel by class name patterns
                if window is NSPanel,
                   (className.contains("MenuBarExtra") ||
                    className.contains("StatusBar") ||
                    className.contains("_NSStatusBarWindow")) {
                    window.hidesOnDeactivate = !pinned
                    if pinned {
                        window.level = .floating
                    } else {
                        window.level = .normal
                    }
                    print("[PortDetail] Panel pinned=\(pinned) for \(className)")
                    return
                }
            }
            
            // Fallback: find the visible NSPanel that contains our content
            if let panel = NSApp.windows
                .compactMap({ $0 as? NSPanel })
                .first(where: { $0.isVisible && $0.contentView != nil }) {
                panel.hidesOnDeactivate = !pinned
                if pinned {
                    panel.level = .floating
                } else {
                    panel.level = .normal
                }
                let className = String(describing: type(of: panel))
                print("[PortDetail] Fallback panel pinned=\(pinned) for \(className)")
            }
        }
    }
}
