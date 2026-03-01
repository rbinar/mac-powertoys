import Foundation
import AppKit
import Darwin

// MARK: - Well-Known Port Service Names

enum PortCategory: String, CaseIterable {
    case all = "All"
    case system = "System"   // 0-1023
    case user = "User"       // 1024-49151
    case dynamic = "Dynamic" // 49152-65535
    
    static func from(port: Int) -> PortCategory {
        switch port {
        case 0..<1024: return .system
        case 1024..<49152: return .user
        default: return .dynamic
        }
    }
}

enum PortSortOrder: String, CaseIterable {
    case portAsc = "Port ↑"
    case portDesc = "Port ↓"
    case processAsc = "Name A-Z"
    case pidAsc = "PID ↑"
}

struct PortInfo: Identifiable, Equatable {
    var id: String { "\(pid)-\(port)" }
    let command: String
    let pid: Int32
    let user: String
    let port: Int
    let address: String
    
    var serviceName: String? {
        Self.wellKnownPorts[port]
    }
    
    var category: PortCategory {
        PortCategory.from(port: port)
    }
    
    var isLocalOnly: Bool {
        address == "127.0.0.1" || address == "[::1]" || address == "localhost"
    }
    
    /// Formatted single-line summary for clipboard
    var summary: String {
        let svc = serviceName.map { " (\($0))" } ?? ""
        return "\(port)\(svc)\t\(command)\tPID \(pid)\t\(address)\t\(user)"
    }
    
    // Common ports for macOS development
    private static let wellKnownPorts: [Int: String] = [
        22: "SSH", 53: "DNS", 80: "HTTP", 443: "HTTPS",
        3000: "Dev Server", 3001: "Dev Server",
        3306: "MySQL", 4200: "Angular", 4443: "Pharos",
        5000: "Flask/AirPlay", 5001: "Flask/AirPlay",
        5173: "Vite", 5432: "PostgreSQL", 5500: "Live Server",
        5672: "RabbitMQ", 5900: "VNC",
        6379: "Redis", 6443: "Kubernetes API",
        8000: "HTTP Alt", 8001: "HTTP Alt", 8008: "HTTP Alt",
        8080: "HTTP Proxy", 8081: "HTTP Proxy",
        8443: "HTTPS Alt", 8888: "Jupyter",
        9000: "PHP-FPM", 9090: "Prometheus", 9200: "Elasticsearch",
        9229: "Node Debug", 9292: "Rack",
        15672: "RabbitMQ Mgmt", 27017: "MongoDB",
    ]
}

// MARK: - Connection & Traffic Models

struct ConnectionInfo: Identifiable, Equatable {
    var id: String { "\(localAddress):\(localPort)->\(remoteAddress):\(remotePort)" }
    let localAddress: String
    let localPort: Int
    let remoteAddress: String
    let remotePort: Int
    let state: String        // ESTABLISHED, CLOSE_WAIT, TIME_WAIT, LISTEN, etc.
    let protocolType: String // TCP or TCP6
    
    var isEstablished: Bool { state == "ESTABLISHED" }
    
    var stateColor: String {
        switch state {
        case "ESTABLISHED": return "green"
        case "CLOSE_WAIT", "LAST_ACK", "FIN_WAIT1", "FIN_WAIT2": return "orange"
        case "TIME_WAIT": return "yellow"
        case "LISTEN": return "blue"
        default: return "gray"
        }
    }
    
    var displayRemote: String {
        "\(remoteAddress):\(remotePort)"
    }
    
    var summary: String {
        "\(localAddress):\(localPort) → \(remoteAddress):\(remotePort) [\(state)]"
    }
}

struct TrafficStats: Equatable {
    var bytesIn: Int64 = 0
    var bytesOut: Int64 = 0
    var packetsIn: Int64 = 0
    var packetsOut: Int64 = 0
    var previousBytesIn: Int64 = 0
    var previousBytesOut: Int64 = 0
    var lastSampleTime: Date = Date()
    
    var bytesInPerSec: Double {
        let elapsed = Date().timeIntervalSince(lastSampleTime)
        guard elapsed > 0 else { return 0 }
        return Double(bytesIn - previousBytesIn) / elapsed
    }
    
    var bytesOutPerSec: Double {
        let elapsed = Date().timeIntervalSince(lastSampleTime)
        guard elapsed > 0 else { return 0 }
        return Double(bytesOut - previousBytesOut) / elapsed
    }
    
    static func formatBytes(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        if bytes < 1024 * 1024 * 1024 { return String(format: "%.1f MB", Double(bytes) / (1024 * 1024)) }
        return String(format: "%.2f GB", Double(bytes) / (1024 * 1024 * 1024))
    }
    
    static func formatRate(_ bytesPerSec: Double) -> String {
        if bytesPerSec < 1 { return "0 B/s" }
        if bytesPerSec < 1024 { return String(format: "%.0f B/s", bytesPerSec) }
        if bytesPerSec < 1024 * 1024 { return String(format: "%.1f KB/s", bytesPerSec / 1024) }
        return String(format: "%.1f MB/s", bytesPerSec / (1024 * 1024))
    }
    
    static func formatPackets(_ count: Int64) -> String {
        if count < 1000 { return "\(count)" }
        if count < 1_000_000 { return String(format: "%.1fK", Double(count) / 1000) }
        return String(format: "%.1fM", Double(count) / 1_000_000)
    }
}

struct ConnectionTraffic: Identifiable, Equatable {
    var id: String { "\(proto) \(localEndpoint)<->\(remoteEndpoint)" }
    let proto: String          // "tcp4", "tcp6", "udp4", "udp6"
    let localEndpoint: String  // "192.168.0.132:54924" or "*:5353" or "*.5353"
    let remoteEndpoint: String // "162.159.140.229:443" or "*.*" or "*:*"
    let bytesIn: Int64
    let bytesOut: Int64
    let packetsIn: Int64
    let packetsOut: Int64
    
    var totalBytes: Int64 { bytesIn + bytesOut }
    var isActive: Bool { bytesIn > 0 || bytesOut > 0 }
    
    /// Extract remote port number if available
    var remotePort: Int? {
        // Handle formats: "1.2.3.4:443", "[::1]:443", "*.*", "*:*"
        if remoteEndpoint == "*.*" || remoteEndpoint == "*:*" { return nil }
        if let lastColon = remoteEndpoint.lastIndex(of: ":") {
            return Int(String(remoteEndpoint[remoteEndpoint.index(after: lastColon)...]))
        }
        // Handle "*.5353" format (dot-separated)
        if remoteEndpoint.contains("."), let lastDot = remoteEndpoint.lastIndex(of: ".") {
            return Int(String(remoteEndpoint[remoteEndpoint.index(after: lastDot)...]))
        }
        return nil
    }
    
    /// Remote service name based on well-known remote ports
    var remoteServiceName: String? {
        guard let port = remotePort else { return nil }
        return Self.wellKnownRemotePorts[port]
    }
    
    private static let wellKnownRemotePorts: [Int: String] = [
        22: "SSH", 53: "DNS", 80: "HTTP", 443: "HTTPS",
        993: "IMAPS", 995: "POP3S", 587: "SMTP",
        3306: "MySQL", 5432: "PostgreSQL", 6379: "Redis", 27017: "MongoDB",
        5228: "Google Push", 5229: "Google Push", 5230: "Google Push",
        5353: "mDNS", 5222: "XMPP",
        8080: "HTTP Proxy", 8443: "HTTPS Alt",
        9090: "Prometheus", 9200: "Elasticsearch",
    ]
}

@MainActor
final class PortManagerModel: ObservableObject {
    @Published var ports: [PortInfo] = []
    @Published var isEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "portManager.isEnabled")
            if isEnabled { startMonitoring() } else { stopMonitoring() }
        }
    }
    @Published var searchText: String = ""
    
    @Published var sortOrder: PortSortOrder = .portAsc {
        didSet { UserDefaults.standard.set(sortOrder.rawValue, forKey: "portManager.sortOrder") }
    }
    
    @Published var categoryFilter: PortCategory = .all {
        didSet { UserDefaults.standard.set(categoryFilter.rawValue, forKey: "portManager.categoryFilter") }
    }

    @Published var refreshInterval: Double = 2.0 {
        didSet {
            UserDefaults.standard.set(refreshInterval, forKey: "portManager.refreshInterval")
            if isEnabled { startMonitoring() }
        }
    }

    var filteredPorts: [PortInfo] {
        var result = ports
        
        // Category filter
        if categoryFilter != .all {
            result = result.filter { $0.category == categoryFilter }
        }
        
        // Text search
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.command.lowercased().contains(query) ||
                String($0.port).contains(query) ||
                ($0.serviceName?.lowercased().contains(query) ?? false) ||
                $0.address.lowercased().contains(query) ||
                $0.user.lowercased().contains(query)
            }
        }
        
        // Sort
        switch sortOrder {
        case .portAsc:    result.sort { $0.port < $1.port }
        case .portDesc:   result.sort { $0.port > $1.port }
        case .processAsc: result.sort { $0.command.lowercased() < $1.command.lowercased() }
        case .pidAsc:     result.sort { $0.pid < $1.pid }
        }
        
        return result
    }

    private var refreshTimer: Timer?

    init() {
        let saved = UserDefaults.standard.double(forKey: "portManager.refreshInterval")
        refreshInterval = saved > 0 ? saved : 2.0
        
        if let sortRaw = UserDefaults.standard.string(forKey: "portManager.sortOrder"),
           let sort = PortSortOrder(rawValue: sortRaw) {
            sortOrder = sort
        }
        if let catRaw = UserDefaults.standard.string(forKey: "portManager.categoryFilter"),
           let cat = PortCategory(rawValue: catRaw) {
            categoryFilter = cat
        }

        self.isEnabled = UserDefaults.standard.bool(forKey: "portManager.isEnabled")
        if isEnabled {
            startMonitoring()
        }
    }

    func startMonitoring() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshPorts()
            }
        }
        Task {
            await refreshPorts()
        }
    }

    func stopMonitoring() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func refreshPorts() async {
        let result = await runLsof()
        self.ports = result
    }

    // MARK: - Process Actions
    
    func killProcess(_ portInfo: PortInfo, force: Bool = false) -> Bool {
        let signal = force ? SIGKILL : SIGTERM
        let result = Darwin.kill(portInfo.pid, signal)
        if result == 0 {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000)
                await refreshPorts()
            }
            return true
        }
        return false
    }
    
    func copyToClipboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }
    
    func copyAllPortsInfo() {
        let header = "PORT\tSERVICE\tPROCESS\tPID\tADDRESS\tUSER"
        let rows = filteredPorts.map { $0.summary }
        let text = ([header] + rows).joined(separator: "\n")
        copyToClipboard(text)
    }

    // MARK: - Connection & Traffic Fetching
    
    /// Get all PIDs in a process tree: the given PID + all descendant child PIDs.
    private func getProcessTree(_ pid: Int32) async -> [Int32] {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var pids: [Int32] = [pid]
                // Find direct children
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
                process.arguments = ["-P", "\(pid)"]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice
                
                do {
                    try process.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    let childPids = output.split(separator: "\n").compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
                    pids.append(contentsOf: childPids)
                } catch { }
                
                continuation.resume(returning: pids)
            }
        }
    }
    
    func fetchConnections(for pid: Int32) async -> [ConnectionInfo] {
        let pids = await getProcessTree(pid)
        var allConnections: [ConnectionInfo] = []
        var seen = Set<String>()
        
        for p in pids {
            let conns = await fetchConnectionsForSinglePid(p)
            for conn in conns {
                if seen.insert(conn.id).inserted {
                    allConnections.append(conn)
                }
            }
        }
        return allConnections
    }
    
    private func fetchConnectionsForSinglePid(_ pid: Int32) async -> [ConnectionInfo] {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
                process.arguments = ["+c", "0", "-i", "-a", "-p", "\(pid)", "-P", "-n"]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice
                
                do {
                    try process.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    let connections = Self.parseConnectionOutput(output)
                    continuation.resume(returning: connections)
                } catch {
                    continuation.resume(returning: [])
                }
            }
        }
    }
    
    func fetchTrafficStats(for pid: Int32, previous: TrafficStats?) async -> (TrafficStats, [ConnectionTraffic]) {
        let pids = await getProcessTree(pid)
        var totalBytesIn: Int64 = 0
        var totalBytesOut: Int64 = 0
        var totalPacketsIn: Int64 = 0
        var totalPacketsOut: Int64 = 0
        var allConnections: [ConnectionTraffic] = []
        var seenConnectionIds = Set<String>()
        
        for p in pids {
            let (stats, connections) = await fetchTrafficForSinglePid(p)
            totalBytesIn += stats.bytesIn
            totalBytesOut += stats.bytesOut
            totalPacketsIn += stats.packetsIn
            totalPacketsOut += stats.packetsOut
            for conn in connections {
                if seenConnectionIds.insert(conn.id).inserted {
                    allConnections.append(conn)
                }
            }
        }
        
        var result = TrafficStats()
        result.bytesIn = totalBytesIn
        result.bytesOut = totalBytesOut
        result.packetsIn = totalPacketsIn
        result.packetsOut = totalPacketsOut
        result.previousBytesIn = previous?.bytesIn ?? totalBytesIn
        result.previousBytesOut = previous?.bytesOut ?? totalBytesOut
        result.lastSampleTime = previous?.lastSampleTime ?? Date()
        return (result, allConnections)
    }
    
    private func fetchTrafficForSinglePid(_ pid: Int32) async -> (TrafficStats, [ConnectionTraffic]) {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
                process.arguments = ["-x", "-p", "\(pid)", "-l", "1", "-J", "bytes_in,bytes_out,packets_in,packets_out"]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice
                
                do {
                    try process.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    let result = Self.parseNettopOutput(output, previous: nil)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(returning: (TrafficStats(), []))
                }
            }
        }
    }
    
    static func parseConnectionOutput(_ output: String) -> [ConnectionInfo] {
        var results: [ConnectionInfo] = []
        let lines = output.components(separatedBy: "\n")
        
        for (index, line) in lines.enumerated() {
            if index == 0 { continue } // skip header
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            
            let columns = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard columns.count >= 9 else { continue }
            
            // Last column is the state in parentheses, second-to-last is the NAME
            let lastCol = columns.last ?? ""
            guard lastCol.hasPrefix("(") && lastCol.hasSuffix(")") else { continue }
            let state = String(lastCol.dropFirst().dropLast())
            
            let nameCol = columns[columns.count - 2]
            let protoCol = columns.count > 7 ? columns[7] : "TCP" // NODE column
            let proto = protoCol.lowercased().contains("6") ? "TCP6" : "TCP"
            
            // Connection format: local->remote  OR just local (LISTEN)
            if nameCol.contains("->") {
                let parts = nameCol.components(separatedBy: "->")
                guard parts.count == 2 else { continue }
                let (localAddr, localPort) = Self.parseAddressPort(parts[0])
                let (remoteAddr, remotePort) = Self.parseAddressPort(parts[1])
                guard let lPort = localPort, let rPort = remotePort else { continue }
                
                results.append(ConnectionInfo(
                    localAddress: localAddr,
                    localPort: lPort,
                    remoteAddress: remoteAddr,
                    remotePort: rPort,
                    state: state,
                    protocolType: proto
                ))
            } else if state == "LISTEN" {
                let (localAddr, localPort) = Self.parseAddressPort(nameCol)
                guard let lPort = localPort else { continue }
                
                results.append(ConnectionInfo(
                    localAddress: localAddr,
                    localPort: lPort,
                    remoteAddress: "*",
                    remotePort: 0,
                    state: state,
                    protocolType: proto
                ))
            }
        }
        
        return results
    }
    
    static func parseNettopOutput(_ output: String, previous: TrafficStats?) -> (TrafficStats, [ConnectionTraffic]) {
        // nettop output with 4 columns (order: packets_in, bytes_in, packets_out, bytes_out):
        //                                packets_in        bytes_in     packets_out       bytes_out
        // Google Chrome H.6770              2306          510245            2260          998919
        //                                     tcp4 192.168.0.132:54924<->162.159.140.229:443
        //                                   1395          429075            2402         1044521
        // The process name + totals are on the SAME line.
        // Per-connection lines have 4 numbers + "proto local<->remote".
        let lines = output.components(separatedBy: "\n")
        var foundHeader = false
        var connections: [ConnectionTraffic] = []
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Skip the column header line
            if trimmed.contains("bytes_in") && trimmed.contains("bytes_out") {
                foundHeader = true
                continue
            }
            
            guard foundHeader else { continue }
            if trimmed.isEmpty { continue }
            
            // Parse per-connection lines (contain <->)
            if trimmed.contains("<->") {
                let tokens = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
                // Find the token containing <->
                guard let arrowIdx = tokens.firstIndex(where: { $0.contains("<->") }) else { continue }
                // Protocol is the token before the <-> token
                guard arrowIdx > 0 else { continue }
                let proto = tokens[arrowIdx - 1]
                // Split the <-> token into local and remote endpoints
                let endpointParts = tokens[arrowIdx].components(separatedBy: "<->")
                guard endpointParts.count == 2 else { continue }
                let localEndpoint = endpointParts[0]
                let remoteEndpoint = endpointParts[1]
                // First 4 numeric tokens (before protocol) are packets_in, bytes_in, packets_out, bytes_out
                let numericTokens = tokens.prefix(upTo: arrowIdx - 1).compactMap { Int64($0) }
                guard numericTokens.count >= 4 else { continue }
                connections.append(ConnectionTraffic(
                    proto: proto,
                    localEndpoint: localEndpoint,
                    remoteEndpoint: remoteEndpoint,
                    bytesIn: numericTokens[1],
                    bytesOut: numericTokens[3],
                    packetsIn: numericTokens[0],
                    packetsOut: numericTokens[2]
                ))
                continue
            }
            
            // Process total line: last 4 tokens are packets_in, bytes_in, packets_out, bytes_out
            let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 4 else {
                // Fallback: 2-column format (bytes_in, bytes_out only)
                if parts.count >= 2,
                   let bytesOut = Int64(parts[parts.count - 1]),
                   let bytesIn = Int64(parts[parts.count - 2]) {
                    var stats = TrafficStats()
                    stats.bytesIn = bytesIn
                    stats.bytesOut = bytesOut
                    stats.previousBytesIn = previous?.bytesIn ?? bytesIn
                    stats.previousBytesOut = previous?.bytesOut ?? bytesOut
                    stats.lastSampleTime = previous?.lastSampleTime ?? Date()
                    return (stats, connections)
                }
                continue
            }
            
            if let bytesOut = Int64(parts[parts.count - 1]),
               let packetsOut = Int64(parts[parts.count - 2]),
               let bytesIn = Int64(parts[parts.count - 3]),
               let packetsIn = Int64(parts[parts.count - 4]) {
                var stats = TrafficStats()
                stats.bytesIn = bytesIn
                stats.bytesOut = bytesOut
                stats.packetsIn = packetsIn
                stats.packetsOut = packetsOut
                stats.previousBytesIn = previous?.bytesIn ?? bytesIn
                stats.previousBytesOut = previous?.bytesOut ?? bytesOut
                stats.lastSampleTime = previous?.lastSampleTime ?? Date()
                return (stats, connections)
            }
        }
        
        return (previous ?? TrafficStats(), connections)
    }

    // MARK: - Private

    private func runLsof() async -> [PortInfo] {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
                process.arguments = ["+c", "0", "-iTCP", "-sTCP:LISTEN", "-P", "-n"]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice

                do {
                    try process.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    let output = String(data: data, encoding: .utf8) ?? ""
                    let ports = Self.parseLsofOutput(output)
                    continuation.resume(returning: ports)
                } catch {
                    continuation.resume(returning: [])
                }
            }
        }
    }

    static func parseLsofOutput(_ output: String) -> [PortInfo] {
        var results: [PortInfo] = []
        var seen = Set<String>()
        let lines = output.components(separatedBy: "\n")

        for (index, line) in lines.enumerated() {
            if index == 0 { continue }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            let columns = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard columns.count >= 9 else { continue }

            let command = columns[0]
            guard let pid = Int32(columns[1]) else { continue }
            let user = columns[2]

            guard let listenIndex = columns.lastIndex(of: "(LISTEN)"),
                  listenIndex > 0 else { continue }
            let nameColumn = columns[listenIndex - 1]

            let (address, port) = parseAddressPort(nameColumn)
            guard let portNumber = port else { continue }

            let key = "\(command)-\(pid)-\(portNumber)"
            guard !seen.contains(key) else { continue }
            seen.insert(key)

            results.append(PortInfo(
                command: command,
                pid: pid,
                user: user,
                port: portNumber,
                address: address
            ))
        }

        return results
    }

    private static func parseAddressPort(_ nameColumn: String) -> (String, Int?) {
        if nameColumn.hasPrefix("[") {
            guard let closeBracket = nameColumn.lastIndex(of: "]") else { return (nameColumn, nil) }
            let address = String(nameColumn[nameColumn.startIndex...closeBracket])
            let afterBracket = nameColumn[nameColumn.index(after: closeBracket)...]
            guard afterBracket.hasPrefix(":") else { return (address, nil) }
            let portStr = String(afterBracket.dropFirst())
            return (address, Int(portStr))
        }

        guard let lastColon = nameColumn.lastIndex(of: ":") else { return (nameColumn, nil) }
        let address = String(nameColumn[nameColumn.startIndex..<lastColon])
        let portStr = String(nameColumn[nameColumn.index(after: lastColon)...])
        return (address, Int(portStr))
    }
}
