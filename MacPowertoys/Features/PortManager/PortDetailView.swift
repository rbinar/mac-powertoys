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
    @State private var isLoadingData = false
    @State private var showKillConfirm = false
    @State private var showForceKillConfirm = false
    @State private var showKillError = false
    @State private var showCopiedToast = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            FeatureHeader(title: "\(portInfo.command) :\(portInfo.port)", onBack: onBack) {
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
                .accessibilityLabel("Process actions")
                .help("Process actions")
            }

            HStack(spacing: 4) {
                Text("PID \(portInfo.pid)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                if let svc = portInfo.serviceName {
                    Text("·")
                        .foregroundStyle(.quaternary) // style-ok: decorative separator dot
                    Text(svc)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
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
                    .font(.caption2)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.green.opacity(0.2)))
                    .foregroundStyle(.green)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
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
            SectionHeader("Network Traffic")
            
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
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.quaternary)
                    Text(rate)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 3) {
                    Image(systemName: "shippingbox")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(TrafficStats.formatPackets(packets)) pkts")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
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
                SectionHeader("Connections by Traffic")
                
                Spacer()
                
                let activeCount = connectionTraffics.filter(\.isActive).count
                Text("\(activeCount) / \(connectionTraffics.count)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
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
                        .font(.caption2)
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
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .fixedSize()
                
                HStack(spacing: 2) {
                    Image(systemName: "arrow.down")
                        .font(.caption2)
                        .foregroundStyle(.tint)
                    Text(TrafficStats.formatBytes(ct.bytesIn))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tint)
                }
                .fixedSize()
                
                HStack(spacing: 2) {
                    Image(systemName: "arrow.up")
                        .font(.caption2)
                        .foregroundColor(.orange)
                    Text(TrafficStats.formatBytes(ct.bytesOut))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.orange)
                }
                .fixedSize()
                
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.primary.opacity(0.06))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(fillColor.opacity(0.4))
                            .frame(width: geo.size.width * CGFloat(share))
                    }
                }
                .frame(height: 6)
                
                Text("\(Int(share * 100))%")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.03)))
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
                SectionHeader("Active Connections")
                
                Spacer()
                
                Text("\(connections.count)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
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
                        .foregroundStyle(.secondary)
                    Text("No active connections")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                .font(.system(.caption2, design: .monospaced))
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
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            Text(conn.protocolType)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.03)))
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
        case "TIME_WAIT": return .orange
        case "LISTEN": return .blue
        default: return .gray
        }
    }
    
    // MARK: - Data Loading
    
    private func startRefreshing() {
        Task { await loadData() }
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: model.refreshInterval, repeats: true) { _ in
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
        guard !isLoadingData else { return }
        isLoadingData = true
        defer { isLoadingData = false }

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
        withAnimation(reduceMotion ? nil : .default) { showCopiedToast = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation(reduceMotion ? nil : .default) { showCopiedToast = false }
        }
    }
    
    /// Pin/unpin the MenuBarExtra panel so it stays visible when another app is focused.
    private func setMenuBarPanelPinned(_ pinned: Bool) {
        DispatchQueue.main.async {
            // The MenuBarExtra window is an NSPanel; find the one containing this view
            for window in NSApp.windows {
                let className = String(describing: type(of: window))

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
            }
        }
    }
}
