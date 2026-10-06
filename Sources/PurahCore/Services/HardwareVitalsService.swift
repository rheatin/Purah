// Sources/PurahCore/Services/HardwareVitalsService.swift
import Foundation
import AppKit
import Darwin
import Observation
import IOKit
import IOKit.ps

public struct ProcessInfoItem: Identifiable, Sendable {
    public let id: Int32
    public var name: String
    public var cpuPercent: Double
    public var memoryPercent: Double

    public init(id: Int32, name: String, cpuPercent: Double, memoryPercent: Double) {
        self.id = id
        self.name = name
        self.cpuPercent = cpuPercent
        self.memoryPercent = memoryPercent
    }
}

public struct HardwareVitalsInfo: Sendable {
    public var cpuUsage: Double // 0.0 ~ 1.0
    public var gpuUsage: Double // 0.0 ~ 1.0
    public var memoryUsage: Double // 0.0 ~ 1.0
    public var memoryUsedGB: Double
    public var memoryTotalGB: Double
    public var diskFreeGB: Double
    public var diskTotalGB: Double
    public var batteryLevel: Int
    public var isCharging: Bool
    public var powerSource: String
    public var thermalStateDescription: String
    public var isUnderThermalPressure: Bool
    public var networkDownSpeed: Double // bytes/sec
    public var networkUpSpeed: Double // bytes/sec
    public var topProcesses: [ProcessInfoItem]

    public init(
        cpuUsage: Double = 0.15,
        gpuUsage: Double = 0.05,
        memoryUsage: Double = 0.45,
        memoryUsedGB: Double = 8.0,
        memoryTotalGB: Double = 16.0,
        diskFreeGB: Double = 256.0,
        diskTotalGB: Double = 512.0,
        batteryLevel: Int = 100,
        isCharging: Bool = false,
        powerSource: String = "AC Power",
        thermalStateDescription: String = "Nominal",
        isUnderThermalPressure: Bool = false,
        networkDownSpeed: Double = 0.0,
        networkUpSpeed: Double = 0.0,
        topProcesses: [ProcessInfoItem] = []
    ) {
        self.cpuUsage = cpuUsage
        self.gpuUsage = gpuUsage
        self.memoryUsage = memoryUsage
        self.memoryUsedGB = memoryUsedGB
        self.memoryTotalGB = memoryTotalGB
        self.diskFreeGB = diskFreeGB
        self.diskTotalGB = diskTotalGB
        self.batteryLevel = batteryLevel
        self.isCharging = isCharging
        self.powerSource = powerSource
        self.thermalStateDescription = thermalStateDescription
        self.isUnderThermalPressure = isUnderThermalPressure
        self.networkDownSpeed = networkDownSpeed
        self.networkUpSpeed = networkUpSpeed
        self.topProcesses = topProcesses
    }
}

@Observable
public final class HardwareVitalsService: @unchecked Sendable {
    public static let shared = HardwareVitalsService()

    public private(set) var metrics: HardwareVitalsInfo = .init()
    @ObservationIgnored private var timer: Timer?

    @ObservationIgnored private var previousCpuInfo: processor_info_array_t?
    @ObservationIgnored private var previousCpuInfoCount: mach_msg_type_number_t = 0
    @ObservationIgnored private var previousNetworkInBytes: UInt64?
    @ObservationIgnored private var previousNetworkOutBytes: UInt64?
    @ObservationIgnored private var previousNetworkTimestamp: Date?

    public init() {
        Task.detached(priority: .utility) { [weak self] in
            await self?.refreshMetricsAsync(includeProcesses: false)
            try? await Task.sleep(nanoseconds: 200_000_000)
            await self?.refreshMetricsAsync(includeProcesses: false)
        }
        startMonitoring(interval: 1.0)
    }

    public func startMonitoring(interval: TimeInterval = 1.0) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task.detached(priority: .utility) { [weak self] in
                // Lightweight periodic poll (CPU, RAM, Battery, Disk without process enumeration)
                await self?.refreshMetricsAsync(includeProcesses: false)
            }
        }
    }

    public func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    public func refreshMetrics(includeProcesses: Bool = true) {
        let cpu = readCPUUsage()
        let gpu = readGPUUsage()
        let mem = readMemoryBreakdown()
        let disk = readDiskSpace()
        let battery = readBatteryInfo()
        let thermal = readThermalState()
        let net = readNetworkThroughput()
        let top = includeProcesses ? readTopProcessesNative() : metrics.topProcesses

        metrics = HardwareVitalsInfo(
            cpuUsage: cpu,
            gpuUsage: gpu,
            memoryUsage: mem.usage,
            memoryUsedGB: mem.usedGB,
            memoryTotalGB: mem.totalGB,
            diskFreeGB: disk.freeGB,
            diskTotalGB: disk.totalGB,
            batteryLevel: battery.level,
            isCharging: battery.isCharging,
            powerSource: battery.source,
            thermalStateDescription: thermal.description,
            isUnderThermalPressure: thermal.isPressure || cpu > 0.80 || mem.usage > 0.85 || gpu > 0.85,
            networkDownSpeed: net.down,
            networkUpSpeed: net.up,
            topProcesses: top
        )
    }

    public func refreshMetricsAsync(includeProcesses: Bool = false) async {
        let cpu = readCPUUsage()
        let gpu = readGPUUsage()
        let mem = readMemoryBreakdown()
        let disk = readDiskSpace()
        let battery = readBatteryInfo()
        let thermal = readThermalState()
        let net = readNetworkThroughput()
        let currentProcesses = await MainActor.run { self.metrics.topProcesses }
        let top = includeProcesses ? readTopProcessesNative() : (currentProcesses.isEmpty ? readTopProcessesNative() : currentProcesses)

        await MainActor.run {
            self.metrics = HardwareVitalsInfo(
                cpuUsage: cpu,
                gpuUsage: gpu,
                memoryUsage: mem.usage,
                memoryUsedGB: mem.usedGB,
                memoryTotalGB: mem.totalGB,
                diskFreeGB: disk.freeGB,
                diskTotalGB: disk.totalGB,
                batteryLevel: battery.level,
                isCharging: battery.isCharging,
                powerSource: battery.source,
                thermalStateDescription: thermal.description,
                isUnderThermalPressure: thermal.isPressure || cpu > 0.80 || mem.usage > 0.85 || gpu > 0.85,
                networkDownSpeed: net.down,
                networkUpSpeed: net.up,
                topProcesses: top
            )
        }
    }

    public func killProcess(pid: Int32) {
        if let app = NSRunningApplication(processIdentifier: pid) {
            app.forceTerminate()
        } else {
            kill(pid, SIGTERM)
        }

        Task.detached(priority: .utility) { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            await self?.refreshMetricsAsync(includeProcesses: true)
        }
    }

    // MARK: - Mach Kernel & System APIs (100% Native C/Darwin, zero overhead)

    private func readDiskSpace() -> (freeGB: Double, totalGB: Double) {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: "/") else {
            return (256.0, 512.0)
        }
        let total = (attrs[.systemSize] as? Int64) ?? 0
        let free = (attrs[.systemFreeSize] as? Int64) ?? 0
        let totalGB = Double(total) / 1_000_000_000.0
        let freeGB = Double(free) / 1_000_000_000.0
        return (freeGB, totalGB)
    }

    private func readBatteryInfo() -> (level: Int, isCharging: Bool, source: String) {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return (100, false, "AC Power")
        }
        for source in sources {
            if let desc = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] {
                let cap = desc[kIOPSCurrentCapacityKey] as? Int ?? 100
                let isCharging = desc[kIOPSIsChargingKey] as? Bool ?? false
                let source = desc[kIOPSPowerSourceStateKey] as? String ?? "AC Power"
                let sourceName = (source == kIOPSACPowerValue) ? "AC Power" : "Battery"
                return (cap, isCharging, sourceName)
            }
        }
        return (100, false, "AC Power")
    }

    private func readThermalState() -> (description: String, isPressure: Bool) {
        let state = ProcessInfo.processInfo.thermalState
        switch state {
        case .nominal: return ("Nominal", false)
        case .fair: return ("Fair", false)
        case .serious: return ("Serious", true)
        case .critical: return ("Critical", true)
        @unknown default: return ("Normal", false)
        }
    }

    private func readMemoryBreakdown() -> (usage: Double, usedGB: Double, totalGB: Double) {
        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        let totalMem = Double(ProcessInfo.processInfo.physicalMemory)
        let totalGB = totalMem / 1_073_741_824.0

        guard result == KERN_SUCCESS else { return (0.45, totalGB * 0.45, totalGB) }

        let pageSize = Double(getpagesize())
        let active = Double(vmStats.active_count) * pageSize
        let wired = Double(vmStats.wire_count) * pageSize
        let compressed = Double(vmStats.compressor_page_count) * pageSize
        let used = active + wired + compressed
        let usedGB = used / 1_073_741_824.0
        let usage = min(max(used / totalMem, 0.0), 1.0)
        return (usage, usedGB, totalGB)
    }

    private func readCPUUsage() -> Double {
        var numProcessors: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var numCpuInfo: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numProcessors,
            &cpuInfo,
            &numCpuInfo
        )

        guard result == KERN_SUCCESS, let cpuInfo = cpuInfo else { return 0.15 }

        var totalUsage: Double = 0.0

        if let prev = previousCpuInfo {
            var inUse: Int32 = 0
            var total: Int32 = 0

            for i in 0..<Int32(numProcessors) {
                let u = cpuInfo[Int(CPU_STATE_MAX * i + CPU_STATE_USER)] - prev[Int(CPU_STATE_MAX * i + CPU_STATE_USER)]
                let s = cpuInfo[Int(CPU_STATE_MAX * i + CPU_STATE_SYSTEM)] - prev[Int(CPU_STATE_MAX * i + CPU_STATE_SYSTEM)]
                let n = cpuInfo[Int(CPU_STATE_MAX * i + CPU_STATE_NICE)] - prev[Int(CPU_STATE_MAX * i + CPU_STATE_NICE)]
                let id = cpuInfo[Int(CPU_STATE_MAX * i + CPU_STATE_IDLE)] - prev[Int(CPU_STATE_MAX * i + CPU_STATE_IDLE)]

                inUse += (u + s + n)
                total += (u + s + n + id)
            }

            if total > 0 {
                totalUsage = Double(inUse) / Double(total)
            }
        } else {
            totalUsage = 0.15
        }

        if let prev = previousCpuInfo {
            let byteSize = vm_size_t(previousCpuInfoCount * mach_msg_type_number_t(MemoryLayout<integer_t>.stride))
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: prev), byteSize)
        }

        previousCpuInfo = cpuInfo
        previousCpuInfoCount = numCpuInfo

        return min(max(totalUsage, 0.0), 1.0)
    }

    deinit {
        timer?.invalidate()
        if let prev = previousCpuInfo {
            let byteSize = vm_size_t(previousCpuInfoCount * mach_msg_type_number_t(MemoryLayout<integer_t>.stride))
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: prev), byteSize)
        }
    }

    // MARK: - Native Darwin proc_pidinfo & NSWorkspace collection
    private func readTopProcessesNative() -> [ProcessInfoItem] {
        let apps = NSWorkspace.shared.runningApplications
        var items: [ProcessInfoItem] = []
        let totalMemBytes = Double(ProcessInfo.processInfo.physicalMemory)

        for app in apps {
            let pid = app.processIdentifier
            guard pid > 0, let name = app.localizedName, !name.isEmpty else { continue }

            var taskInfo = proc_taskinfo()
            let size = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, Int32(MemoryLayout<proc_taskinfo>.size))
            if size == MemoryLayout<proc_taskinfo>.size {
                let memBytes = Double(taskInfo.pti_resident_size)
                let memPercent = min(max((memBytes / totalMemBytes) * 100.0, 0.0), 100.0)
                let cpuTimeMs = Double(taskInfo.pti_total_user + taskInfo.pti_total_system) / 100_000_000.0
                let cpuPercent = min(max(cpuTimeMs.truncatingRemainder(dividingBy: 100.0), 0.5), 99.0)

                items.append(ProcessInfoItem(
                    id: pid,
                    name: name,
                    cpuPercent: cpuPercent,
                    memoryPercent: memPercent
                ))
            }
        }

        items.sort { $0.memoryPercent > $1.memoryPercent }
        return Array(items.prefix(3))
    }

    // MARK: - Zero-Overhead GPU & Network Telemetry

    public func readGPUUsage() -> Double {
        var iterator: io_iterator_t = 0
        let matchDict = IOServiceMatching("IOAccelerator")
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matchDict, &iterator)
        guard result == kIOReturnSuccess, iterator != 0 else { return 0.0 }
        defer { IOObjectRelease(iterator) }

        var maxUsage: Double = 0.0
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == kIOReturnSuccess,
               let dict = props?.takeRetainedValue() as? [String: Any],
               let perfStats = dict["PerformanceStatistics"] as? [String: Any] {
                if let devUtil = perfStats["Device Utilization %"] as? NSNumber {
                    let util = devUtil.doubleValue / 100.0
                    maxUsage = max(maxUsage, util)
                } else if let devUtil = perfStats["Device Utilization %"] as? Int {
                    let util = Double(devUtil) / 100.0
                    maxUsage = max(maxUsage, util)
                } else if let rendUtil = perfStats["Renderer Utilization %"] as? NSNumber {
                    let util = rendUtil.doubleValue / 100.0
                    maxUsage = max(maxUsage, util)
                }
            }
        }
        return min(max(maxUsage, 0.0), 1.0)
    }

    public func readNetworkThroughput() -> (down: Double, up: Double) {
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else {
            return (0.0, 0.0)
        }
        defer { freeifaddrs(ifap) }

        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0
        var ptr: UnsafeMutablePointer<ifaddrs>? = first

        while let cur = ptr {
            let flags = cur.pointee.ifa_flags
            if (flags & UInt32(IFF_UP)) != 0 && (flags & UInt32(IFF_LOOPBACK)) == 0 {
                if let addr = cur.pointee.ifa_addr,
                   addr.pointee.sa_family == UInt8(AF_LINK),
                   let data = cur.pointee.ifa_data {
                    let ifData = data.assumingMemoryBound(to: if_data.self).pointee
                    totalIn += UInt64(ifData.ifi_ibytes)
                    totalOut += UInt64(ifData.ifi_obytes)
                }
            }
            ptr = cur.pointee.ifa_next
        }

        let now = Date()
        var downSpeed: Double = 0.0
        var upSpeed: Double = 0.0

        if let prevIn = previousNetworkInBytes,
           let prevOut = previousNetworkOutBytes,
           let prevTime = previousNetworkTimestamp {
            let elapsed = now.timeIntervalSince(prevTime)
            if elapsed > 0.05 {
                let deltaIn = totalIn >= prevIn ? Double(totalIn - prevIn) : 0.0
                let deltaOut = totalOut >= prevOut ? Double(totalOut - prevOut) : 0.0
                downSpeed = deltaIn / elapsed
                upSpeed = deltaOut / elapsed
            }
        }

        previousNetworkInBytes = totalIn
        previousNetworkOutBytes = totalOut
        previousNetworkTimestamp = now

        return (max(downSpeed, 0.0), max(upSpeed, 0.0))
    }
}
