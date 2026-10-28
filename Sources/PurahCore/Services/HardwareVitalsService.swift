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
    public var memoryMB: Double

    public init(id: Int32, name: String, cpuPercent: Double, memoryPercent: Double, memoryMB: Double = 0.0) {
        self.id = id
        self.name = name
        self.cpuPercent = cpuPercent
        self.memoryPercent = memoryPercent
        self.memoryMB = memoryMB
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
    public var networkDownSpeed: Double // bytes/sec
    public var networkUpSpeed: Double // bytes/sec
    public var topProcesses: [ProcessInfoItem]

    // Deep Hardware Telemetry
    // CPU & System
    public var cpuUserUsage: Double
    public var cpuSystemUsage: Double
    public var cpuIdleUsage: Double
    public var loadAverage1m: Double
    public var loadAverage5m: Double
    public var loadAverage15m: Double
    public var chipModelName: String
    public var performanceCoreCount: Int
    public var efficiencyCoreCount: Int
    public var thermalStateLabel: String

    // Memory (RAM)
    public var memoryAppGB: Double
    public var memoryWiredGB: Double
    public var memoryCompressedGB: Double
    public var memorySwapUsedMB: Double
    public var memoryPressureLevel: String

    // Network
    public var networkInterfaceName: String
    public var localIPAddress: String
    public var networkTotalReceivedGB: Double
    public var networkTotalSentGB: Double

    // Disk I/O
    public var diskReadBytesPerSec: Double
    public var diskWriteBytesPerSec: Double

    // Battery & Thermal
    public var batteryHealthPercent: Int
    public var batteryCycleCount: Int
    public var batteryTemperatureCelsius: Double

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
        networkDownSpeed: Double = 0.0,
        networkUpSpeed: Double = 0.0,
        topProcesses: [ProcessInfoItem] = [],
        cpuUserUsage: Double = 0.10,
        cpuSystemUsage: Double = 0.05,
        cpuIdleUsage: Double = 0.85,
        loadAverage1m: Double = 1.0,
        loadAverage5m: Double = 1.0,
        loadAverage15m: Double = 1.0,
        chipModelName: String = "Apple Silicon",
        performanceCoreCount: Int = 0,
        efficiencyCoreCount: Int = 0,
        thermalStateLabel: String = "Nominal",
        memoryAppGB: Double = 4.0,
        memoryWiredGB: Double = 2.0,
        memoryCompressedGB: Double = 1.0,
        memorySwapUsedMB: Double = 0.0,
        memoryPressureLevel: String = "Normal",
        networkInterfaceName: String = "en0",
        localIPAddress: String = "—",
        networkTotalReceivedGB: Double = 0.0,
        networkTotalSentGB: Double = 0.0,
        diskReadBytesPerSec: Double = 0.0,
        diskWriteBytesPerSec: Double = 0.0,
        batteryHealthPercent: Int = 100,
        batteryCycleCount: Int = 0,
        batteryTemperatureCelsius: Double = 31.0
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
        self.networkDownSpeed = networkDownSpeed
        self.networkUpSpeed = networkUpSpeed
        self.topProcesses = topProcesses
        self.cpuUserUsage = cpuUserUsage
        self.cpuSystemUsage = cpuSystemUsage
        self.cpuIdleUsage = cpuIdleUsage
        self.loadAverage1m = loadAverage1m
        self.loadAverage5m = loadAverage5m
        self.loadAverage15m = loadAverage15m
        self.chipModelName = chipModelName
        self.performanceCoreCount = performanceCoreCount
        self.efficiencyCoreCount = efficiencyCoreCount
        self.thermalStateLabel = thermalStateLabel
        self.memoryAppGB = memoryAppGB
        self.memoryWiredGB = memoryWiredGB
        self.memoryCompressedGB = memoryCompressedGB
        self.memorySwapUsedMB = memorySwapUsedMB
        self.memoryPressureLevel = memoryPressureLevel
        self.networkInterfaceName = networkInterfaceName
        self.localIPAddress = localIPAddress
        self.networkTotalReceivedGB = networkTotalReceivedGB
        self.networkTotalSentGB = networkTotalSentGB
        self.diskReadBytesPerSec = diskReadBytesPerSec
        self.diskWriteBytesPerSec = diskWriteBytesPerSec
        self.batteryHealthPercent = batteryHealthPercent
        self.batteryCycleCount = batteryCycleCount
        self.batteryTemperatureCelsius = batteryTemperatureCelsius
    }
}

private final class CpuTelemetryBuffer: @unchecked Sendable {
    var previousCpuInfo: processor_info_array_t?
    var previousCpuInfoCount: mach_msg_type_number_t = 0
    var previousNetworkInBytes: UInt64?
    var previousNetworkOutBytes: UInt64?
    var previousNetworkTimestamp: Date?
    var previousDiskReadBytes: UInt64?
    var previousDiskWriteBytes: UInt64?
    var previousDiskTimestamp: Date?
    /// Per-PID CPU accounting. `pti_total_user + pti_total_system` is a
    /// monotonic nanosecond counter, so a process's share of the CPU is the
    /// delta since the previous sample divided by the wall-clock delta.
    /// Deriving it from the raw counter (as the old `% 100` did) produced a
    /// meaningless number.
    var previousProcessCPUTimeNs: [Int32: UInt64] = [:]
    var previousProcessSampleTimestamp: Date?

    deinit {
        if let prev = previousCpuInfo {
            let byteSize = vm_size_t(previousCpuInfoCount * mach_msg_type_number_t(MemoryLayout<integer_t>.stride))
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: prev), byteSize)
        }
    }
}

@Observable
@MainActor
public final class HardwareVitalsService {
    public static let shared = HardwareVitalsService()

    public private(set) var metrics: HardwareVitalsInfo = .init()
    public private(set) var cpuHistory: [VitalsHistoryPoint] = []
    public private(set) var gpuHistory: [VitalsHistoryPoint] = []
    public private(set) var ramHistory: [VitalsHistoryPoint] = []
    public private(set) var powerHistory: [VitalsHistoryPoint] = []
    public private(set) var networkHistory: [VitalsHistoryPoint] = []
    public private(set) var networkDownHistory: [VitalsHistoryPoint] = []
    public private(set) var networkUpHistory: [VitalsHistoryPoint] = []
    public private(set) var diskHistory: [VitalsHistoryPoint] = []

    public var selectedTimeScope: VitalsTimeScope = .realTime30s
    public var isDrawerVisible: Bool = false

    @ObservationIgnored private var monitorTask: Task<Void, Never>?
    @ObservationIgnored private let buffer = CpuTelemetryBuffer()
    @ObservationIgnored private let hostPort: mach_port_t = mach_host_self()
    @ObservationIgnored private var saveThrottleCounter = 0

    // Dedicated Permanent Storage: ~/Library/Application Support/Purah/Vitals/
    @ObservationIgnored public static let defaultStorageDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return appSupport.appendingPathComponent("Purah/Vitals", isDirectory: true)
    }()

    @ObservationIgnored public let storageDirectory: URL
    @ObservationIgnored private var historyFileURL: URL {
        storageDirectory.appendingPathComponent("vitals_history.json")
    }

    public var isMonitoring: Bool {
        monitorTask != nil
    }

    private static let cachedChipModel: String = {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        if size > 0 {
            var buffer = [CChar](repeating: 0, count: size)
            if sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0) == 0 {
                if let str = buffer.withUnsafeBufferPointer({ ptr -> String? in
                    guard let base = ptr.baseAddress else { return nil }
                    return String(validatingCString: base)
                })?.trimmingCharacters(in: .whitespacesAndNewlines), !str.isEmpty {
                    return str
                }
            }
        }
        var modelSize = 0
        sysctlbyname("hw.model", nil, &modelSize, nil, 0)
        if modelSize > 0 {
            var modelBuffer = [CChar](repeating: 0, count: modelSize)
            if sysctlbyname("hw.model", &modelBuffer, &modelSize, nil, 0) == 0 {
                if let str = modelBuffer.withUnsafeBufferPointer({ ptr -> String? in
                    guard let base = ptr.baseAddress else { return nil }
                    return String(validatingCString: base)
                })?.trimmingCharacters(in: .whitespacesAndNewlines), !str.isEmpty {
                    return str
                }
            }
        }
        return "Apple Silicon"
    }()

    private static let cachedCoreCounts: (p: Int, e: Int) = {
        var pCores: Int32 = 0
        var pSize = MemoryLayout<Int32>.size
        let pResult = sysctlbyname("hw.perflevel0.physicalcpu", &pCores, &pSize, nil, 0)

        var eCores: Int32 = 0
        var eSize = MemoryLayout<Int32>.size
        let eResult = sysctlbyname("hw.perflevel1.physicalcpu", &eCores, &eSize, nil, 0)

        let pCount = pResult == 0 ? Int(pCores) : 0
        let eCount = eResult == 0 ? Int(eCores) : 0
        if pCount == 0 && eCount == 0 {
            return (ProcessInfo.processInfo.activeProcessorCount, 0)
        }
        return (pCount, eCount)
    }()

    public init(storageDirectory: URL = defaultStorageDirectory) {
        self.storageDirectory = storageDirectory
        loadHistoryFromDisk()
        // Collect initial baseline snapshot on startup without kicking off continuous kernel polling
        refreshMetrics(includeProcesses: false)
    }

    public func history(for metric: VitalsMetricType, scope: VitalsTimeScope? = nil) -> [VitalsHistoryPoint] {
        let activeScope = scope ?? selectedTimeScope
        let allPoints: [VitalsHistoryPoint] = {
            switch metric {
            case .cpu: return cpuHistory
            case .gpu: return gpuHistory
            case .ram: return ramHistory
            case .power: return powerHistory
            case .network: return networkDownHistory
            case .disk: return diskHistory
            }
        }()
        let now = Date()
        let dur = activeScope.durationSeconds
        return allPoints.filter { now.timeIntervalSince($0.timestamp) <= dur }
    }

    public func networkUpHistory(scope: VitalsTimeScope? = nil) -> [VitalsHistoryPoint] {
        let activeScope = scope ?? selectedTimeScope
        let now = Date()
        let dur = activeScope.durationSeconds
        return networkUpHistory.filter { now.timeIntervalSince($0.timestamp) <= dur }
    }

    private func appendHistory(_ array: inout [VitalsHistoryPoint], point: VitalsHistoryPoint, maxSamples: Int = 2880) {
        let maxAge: TimeInterval = 24 * 3600 // Retain up to 24 hours of telemetry
        let now = point.timestamp
        if array.capacity < maxSamples + 10 {
            array.reserveCapacity(maxSamples + 10)
        }
        array.append(point)
        // Purge points older than 24 hours
        if let first = array.first, now.timeIntervalSince(first.timestamp) > maxAge {
            array.removeAll { now.timeIntervalSince($0.timestamp) > maxAge }
        }
        // Strict boundary: 2880 points (24 hours at 30-second cadence)
        if array.count > maxSamples {
            let overflow = array.count - maxSamples
            array.removeFirst(overflow)
        }
    }

    public func saveHistoryToDisk() {
        let container = VitalsPersistedHistory(
            cpu: cpuHistory,
            gpu: gpuHistory,
            ram: ramHistory,
            power: powerHistory,
            networkDown: networkDownHistory,
            networkUp: networkUpHistory,
            disk: diskHistory
        )
        do {
            try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            let data = try encoder.encode(container)
            try data.write(to: historyFileURL, options: .atomic)
        } catch {
            // Silently ignore disk write failures in background
        }
    }

    public func loadHistoryFromDisk() {
        guard FileManager.default.fileExists(atPath: historyFileURL.path) else { return }
        do {
            let data = try Data(contentsOf: historyFileURL)
            let container = try JSONDecoder().decode(VitalsPersistedHistory.self, from: data)
            let now = Date()
            let maxAge: TimeInterval = 24 * 3600

            // Strictly filter loaded points to within 24 hours
            self.cpuHistory = container.cpu.filter { now.timeIntervalSince($0.timestamp) <= maxAge }
            self.gpuHistory = container.gpu.filter { now.timeIntervalSince($0.timestamp) <= maxAge }
            self.ramHistory = container.ram.filter { now.timeIntervalSince($0.timestamp) <= maxAge }
            self.powerHistory = container.power.filter { now.timeIntervalSince($0.timestamp) <= maxAge }
            self.networkDownHistory = container.networkDown.filter { now.timeIntervalSince($0.timestamp) <= maxAge }
            self.networkUpHistory = container.networkUp.filter { now.timeIntervalSince($0.timestamp) <= maxAge }
            self.networkHistory = self.networkDownHistory
            self.diskHistory = container.disk.filter { now.timeIntervalSince($0.timestamp) <= maxAge }
        } catch {
            // In case of corrupt file, fallback to empty history
        }
    }

    public func startMonitoring(interval: TimeInterval = 1.0) {
        guard monitorTask == nil else { return }
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { break }
                self.saveThrottleCounter += 1
                self.refreshMetrics(includeProcesses: self.isDrawerVisible && (self.saveThrottleCounter % 3 == 0))
                if self.saveThrottleCounter >= 60 {
                    self.saveThrottleCounter = 0
                    self.saveHistoryToDisk()
                }
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    public func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
        saveHistoryToDisk()
    }

    public func refreshMetrics(includeProcesses: Bool = true) {
        let cpuBreakdown = readCPUBreakdown()
        let loads = readLoadAverages()
        let gpu = readGPUUsage()
        let mem = readMemoryBreakdown()
        let disk = readDiskSpace()
        let diskIO = readDiskIOThroughput()
        let battery = readBatteryInfo()
        let net = readNetworkThroughputDetailed()
        let top = includeProcesses ? readTopProcessesNative() : metrics.topProcesses
        let thermal = readThermalStateLabel()

        metrics = HardwareVitalsInfo(
            cpuUsage: cpuBreakdown.totalUsage,
            gpuUsage: gpu,
            memoryUsage: mem.usage,
            memoryUsedGB: mem.usedGB,
            memoryTotalGB: mem.totalGB,
            diskFreeGB: disk.freeGB,
            diskTotalGB: disk.totalGB,
            batteryLevel: battery.level,
            isCharging: battery.isCharging,
            powerSource: battery.source,
            networkDownSpeed: net.down,
            networkUpSpeed: net.up,
            topProcesses: top,
            cpuUserUsage: cpuBreakdown.userUsage,
            cpuSystemUsage: cpuBreakdown.sysUsage,
            cpuIdleUsage: cpuBreakdown.idleUsage,
            loadAverage1m: loads.load1m,
            loadAverage5m: loads.load5m,
            loadAverage15m: loads.load15m,
            chipModelName: Self.cachedChipModel,
            performanceCoreCount: Self.cachedCoreCounts.p,
            efficiencyCoreCount: Self.cachedCoreCounts.e,
            thermalStateLabel: thermal,
            memoryAppGB: mem.appGB,
            memoryWiredGB: mem.wiredGB,
            memoryCompressedGB: mem.compressedGB,
            memorySwapUsedMB: mem.swapUsedMB,
            memoryPressureLevel: mem.pressureLevel,
            networkInterfaceName: net.interfaceName,
            localIPAddress: net.localIP,
            networkTotalReceivedGB: net.totalReceivedGB,
            networkTotalSentGB: net.totalSentGB,
            diskReadBytesPerSec: diskIO.readBytesPerSec,
            diskWriteBytesPerSec: diskIO.writeBytesPerSec,
            batteryHealthPercent: battery.healthPercent,
            batteryCycleCount: battery.cycleCount,
            batteryTemperatureCelsius: battery.temperatureCelsius
        )

        let now = Date()
        appendHistory(&cpuHistory, point: VitalsHistoryPoint(timestamp: now, value: cpuBreakdown.totalUsage))
        appendHistory(&gpuHistory, point: VitalsHistoryPoint(timestamp: now, value: gpu))
        appendHistory(&ramHistory, point: VitalsHistoryPoint(timestamp: now, value: mem.usage))
        appendHistory(&powerHistory, point: VitalsHistoryPoint(timestamp: now, value: Double(battery.level) / 100.0))
        let netRatio = min((net.down + net.up) / 10_485_760.0, 1.0)
        let downRatio = min(net.down / 10_485_760.0, 1.0)
        let upRatio = min(net.up / 10_485_760.0, 1.0)
        appendHistory(&networkHistory, point: VitalsHistoryPoint(timestamp: now, value: netRatio))
        appendHistory(&networkDownHistory, point: VitalsHistoryPoint(timestamp: now, value: downRatio))
        appendHistory(&networkUpHistory, point: VitalsHistoryPoint(timestamp: now, value: upRatio))
        let diskRatio = disk.totalGB > 0 ? (disk.totalGB - disk.freeGB) / disk.totalGB : 0.5
        appendHistory(&diskHistory, point: VitalsHistoryPoint(timestamp: now, value: diskRatio))
    }

    public func refreshMetricsAsync(includeProcesses: Bool = false) async {
        refreshMetrics(includeProcesses: includeProcesses)
    }

    public func killProcess(pid: Int32) {
        if let app = NSRunningApplication(processIdentifier: pid) {
            app.forceTerminate()
        } else {
            kill(pid, SIGTERM)
        }

        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.refreshMetrics(includeProcesses: true)
        }
    }

    // MARK: - Mach Kernel & System APIs (100% Native C/Darwin, zero overhead)

    public func readLoadAverages() -> (load1m: Double, load5m: Double, load15m: Double) {
        var loads = [Double](repeating: 0.0, count: 3)
        let count = getloadavg(&loads, 3)
        guard count == 3 else { return (1.0, 1.0, 1.0) }
        return (max(loads[0], 0.0), max(loads[1], 0.0), max(loads[2], 0.0))
    }

    public func readThermalStateLabel() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Nominal"
        }
    }

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

    public func readDiskIOThroughput() -> (readBytesPerSec: Double, writeBytesPerSec: Double) {
        var iterator: io_iterator_t = 0
        let matchDict = IOServiceMatching("IOBlockStorageDriver")
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matchDict, &iterator)
        guard result == kIOReturnSuccess, iterator != 0 else { return (0.0, 0.0) }
        defer { IOObjectRelease(iterator) }

        var totalRead: UInt64 = 0
        var totalWrite: UInt64 = 0
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == kIOReturnSuccess,
               let dict = props?.takeRetainedValue() as? [String: Any],
               let stats = dict["Statistics"] as? [String: Any] {
                if let r = stats["Bytes (Read)"] as? NSNumber {
                    totalRead += r.uint64Value
                }
                if let w = stats["Bytes (Write)"] as? NSNumber {
                    totalWrite += w.uint64Value
                }
            }
        }

        let now = Date()
        var readSpeed: Double = 0.0
        var writeSpeed: Double = 0.0

        if let prevRead = buffer.previousDiskReadBytes,
           let prevWrite = buffer.previousDiskWriteBytes,
           let prevTime = buffer.previousDiskTimestamp {
            let elapsed = now.timeIntervalSince(prevTime)
            if elapsed > 0.05 {
                let deltaRead = totalRead >= prevRead ? Double(totalRead - prevRead) : 0.0
                let deltaWrite = totalWrite >= prevWrite ? Double(totalWrite - prevWrite) : 0.0
                readSpeed = deltaRead / elapsed
                writeSpeed = deltaWrite / elapsed
            }
        }

        buffer.previousDiskReadBytes = totalRead
        buffer.previousDiskWriteBytes = totalWrite
        buffer.previousDiskTimestamp = now

        return (max(readSpeed, 0.0), max(writeSpeed, 0.0))
    }

    public func readBatteryInfo() -> (level: Int, isCharging: Bool, source: String, healthPercent: Int, cycleCount: Int, temperatureCelsius: Double) {
        var level = 100
        var isCharging = false
        var sourceName = "AC Power"

        if let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] {
            for source in sources {
                if let desc = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] {
                    level = desc[kIOPSCurrentCapacityKey] as? Int ?? 100
                    isCharging = desc[kIOPSIsChargingKey] as? Bool ?? false
                    let source = desc[kIOPSPowerSourceStateKey] as? String ?? "AC Power"
                    sourceName = (source == kIOPSACPowerValue) ? "AC Power" : "Battery"
                    break
                }
            }
        }

        var cycleCount = 0
        var temperatureCelsius = 31.0
        var healthPercent = 100

        var iterator: io_iterator_t = 0
        let matchDict = IOServiceMatching("AppleSmartBattery")
        let res = IOServiceGetMatchingServices(kIOMainPortDefault, matchDict, &iterator)
        if res == kIOReturnSuccess, iterator != 0 {
            defer { IOObjectRelease(iterator) }
            var service = IOIteratorNext(iterator)
            while service != 0 {
                defer {
                    IOObjectRelease(service)
                    service = IOIteratorNext(iterator)
                }
                var props: Unmanaged<CFMutableDictionary>?
                if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == kIOReturnSuccess,
                   let dict = props?.takeRetainedValue() as? [String: Any] {
                    if let cycles = dict["CycleCount"] as? Int {
                        cycleCount = cycles
                    } else if let cycles = dict["CycleCount"] as? NSNumber {
                        cycleCount = cycles.intValue
                    }
                    if let rawTemp = dict["Temperature"] as? Double {
                        temperatureCelsius = rawTemp / 100.0
                    } else if let rawTemp = dict["Temperature"] as? NSNumber {
                        temperatureCelsius = rawTemp.doubleValue / 100.0
                    }
                    let maxCap = (dict["MaxCapacity"] as? NSNumber)?.doubleValue
                        ?? (dict["NominalChargeCapacity"] as? NSNumber)?.doubleValue
                    let designCap = (dict["DesignCapacity"] as? NSNumber)?.doubleValue
                    if let capVal = maxCap, let designVal = designCap, designVal > 0 {
                        let calc = Int((capVal / designVal) * 100.0)
                        healthPercent = Swift.min(Swift.max(calc, 50), 100)
                    }
                }
            }
        }

        return (level, isCharging, sourceName, healthPercent, cycleCount, temperatureCelsius)
    }

    public func readMemoryBreakdown() -> (
        usage: Double,
        usedGB: Double,
        totalGB: Double,
        appGB: Double,
        wiredGB: Double,
        compressedGB: Double,
        swapUsedMB: Double,
        pressureLevel: String
    ) {
        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(self.hostPort, HOST_VM_INFO64, $0, &count)
            }
        }

        let totalMem = Double(ProcessInfo.processInfo.physicalMemory)
        let totalGB = totalMem / 1_073_741_824.0

        guard result == KERN_SUCCESS else {
            return (0.45, totalGB * 0.45, totalGB, 4.0, 2.0, 1.0, 0.0, "Normal")
        }

        let pageSize = Double(getpagesize())
        let active = Double(vmStats.active_count) * pageSize
        let wired = Double(vmStats.wire_count) * pageSize
        let compressed = Double(vmStats.compressor_page_count) * pageSize
        let used = active + wired + compressed
        let usedGB = used / 1_073_741_824.0
        let usage = min(max(used / totalMem, 0.0), 1.0)

        let wiredGB = (Double(vmStats.wire_count) * pageSize) / 1_073_741_824.0
        let compressedGB = (Double(vmStats.compressor_page_count) * pageSize) / 1_073_741_824.0
        let internalMinusPurgeable = (Double(max(Int64(vmStats.internal_page_count) - Int64(vmStats.purgeable_count), 0)) * pageSize) / 1_073_741_824.0
        let activeGB = (Double(vmStats.active_count) * pageSize) / 1_073_741_824.0
        let appGB = max(internalMinusPurgeable, activeGB)

        var swapUsage = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        var swapUsedMB: Double = 0.0
        if sysctlbyname("vm.swapusage", &swapUsage, &swapSize, nil, 0) == 0 {
            swapUsedMB = Double(swapUsage.xsu_used) / 1_048_576.0
        }

        let pressureLevel: String = {
            if usage >= 0.85 { return "Critical" }
            if usage >= 0.70 { return "Warning" }
            return "Normal"
        }()

        return (usage, usedGB, totalGB, appGB, wiredGB, compressedGB, swapUsedMB, pressureLevel)
    }

    public func readCPUBreakdown() -> (totalUsage: Double, userUsage: Double, sysUsage: Double, idleUsage: Double) {
        var numProcessors: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var numCpuInfo: mach_msg_type_number_t = 0

        let result = host_processor_info(
            self.hostPort,
            PROCESSOR_CPU_LOAD_INFO,
            &numProcessors,
            &cpuInfo,
            &numCpuInfo
        )

        guard result == KERN_SUCCESS, let cpuInfo = cpuInfo else {
            return (0.15, 0.10, 0.05, 0.85)
        }

        var totalUsage: Double = 0.15
        var userUsage: Double = 0.10
        var sysUsage: Double = 0.05
        var idleUsage: Double = 0.85

        if let prev = buffer.previousCpuInfo, buffer.previousCpuInfoCount == numCpuInfo {
            var userTicks: Int64 = 0
            var sysTicks: Int64 = 0
            var idleTicks: Int64 = 0
            var totalTicks: Int64 = 0

            for i in 0..<Int(numProcessors) {
                let userIdx = Int(CPU_STATE_MAX) * i + Int(CPU_STATE_USER)
                let sysIdx = Int(CPU_STATE_MAX) * i + Int(CPU_STATE_SYSTEM)
                let niceIdx = Int(CPU_STATE_MAX) * i + Int(CPU_STATE_NICE)
                let idleIdx = Int(CPU_STATE_MAX) * i + Int(CPU_STATE_IDLE)

                let u = max(Int64(cpuInfo[userIdx]) - Int64(prev[userIdx]), 0)
                let s = max(Int64(cpuInfo[sysIdx]) - Int64(prev[sysIdx]), 0)
                let n = max(Int64(cpuInfo[niceIdx]) - Int64(prev[niceIdx]), 0)
                let id = max(Int64(cpuInfo[idleIdx]) - Int64(prev[idleIdx]), 0)

                userTicks += (u + n)
                sysTicks += s
                idleTicks += id
                totalTicks += (u + s + n + id)
            }

            if totalTicks > 0 {
                let totalD = Double(totalTicks)
                totalUsage = Double(userTicks + sysTicks) / totalD
                userUsage = Double(userTicks) / totalD
                sysUsage = Double(sysTicks) / totalD
                idleUsage = Double(idleTicks) / totalD
            }
        }

        if let prev = buffer.previousCpuInfo {
            let byteSize = vm_size_t(buffer.previousCpuInfoCount * mach_msg_type_number_t(MemoryLayout<integer_t>.stride))
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: prev), byteSize)
        }

        buffer.previousCpuInfo = cpuInfo
        buffer.previousCpuInfoCount = numCpuInfo

        return (
            min(max(totalUsage, 0.0), 1.0),
            min(max(userUsage, 0.0), 1.0),
            min(max(sysUsage, 0.0), 1.0),
            min(max(idleUsage, 0.0), 1.0)
        )
    }

    deinit {
        monitorTask?.cancel()
        mach_port_deallocate(mach_task_self_, hostPort)
    }

    // MARK: - Native Darwin proc_pidinfo & NSWorkspace collection
    private func readTopProcessesNative() -> [ProcessInfoItem] {
        let apps = NSWorkspace.shared.runningApplications
        var items: [ProcessInfoItem] = []
        let totalMemBytes = Double(ProcessInfo.processInfo.physicalMemory)

        let now = Date()
        let previousCPUTimes = buffer.previousProcessCPUTimeNs
        let previousTimestamp = buffer.previousProcessSampleTimestamp
        // First sample after launch has no baseline: report 0% rather than a
        // bogus number, and use the *current* sample as the next baseline.
        let interval = previousTimestamp.map { now.timeIntervalSince($0) } ?? 0
        let hasBaseline = previousTimestamp != nil && interval > 0.05
        var sampledCPUTimes: [Int32: UInt64] = [:]

        for app in apps {
            let pid = app.processIdentifier
            guard pid > 0, let name = app.localizedName, !name.isEmpty else { continue }

            var taskInfo = proc_taskinfo()
            let size = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, Int32(MemoryLayout<proc_taskinfo>.size))
            if size == MemoryLayout<proc_taskinfo>.size {
                let memBytes = Double(taskInfo.pti_resident_size)
                let memPercent = min(max((memBytes / totalMemBytes) * 100.0, 0.0), 100.0)
                let totalCPUTimeNs = taskInfo.pti_total_user + taskInfo.pti_total_system
                sampledCPUTimes[pid] = totalCPUTimeNs

                var cpuPercent = 0.0
                if hasBaseline, let previous = previousCPUTimes[pid], totalCPUTimeNs >= previous {
                    let usedSeconds = Double(totalCPUTimeNs - previous) / 1_000_000_000.0
                    cpuPercent = min(max((usedSeconds / interval) * 100.0, 0.0), 100.0)
                }
                let memoryMB = memBytes / 1_048_576.0

                items.append(ProcessInfoItem(
                    id: pid,
                    name: name,
                    cpuPercent: cpuPercent,
                    memoryPercent: memPercent,
                    memoryMB: memoryMB
                ))
            }
        }

        // Keep only live PIDs so the dictionary cannot grow with every process
        // the machine has ever launched.
        buffer.previousProcessCPUTimeNs = sampledCPUTimes
        buffer.previousProcessSampleTimestamp = now

        items.sort { $0.memoryPercent > $1.memoryPercent }
        return items
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

    public func readNetworkThroughputDetailed() -> (
        down: Double,
        up: Double,
        totalReceivedGB: Double,
        totalSentGB: Double,
        interfaceName: String,
        localIP: String
    ) {
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else {
            return (0.0, 0.0, 0.0, 0.0, "en0", "—")
        }
        defer { freeifaddrs(ifap) }

        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0
        var primaryInterface = "en0"
        var primaryIP = "—"
        var foundPrimary = false

        var ptr: UnsafeMutablePointer<ifaddrs>? = first

        while let cur = ptr {
            let flags = cur.pointee.ifa_flags
            let isUp = (flags & UInt32(IFF_UP)) != 0
            let isLoopback = (flags & UInt32(IFF_LOOPBACK)) != 0
            let name = String(cString: cur.pointee.ifa_name)

            if isUp && !isLoopback {
                if let addr = cur.pointee.ifa_addr {
                    if addr.pointee.sa_family == UInt8(AF_LINK), let data = cur.pointee.ifa_data {
                        let ifData = data.assumingMemoryBound(to: if_data.self).pointee
                        totalIn += UInt64(ifData.ifi_ibytes)
                        totalOut += UInt64(ifData.ifi_obytes)
                    } else if addr.pointee.sa_family == UInt8(AF_INET) {
                        var addrBuf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                        let sin = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
                        var inAddr = sin.sin_addr
                        if inet_ntop(AF_INET, &inAddr, &addrBuf, socklen_t(INET_ADDRSTRLEN)) != nil {
                            let ipStr = addrBuf.withUnsafeBufferPointer { ptr -> String in
                                guard let base = ptr.baseAddress else { return "—" }
                                return String(validatingCString: base) ?? "—"
                            }
                            if !ipStr.hasPrefix("127.") && !foundPrimary {
                                primaryInterface = name
                                primaryIP = ipStr
                                if name == "en0" {
                                    foundPrimary = true
                                }
                            }
                        }
                    }
                }
            }
            ptr = cur.pointee.ifa_next
        }

        let totalReceivedGB = Double(totalIn) / 1_073_741_824.0
        let totalSentGB = Double(totalOut) / 1_073_741_824.0

        let now = Date()
        var downSpeed: Double = 0.0
        var upSpeed: Double = 0.0

        if let prevIn = buffer.previousNetworkInBytes,
           let prevOut = buffer.previousNetworkOutBytes,
           let prevTime = buffer.previousNetworkTimestamp {
            let elapsed = now.timeIntervalSince(prevTime)
            if elapsed > 0.05 {
                let deltaIn = totalIn >= prevIn ? Double(totalIn - prevIn) : 0.0
                let deltaOut = totalOut >= prevOut ? Double(totalOut - prevOut) : 0.0
                downSpeed = deltaIn / elapsed
                upSpeed = deltaOut / elapsed
            }
        }

        buffer.previousNetworkInBytes = totalIn
        buffer.previousNetworkOutBytes = totalOut
        buffer.previousNetworkTimestamp = now

        return (
            max(downSpeed, 0.0),
            max(upSpeed, 0.0),
            totalReceivedGB,
            totalSentGB,
            primaryInterface,
            primaryIP
        )
    }

}
