import Foundation
import Darwin
import IOKit.ps
import Network
import CoreWLAN
import SystemConfiguration
import Combine

final class SystemMonitorService: ObservableObject {
    @Published var cpuUsage: Double = 0.12
    @Published var cpuText: String = "12%"
    @Published var chipName: String = "Apple Silicon"
    @Published var coreCountText: String = "\(ProcessInfo.processInfo.processorCount) Cores"

    @Published var memoryUsedBytes: UInt64 = 0
    @Published var memoryTotalBytes: UInt64 = 0
    @Published var memoryRatio: Double = 0.5
    @Published var memoryUsedText: String = "0 GB"
    @Published var memoryFreeText: String = "0 GB"
    @Published var memoryPercentText: String = "0%"

    @Published var batteryRatio: Double = 1.0
    @Published var batteryText: String = "100%"
    @Published var batterySourceText: String = "AC Power"
    @Published var isCharging: Bool = false
    @Published var hasBattery: Bool = true

    @Published var networkStatusText: String = "Online"
    @Published var networkInterfaceText: String = "Connected"
    @Published var networkNameText: String = "Wi-Fi"
    @Published var localIPText: String = "Connected"
    @Published var isOnline: Bool = true

    private var timer: AnyCancellable?
    private let pathMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.mackitty.networkmonitor", qos: .utility)
    private var prevCPUTicks: host_cpu_load_info?

    init() {
        memoryTotalBytes = UInt64(ProcessInfo.processInfo.physicalMemory)
        chipName = queryChipName()
        startNetworkMonitoring()
        sampleAll()
        startTimer()
    }

    deinit {
        timer?.cancel()
        pathMonitor.cancel()
    }

    func startTimer() {
        timer?.cancel()
        timer = Timer.publish(every: 2.5, tolerance: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.sampleAll()
            }
    }

    func stopTimer() {
        timer?.cancel()
        timer = nil
    }

    func sampleAll() {
        sampleMemory()
        sampleCPU()
        sampleBattery()
        sampleNetwork()
    }

    // MARK: - Memory (Mach kernel host_statistics64)
    private func sampleMemory() {
        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return }

        let pageSize = UInt64(vm_kernel_page_size)
        let active = UInt64(vmStats.active_count) * pageSize
        let wire = UInt64(vmStats.wire_count) * pageSize
        let compressed = UInt64(vmStats.compressor_page_count) * pageSize
        let used = active + wire + compressed
        let total = memoryTotalBytes > 0 ? memoryTotalBytes : UInt64(ProcessInfo.processInfo.physicalMemory)
        let free = total > used ? (total - used) : 0
        let ratio = total > 0 ? min(max(Double(used) / Double(total), 0.0), 1.0) : 0.0

        memoryUsedBytes = used
        memoryRatio = ratio
        memoryUsedText = ByteCountFormatter.string(fromByteCount: Int64(used), countStyle: .memory)
        memoryFreeText = "\(ByteCountFormatter.string(fromByteCount: Int64(free), countStyle: .memory)) free"
        memoryPercentText = "\(Int(round(ratio * 100)))% used"
    }

    // MARK: - CPU (Mach host_cpu_load_info)
    private func sampleCPU() {
        var cpuLoad = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &cpuLoad) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return }

        if let prev = prevCPUTicks {
            let user = Double(cpuLoad.cpu_ticks.0 - prev.cpu_ticks.0)
            let sys = Double(cpuLoad.cpu_ticks.1 - prev.cpu_ticks.1)
            let idle = Double(cpuLoad.cpu_ticks.2 - prev.cpu_ticks.2)
            let nice = Double(cpuLoad.cpu_ticks.3 - prev.cpu_ticks.3)
            let total = user + sys + idle + nice
            if total > 0 {
                let usage = min(max((user + sys + nice) / total, 0.01), 1.0)
                cpuUsage = usage
                cpuText = "\(Int(round(usage * 100)))%"
            }
        }
        prevCPUTicks = cpuLoad
    }

    // MARK: - Battery (IOKit Power Sources)
    private func sampleBattery() {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              !sources.isEmpty else {
            hasBattery = false
            batteryText = "AC Power"
            batterySourceText = "Desktop"
            batteryRatio = 1.0
            return
        }

        var foundBattery = false
        for ps in sources {
            guard let desc = IOPSGetPowerSourceDescription(snapshot, ps)?.takeUnretainedValue() as? [String: Any] else { continue }
            let cur = desc[kIOPSCurrentCapacityKey as String] as? Int ?? 0
            let maxCap = desc[kIOPSMaxCapacityKey as String] as? Int ?? 100
            let charging = desc[kIOPSIsChargingKey as String] as? Bool ?? false
            let pState = desc[kIOPSPowerSourceStateKey as String] as? String ?? ""

            let ratio = maxCap > 0 ? min(max(Double(cur) / Double(maxCap), 0.0), 1.0) : 0.0
            batteryRatio = ratio
            batteryText = "\(Int(round(ratio * 100)))%"
            isCharging = charging
            batterySourceText = charging ? "Charging" : (pState == (kIOPSACPowerValue as String) ? "Plugged in" : "On Battery")
            hasBattery = true
            foundBattery = true
            break
        }

        if !foundBattery {
            hasBattery = false
            batteryText = "AC Power"
            batterySourceText = "Desktop"
            batteryRatio = 1.0
        }
    }

    // MARK: - Network (NWPathMonitor)
    private func startNetworkMonitoring() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isOnline = path.status == .satisfied
                if path.status == .satisfied {
                    self.networkStatusText = "Online"
                    if path.usesInterfaceType(.wifi) {
                        self.networkInterfaceText = "Wi-Fi"
                    } else if path.usesInterfaceType(.wiredEthernet) {
                        self.networkInterfaceText = "Ethernet"
                    } else if path.usesInterfaceType(.cellular) {
                        self.networkInterfaceText = "Cellular"
                    } else {
                        self.networkInterfaceText = "Connected"
                    }
                } else {
                    self.networkStatusText = "Offline"
                    self.networkInterfaceText = "Disconnected"
                }
            }
        }
        pathMonitor.start(queue: monitorQueue)
    }

    private func sampleNetwork() {
        var foundName: String?
        if let iface = CWWiFiClient.shared().interface(), let ssid = iface.ssid(), !ssid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            foundName = ssid.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if foundName == nil || foundName?.isEmpty == true {
            if let store = SCDynamicStoreCreate(nil, "com.mackitty.net" as CFString, nil, nil) {
                if let ipv4 = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any],
                   let serviceID = ipv4["PrimaryService"] as? String {
                    if let service = SCDynamicStoreCopyValue(store, "Setup:/Network/Service/\(serviceID)" as CFString) as? [String: Any],
                       let serviceName = service["UserDefinedName"] as? String, !serviceName.isEmpty {
                        foundName = serviceName
                    }
                    if let serviceState = SCDynamicStoreCopyValue(store, "State:/Network/Service/\(serviceID)/IPv4" as CFString) as? [String: Any],
                       let addrs = serviceState["Addresses"] as? [String], let first = addrs.first {
                        localIPText = first
                    }
                }
            }
        }

        if let found = foundName, !found.isEmpty {
            networkNameText = found
        } else {
            networkNameText = networkInterfaceText
        }
    }

    private func queryChipName() -> String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        guard size > 0 else { return "Apple Silicon" }
        var name = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &name, &size, nil, 0)
        let brand = String(cString: name).trimmingCharacters(in: .whitespacesAndNewlines)
        return brand.isEmpty ? "Apple Silicon" : brand
    }
}
