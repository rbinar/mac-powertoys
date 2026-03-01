import Foundation
import Darwin

@MainActor
final class SystemInfoModel: ObservableObject {
    // MARK: - Published State

    @Published private(set) var cpuUsage: Double = 0.0
    @Published private(set) var memoryUsed: Double = 0.0
    @Published private(set) var memoryTotal: Double = 0.0
    @Published private(set) var diskUsed: Double = 0.0
    @Published private(set) var diskTotal: Double = 0.0
    @Published private(set) var networkBytesInPerSec: Int64 = 0
    @Published private(set) var networkBytesOutPerSec: Int64 = 0

    @Published var isEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "systemInfo.isEnabled")
            if isEnabled { startMonitoring() } else { stopMonitoring() }
        }
    }

    @Published var refreshInterval: Double = 2.0 {
        didSet {
            UserDefaults.standard.set(refreshInterval, forKey: "systemInfo.refreshInterval")
            if isEnabled { startMonitoring() }
        }
    }

    // MARK: - Computed Properties

    var formattedCPU: String {
        "\(Int(cpuUsage))%"
    }

    var formattedMemory: String {
        String(format: "%.1f / %.1f GB", memoryUsed, memoryTotal)
    }

    var formattedDisk: String {
        String(format: "%.1f / %.1f GB", diskUsed, diskTotal)
    }

    var formattedNetIn: String {
        formatBytesPerSec(networkBytesInPerSec)
    }

    var formattedNetOut: String {
        formatBytesPerSec(networkBytesOutPerSec)
    }

    var hubStatusText: String {
        let mem = Int(memoryUsed)
        let total = Int(memoryTotal)
        return "CPU \(Int(cpuUsage))% | RAM \(mem)/\(total) GB"
    }

    var cpuFraction: Double { cpuUsage / 100.0 }
    var memoryFraction: Double { memoryTotal > 0 ? memoryUsed / memoryTotal : 0 }
    var diskFraction: Double { diskTotal > 0 ? diskUsed / diskTotal : 0 }

    // MARK: - Private State

    private var refreshTimer: Timer?

    // CPU previous ticks
    private var prevUserTicks: UInt64 = 0
    private var prevSystemTicks: UInt64 = 0
    private var prevIdleTicks: UInt64 = 0
    private var prevNiceTicks: UInt64 = 0
    private var hasPreviousCPU = false

    // Network previous readings
    private var prevNetBytesIn: UInt64 = 0
    private var prevNetBytesOut: UInt64 = 0
    private var prevNetTimestamp: Date?

    // MARK: - Init

    init() {
        let saved = UserDefaults.standard.double(forKey: "systemInfo.refreshInterval")
        refreshInterval = saved > 0 ? saved : 2.0
        self.isEnabled = UserDefaults.standard.bool(forKey: "systemInfo.isEnabled")
        if isEnabled {
            startMonitoring()
        }
    }

    // MARK: - Monitoring

    func startMonitoring() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
        refresh()
    }

    func stopMonitoring() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - Refresh

    private func refresh() {
        fetchCPU()
        fetchMemory()
        fetchDisk()
        fetchNetwork()
    }

    // MARK: - CPU (Mach host_processor_info)

    private func fetchCPU() {
        var numCPUs: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var numCpuInfo: mach_msg_type_number_t = 0

        let result = host_processor_info(mach_host_self(),
                                         PROCESSOR_CPU_LOAD_INFO,
                                         &numCPUs,
                                         &cpuInfo,
                                         &numCpuInfo)
        guard result == KERN_SUCCESS, let info = cpuInfo else { return }

        defer {
            let size = vm_size_t(numCpuInfo) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), size)
        }

        var totalUser: UInt64 = 0
        var totalSystem: UInt64 = 0
        var totalIdle: UInt64 = 0
        var totalNice: UInt64 = 0

        for i in 0..<Int(numCPUs) {
            let base = Int(CPU_STATE_MAX) * i
            totalUser   += UInt64(info[base + Int(CPU_STATE_USER)])
            totalSystem += UInt64(info[base + Int(CPU_STATE_SYSTEM)])
            totalIdle   += UInt64(info[base + Int(CPU_STATE_IDLE)])
            totalNice   += UInt64(info[base + Int(CPU_STATE_NICE)])
        }

        if hasPreviousCPU,
           totalUser >= prevUserTicks,
           totalSystem >= prevSystemTicks,
           totalIdle >= prevIdleTicks,
           totalNice >= prevNiceTicks {
            let userDelta   = totalUser - prevUserTicks
            let systemDelta = totalSystem - prevSystemTicks
            let idleDelta   = totalIdle - prevIdleTicks
            let niceDelta   = totalNice - prevNiceTicks
            let totalDelta  = userDelta + systemDelta + idleDelta + niceDelta
            if totalDelta > 0 {
                cpuUsage = Double(userDelta + systemDelta) / Double(totalDelta) * 100.0
            }
        }

        prevUserTicks = totalUser
        prevSystemTicks = totalSystem
        prevIdleTicks = totalIdle
        prevNiceTicks = totalNice
        hasPreviousCPU = true
    }

    // MARK: - Memory (host_statistics64)

    private func fetchMemory() {
        let hostPort = mach_host_self()
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)

        let result = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(hostPort, HOST_VM_INFO64, intPtr, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }

        let pageSize = UInt64(vm_kernel_page_size)
        let active = UInt64(stats.active_count) * pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize

        let usedBytes = active + wired + compressed
        let totalBytes = ProcessInfo.processInfo.physicalMemory

        memoryUsed = Double(usedBytes) / 1_073_741_824.0
        memoryTotal = Double(totalBytes) / 1_073_741_824.0
    }

    // MARK: - Disk (FileManager)

    private func fetchDisk() {
        do {
            let attrs = try FileManager.default.attributesOfFileSystem(forPath: "/")
            let total = attrs[.systemSize] as? Int64 ?? 0
            let free = attrs[.systemFreeSize] as? Int64 ?? 0
            let used = total - free
            diskUsed = Double(used) / 1_073_741_824.0
            diskTotal = Double(total) / 1_073_741_824.0
        } catch {
            // Leave values unchanged on error
        }
    }

    // MARK: - Network (getifaddrs)

    private func fetchNetwork() {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return }
        defer { freeifaddrs(ifaddr) }

        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0

        var cursor: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let addr = cursor {
            guard let addrPtr = addr.pointee.ifa_addr else {
                cursor = addr.pointee.ifa_next
                continue
            }
            let family = addrPtr.pointee.sa_family
            if family == UInt8(AF_LINK) {
                let name = String(cString: addr.pointee.ifa_name)
                if name.hasPrefix("en") {
                    let data = unsafeBitCast(addr.pointee.ifa_data, to: UnsafeMutablePointer<if_data>.self)
                    totalIn += UInt64(data.pointee.ifi_ibytes)
                    totalOut += UInt64(data.pointee.ifi_obytes)
                }
            }
            cursor = addr.pointee.ifa_next
        }

        let now = Date()
        if let prevTimestamp = prevNetTimestamp {
            let elapsed = now.timeIntervalSince(prevTimestamp)
            if elapsed > 0 {
                let deltaIn = totalIn >= prevNetBytesIn ? totalIn - prevNetBytesIn : 0
                let deltaOut = totalOut >= prevNetBytesOut ? totalOut - prevNetBytesOut : 0
                networkBytesInPerSec = Int64(Double(deltaIn) / elapsed)
                networkBytesOutPerSec = Int64(Double(deltaOut) / elapsed)
            }
        }

        prevNetBytesIn = totalIn
        prevNetBytesOut = totalOut
        prevNetTimestamp = now
    }

    // MARK: - Formatting Helpers

    private func formatBytesPerSec(_ bytes: Int64) -> String {
        let b = Double(bytes)
        if b >= 1_000_000 {
            return String(format: "%.1f MB/s", b / 1_000_000)
        } else if b >= 1_000 {
            return String(format: "%.0f KB/s", b / 1_000)
        } else {
            return "\(bytes) B/s"
        }
    }
}
