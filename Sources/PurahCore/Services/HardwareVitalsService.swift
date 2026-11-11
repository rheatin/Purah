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
    public var networkDownBytesPerSecond: Double
    public var networkUpBytesPerSecond: Double
    public var diskReadBytesPerSecond: Double
    public var diskWriteBytesPerSecond: Double
    public var energyWatts: Double

    public init(
        id: Int32,
        name: String,
        cpuPercent: Double,
        memoryPercent: Double,
        memoryMB: Double = 0.0,
        networkDownBytesPerSecond: Double = 0.0,
        networkUpBytesPerSecond: Double = 0.0,
        diskReadBytesPerSecond: Double = 0.0,
        diskWriteBytesPerSecond: Double = 0.0,
        energyWatts: Double = 0.0
    ) {
        self.id = id
        self.name = name
        self.cpuPercent = cpuPercent
        self.memoryPercent = memoryPercent
        self.memoryMB = memoryMB
        self.networkDownBytesPerSecond = networkDownBytesPerSecond
        self.networkUpBytesPerSecond = networkUpBytesPerSecond
        self.diskReadBytesPerSecond = diskReadBytesPerSecond
        self.diskWriteBytesPerSecond = diskWriteBytesPerSecond
        self.energyWatts = energyWatts
    }
}

struct ProcessResourceCounters: Sendable, Equatable {
    let diskReadBytes: UInt64
    let diskWriteBytes: UInt64
    let energyNanojoules: UInt64

    func rates(since previous: ProcessResourceCounters?, elapsed: TimeInterval) -> ProcessResourceRates {
        guard let previous, elapsed > 0 else { return .zero }

        let readDelta = diskReadBytes >= previous.diskReadBytes
            ? diskReadBytes - previous.diskReadBytes
            : 0
        let writeDelta = diskWriteBytes >= previous.diskWriteBytes
            ? diskWriteBytes - previous.diskWriteBytes
            : 0
        let energyDelta = energyNanojoules >= previous.energyNanojoules
            ? energyNanojoules - previous.energyNanojoules
            : 0

        return ProcessResourceRates(
            diskReadBytesPerSecond: Double(readDelta) / elapsed,
            diskWriteBytesPerSecond: Double(writeDelta) / elapsed,
            energyWatts: Double(energyDelta) / elapsed / 1_000_000_000.0
        )
    }
}

struct ProcessResourceRates: Sendable, Equatable {
    let diskReadBytesPerSecond: Double
    let diskWriteBytesPerSecond: Double
    let energyWatts: Double

    static let zero = ProcessResourceRates(
        diskReadBytesPerSecond: 0,
        diskWriteBytesPerSecond: 0,
        energyWatts: 0
    )
}

/// Immutable process-sampling state. The expensive process walk runs off the
/// main actor, so it carries this snapshot in and returns a new one instead of
/// reading or mutating the service's observable state off-main.
private struct ProcessSamplingSnapshot: Sendable {
    let previousCPUTicks: [Int32: UInt64]
    let previousResources: [Int32: ProcessResourceCounters]
    let previousTimestamp: Date?
}

private struct ProcessNameCacheEntry: Sendable, Equatable {
    let executablePath: String
    let name: String
}

private struct ProcessSamplingInput: Sendable {
    let snapshot: ProcessSamplingSnapshot
    let nameCache: [Int32: ProcessNameCacheEntry]
    let bundleCache: [String: ProcessAppBundleInfo]
    let friendlyNames: [Int32: String]
    let networkSpeeds: [Int32: ProcessNetworkSpeed]
}

private struct ProcessSamplingOutput: Sendable {
    let items: [ProcessInfoItem]
    let cpuTicks: [Int32: UInt64]
    let resources: [Int32: ProcessResourceCounters]
    let timestamp: Date
    let nameCache: [Int32: ProcessNameCacheEntry]
    let bundleCache: [String: ProcessAppBundleInfo]
}

/// The process walk is intentionally outside the main-actor service. It reads
/// kernel state and immutable snapshots only, and returns a value for the main
/// actor to publish.
private enum ProcessSamplingWorker {
    static func sample(_ input: ProcessSamplingInput) -> ProcessSamplingOutput {
        let pids = allProcessIdentifiers()
        let processTable = processExecutableTable(for: pids)
        let appBundles = updateAppBundleCache(input.bundleCache, processTable: processTable)

        let now = Date()
        let previousCPUTimes = input.snapshot.previousCPUTicks
        let previousResources = input.snapshot.previousResources
        let previousTimestamp = input.snapshot.previousTimestamp
        // The first sample has no baseline: report 0% rather than a bogus
        // number, and use the current sample as the next baseline.
        let interval = previousTimestamp.map { now.timeIntervalSince($0) } ?? 0
        let hasBaseline = previousTimestamp != nil && interval > 0.05
        let totalMemBytes = Double(ProcessInfo.processInfo.physicalMemory)
        let coreCount = ProcessInfo.processInfo.activeProcessorCount

        var items: [ProcessInfoItem] = []
        items.reserveCapacity(pids.count)
        var sampledCPUTimes: [Int32: UInt64] = [:]
        var sampledResources: [Int32: ProcessResourceCounters] = [:]
        var names: [Int32: ProcessNameCacheEntry] = [:]
        names.reserveCapacity(pids.count)

        for pid in pids {
            let executablePath = processTable[pid]?.executablePath
            let name: String
            if let cached = input.nameCache[pid],
               cached.executablePath == (executablePath ?? "") {
                name = cached.name
            } else {
                let fallbackName = input.friendlyNames[pid] ?? processNameFromKernel(pid: pid)
                name = ProcessDisplayNameResolver.resolve(
                    pid: pid,
                    executablePath: executablePath,
                    fallbackName: fallbackName,
                    processTable: processTable,
                    appBundles: appBundles
                )
            }
            names[pid] = ProcessNameCacheEntry(
                executablePath: executablePath ?? "",
                name: name
            )

            var taskInfo = proc_taskinfo()
            let size = proc_pidinfo(
                pid,
                PROC_PIDTASKINFO,
                0,
                &taskInfo,
                Int32(MemoryLayout<proc_taskinfo>.size)
            )
            if size == MemoryLayout<proc_taskinfo>.size {
                let totalCPUTicks = taskInfo.pti_total_user + taskInfo.pti_total_system
                sampledCPUTimes[pid] = totalCPUTicks

                let cpuPercent = previousCPUTimes[pid].map {
                    ProcessCPUPercent.calculate(
                        previous: $0,
                        current: totalCPUTicks,
                        elapsed: interval,
                        coreCount: coreCount,
                        tickConversion: ProcessCPUPercent.machTickConversion
                    )
                } ?? 0
                let network = input.networkSpeeds[pid]
                var resources = ProcessResourceRates.zero

                var usage = rusage_info_v6()
                let usageResult = withUnsafeMutablePointer(to: &usage) { pointer in
                    pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                        proc_pid_rusage(pid, RUSAGE_INFO_V6, $0)
                    }
                }
                // Activity Monitor's Memory column is `phys_footprint`, not
                // RSS. Reporting resident size made Purah claim 156 MB while
                // the system said 46 MB for the same process.
                let memoryBytes = usageResult == 0
                    ? Double(usage.ri_phys_footprint)
                    : Double(taskInfo.pti_resident_size)
                let memPercent = min(max((memoryBytes / totalMemBytes) * 100.0, 0.0), 100.0)
                let memoryMB = memoryBytes / 1_048_576.0
                if usageResult == 0 {
                    let counters = ProcessResourceCounters(
                        diskReadBytes: usage.ri_diskio_bytesread,
                        diskWriteBytes: usage.ri_diskio_byteswritten,
                        energyNanojoules: usage.ri_energy_nj
                    )
                    if hasBaseline {
                        resources = counters.rates(
                            since: previousResources[pid],
                            elapsed: interval
                        )
                    }
                    sampledResources[pid] = counters
                }

                items.append(ProcessInfoItem(
                    id: pid,
                    name: name,
                    cpuPercent: cpuPercent,
                    memoryPercent: memPercent,
                    memoryMB: memoryMB,
                    networkDownBytesPerSecond: network?.downBytesPerSecond ?? 0,
                    networkUpBytesPerSecond: network?.upBytesPerSecond ?? 0,
                    diskReadBytesPerSecond: resources.diskReadBytesPerSecond,
                    diskWriteBytesPerSecond: resources.diskWriteBytesPerSecond,
                    energyWatts: resources.energyWatts
                ))
            }
        }

        items.sort { $0.memoryPercent > $1.memoryPercent }
        return ProcessSamplingOutput(
            items: items,
            cpuTicks: sampledCPUTimes,
            resources: sampledResources,
            timestamp: now,
            nameCache: names,
            bundleCache: appBundles
        )
    }

    private static func allProcessIdentifiers() -> [Int32] {
        let stride = MemoryLayout<pid_t>.stride
        let estimatedBytes = Int(proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0))
        var capacity = max(estimatedBytes, stride * 128)

        for _ in 0..<16 {
            var pids = [pid_t](repeating: 0, count: capacity / stride)
            let usedBytes = pids.withUnsafeMutableBytes { buffer in
                proc_listpids(
                    UInt32(PROC_ALL_PIDS),
                    0,
                    buffer.baseAddress,
                    Int32(buffer.count)
                )
            }
            guard usedBytes > 0 else { return [] }

            let usedCount = min(Int(usedBytes) / stride, pids.count)
            if Int(usedBytes) < capacity || usedCount < pids.count {
                return pids.prefix(usedCount).filter { $0 > 0 }
            }
            capacity *= 2
        }

        return []
    }

    private static func processExecutableTable(
        for pids: [Int32]
    ) -> [Int32: ProcessExecutableRecord] {
        var table: [Int32: ProcessExecutableRecord] = [:]
        table.reserveCapacity(pids.count)

        for pid in pids {
            var info = proc_bsdinfo()
            let size = proc_pidinfo(
                pid,
                PROC_PIDTBSDINFO,
                0,
                &info,
                Int32(MemoryLayout<proc_bsdinfo>.size)
            )
            let parentPID = size > 0 ? Int32(clamping: info.pbi_ppid) : 0
            table[pid] = ProcessExecutableRecord(
                parentPID: parentPID,
                executablePath: processExecutablePath(pid: pid)
            )
        }
        return table
    }

    private static func processExecutablePath(pid: Int32) -> String? {
        var pathBuffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let pathLength = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
        guard pathLength > 0 else { return nil }
        return cString(from: pathBuffer)
    }

    private static func processNameFromKernel(pid: Int32) -> String? {
        var nameBuffer = [CChar](repeating: 0, count: 256)
        let nameLength = proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
        guard nameLength > 0 else { return nil }
        return cString(from: nameBuffer)
    }

    private static func updateAppBundleCache(
        _ cache: [String: ProcessAppBundleInfo],
        processTable: [Int32: ProcessExecutableRecord]
    ) -> [String: ProcessAppBundleInfo] {
        var infos = cache
        for record in processTable.values {
            guard let path = record.executablePath,
                  let bundlePath = ProcessDisplayNameResolver.appBundlePath(in: path),
                  infos[bundlePath] == nil else {
                continue
            }
            infos[bundlePath] = appBundleInfo(at: bundlePath)
        }
        return infos
    }

    private static func appBundleInfo(at bundlePath: String) -> ProcessAppBundleInfo {
        let bundle = Bundle(url: URL(fileURLWithPath: bundlePath))
        let configuredName = ["CFBundleDisplayName", "CFBundleName"]
            .compactMap { bundle?.object(forInfoDictionaryKey: $0) as? String }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        let displayName = configuredName
            ?? ProcessDisplayNameResolver.lastPathComponent(
                of: (bundlePath as NSString).deletingPathExtension
            )
            ?? bundlePath
        let executableName = (bundle?.object(forInfoDictionaryKey: "CFBundleExecutable") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ProcessAppBundleInfo(
            displayName: displayName,
            executableName: executableName?.isEmpty == true ? nil : executableName
        )
    }

    private static func cString(from buffer: [CChar]) -> String? {
        buffer.withUnsafeBufferPointer { pointer in
            guard let baseAddress = pointer.baseAddress else { return nil }
            return String(validatingCString: baseAddress)
        }
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
    public var cpuCoreUsages: [Double]
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
    public var memorySwapTotalMB: Double
    public var memoryActiveGB: Double
    public var memoryCachedGB: Double
    public var memoryFreeGB: Double
    public var memoryPressureLevel: String

    // Network
    public var networkInterfaceName: String
    public var localIPAddress: String
    public var networkTotalReceivedGB: Double
    public var networkTotalSentGB: Double

    // Disk I/O
    public var diskReadBytesPerSec: Double
    public var diskWriteBytesPerSec: Double
    public var diskReadTotalGB: Double
    public var diskWriteTotalGB: Double
    public var gpuRendererUsage: Double
    public var gpuTilerUsage: Double
    public var gpuMemoryInUseMB: Double
    public var gpuCoreCount: Int

    // Battery & Thermal
    public var batteryHealthPercent: Int
    public var batteryCycleCount: Int
    public var batteryTemperatureCelsius: Double
    public var batteryIsPresent: Bool
    public var batteryVoltageVolts: Double
    public var batteryChargeWatts: Double
    public var batteryTimeRemainingMinutes: Int?
    public var batteryCondition: String
    public var powerSystemWatts: Double
    public var powerSystemVolts: Double
    public var powerSystemAmps: Double
    public var powerAdapterWatts: Double
    public var batteryMaxCapacityMAh: Double
    public var batteryDesignCapacityMAh: Double

    // Thermal & cooling (best effort; `nil` when the hardware hides it).
    public var cpuTemperatureCelsius: Double?
    public var gpuTemperatureCelsius: Double?
    public var fanRPM: Int?

    // Wi-Fi link and reachability.
    public var wifiSSID: String
    public var wifiRSSI: Int
    public var wifiTransmitRateMbps: Double
    public var wifiLatencyMs: Double?
    public var wifiPacketLossPercent: Double?

    public var systemUptimeSeconds: Double

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
        cpuCoreUsages: [Double] = [],
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
        memorySwapTotalMB: Double = 0.0,
        memoryActiveGB: Double = 0.0,
        memoryCachedGB: Double = 0.0,
        memoryFreeGB: Double = 0.0,
        memoryPressureLevel: String = "Normal",
        networkInterfaceName: String = "en0",
        localIPAddress: String = "—",
        networkTotalReceivedGB: Double = 0.0,
        networkTotalSentGB: Double = 0.0,
        diskReadBytesPerSec: Double = 0.0,
        diskWriteBytesPerSec: Double = 0.0,
        diskReadTotalGB: Double = 0.0,
        diskWriteTotalGB: Double = 0.0,
        gpuRendererUsage: Double = 0.0,
        gpuTilerUsage: Double = 0.0,
        gpuMemoryInUseMB: Double = 0.0,
        gpuCoreCount: Int = 0,
        batteryHealthPercent: Int = 100,
        batteryCycleCount: Int = 0,
        batteryTemperatureCelsius: Double = 31.0,
        batteryIsPresent: Bool = false,
        batteryVoltageVolts: Double = 0.0,
        batteryChargeWatts: Double = 0.0,
        batteryTimeRemainingMinutes: Int? = nil,
        batteryCondition: String = "Normal",
        powerSystemWatts: Double = 0.0,
        powerSystemVolts: Double = 0.0,
        powerSystemAmps: Double = 0.0,
        powerAdapterWatts: Double = 0.0,
        batteryMaxCapacityMAh: Double = 0.0,
        batteryDesignCapacityMAh: Double = 0.0,
        cpuTemperatureCelsius: Double? = nil,
        gpuTemperatureCelsius: Double? = nil,
        fanRPM: Int? = nil,
        wifiSSID: String = "",
        wifiRSSI: Int = 0,
        wifiTransmitRateMbps: Double = 0.0,
        wifiLatencyMs: Double? = nil,
        wifiPacketLossPercent: Double? = nil,
        systemUptimeSeconds: Double = 0.0
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
        self.cpuCoreUsages = cpuCoreUsages
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
        self.memorySwapTotalMB = memorySwapTotalMB
        self.memoryActiveGB = memoryActiveGB
        self.memoryCachedGB = memoryCachedGB
        self.memoryFreeGB = memoryFreeGB
        self.memoryPressureLevel = memoryPressureLevel
        self.networkInterfaceName = networkInterfaceName
        self.localIPAddress = localIPAddress
        self.networkTotalReceivedGB = networkTotalReceivedGB
        self.networkTotalSentGB = networkTotalSentGB
        self.diskReadBytesPerSec = diskReadBytesPerSec
        self.diskWriteBytesPerSec = diskWriteBytesPerSec
        self.diskReadTotalGB = diskReadTotalGB
        self.diskWriteTotalGB = diskWriteTotalGB
        self.gpuRendererUsage = gpuRendererUsage
        self.gpuTilerUsage = gpuTilerUsage
        self.gpuMemoryInUseMB = gpuMemoryInUseMB
        self.gpuCoreCount = gpuCoreCount
        self.batteryHealthPercent = batteryHealthPercent
        self.batteryCycleCount = batteryCycleCount
        self.batteryTemperatureCelsius = batteryTemperatureCelsius
        self.batteryIsPresent = batteryIsPresent
        self.batteryVoltageVolts = batteryVoltageVolts
        self.batteryChargeWatts = batteryChargeWatts
        self.batteryTimeRemainingMinutes = batteryTimeRemainingMinutes
        self.batteryCondition = batteryCondition
        self.powerSystemWatts = powerSystemWatts
        self.powerSystemVolts = powerSystemVolts
        self.powerSystemAmps = powerSystemAmps
        self.powerAdapterWatts = powerAdapterWatts
        self.batteryMaxCapacityMAh = batteryMaxCapacityMAh
        self.batteryDesignCapacityMAh = batteryDesignCapacityMAh
        self.cpuTemperatureCelsius = cpuTemperatureCelsius
        self.gpuTemperatureCelsius = gpuTemperatureCelsius
        self.fanRPM = fanRPM
        self.wifiSSID = wifiSSID
        self.wifiRSSI = wifiRSSI
        self.wifiTransmitRateMbps = wifiTransmitRateMbps
        self.wifiLatencyMs = wifiLatencyMs
        self.wifiPacketLossPercent = wifiPacketLossPercent
        self.systemUptimeSeconds = systemUptimeSeconds
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
    /// monotonic mach-tick counter, so the delta is converted to nanoseconds
    /// before dividing by the wall-clock delta.
    var previousProcessCPUTicks: [Int32: UInt64] = [:]
    var previousProcessResources: [Int32: ProcessResourceCounters] = [:]
    var previousProcessSampleTimestamp: Date?
    /// A process keeps its name until its executable changes or its PID is
    /// reused; this turns the per-sample name walk into a path comparison.
    var processNames: [Int32: ProcessNameCacheEntry] = [:]
    /// Bundle display names are immutable for an app's lifetime, so read the
    /// Info.plist once per bundle rather than once per process sample.
    var appBundles: [String: ProcessAppBundleInfo] = [:]

    deinit {
        if let prev = previousCpuInfo {
            let byteSize = vm_size_t(previousCpuInfoCount * mach_msg_type_number_t(MemoryLayout<integer_t>.stride))
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: prev), byteSize)
        }
    }
}

/// `if_data` exposes 32-bit interface counters, so a busy interface can wrap
/// between two one-second samples. This assumes at most one wrap per interval.
enum NetworkCounterDelta {
    static let counterWidth: UInt64 = 1 << 32

    static func bytes(previous: UInt64, current: UInt64) -> UInt64 {
        if current >= previous {
            return current - previous
        }
        let previous32 = previous % counterWidth
        let current32 = current % counterWidth
        return (counterWidth - previous32 + current32) % counterWidth
    }
}

@Observable
@MainActor
public final class HardwareVitalsService {
    public static let shared = HardwareVitalsService()

    public private(set) var metrics: HardwareVitalsInfo = .init()
    private var cpuBuffer = VitalsHistoryBuffer()
    private var gpuBuffer = VitalsHistoryBuffer()
    private var ramBuffer = VitalsHistoryBuffer()
    private var powerBuffer = VitalsHistoryBuffer()
    private var networkDownBuffer = VitalsHistoryBuffer()
    private var networkUpBuffer = VitalsHistoryBuffer()
    private var diskBuffer = VitalsHistoryBuffer()
    private var diskReadBuffer = VitalsHistoryBuffer()
    private var diskWriteBuffer = VitalsHistoryBuffer()
    private var batteryStateHistory = VitalsStateHistory()

    @ObservationIgnored private var batteryStateBucketStart: Date?
    @ObservationIgnored private var batteryStateValue = 0

    public var cpuHistory: [VitalsHistoryPoint] { cpuBuffer.tiers.fast }
    public var gpuHistory: [VitalsHistoryPoint] { gpuBuffer.tiers.fast }
    public var ramHistory: [VitalsHistoryPoint] { ramBuffer.tiers.fast }
    public var powerHistory: [VitalsHistoryPoint] { powerBuffer.tiers.fast }
    public var networkDownHistory: [VitalsHistoryPoint] { networkDownBuffer.tiers.fast }
    public var networkUpHistory: [VitalsHistoryPoint] { networkUpBuffer.tiers.fast }
    public var diskHistory: [VitalsHistoryPoint] { diskBuffer.tiers.fast }
    public var diskReadHistory: [VitalsHistoryPoint] { diskReadBuffer.tiers.fast }
    public var diskWriteHistory: [VitalsHistoryPoint] { diskWriteBuffer.tiers.fast }
    public var batteryStatePoints: [VitalsHistoryPoint] { batteryStateHistory.points }

    public var selectedTimeScope: VitalsTimeScope = .realTime30s
    public private(set) var samplingInterval: TimeInterval = 1.0
    public var isDrawerVisible: Bool = false {
        didSet {
            guard isDrawerVisible != oldValue else { return }
            if isDrawerVisible {
                wifiService.start()
                refreshMetrics(includeProcesses: false)
            } else {
                wifiService.stop()
            }
        }
    }

    /// The rail's power gauge still needs the battery level while the drawer
    /// is closed. Other rail metrics do not, so the expensive IOKit battery
    /// probe follows the drawer or this explicit rail use.
    @ObservationIgnored public static var isPowerMetricVisibleOnRail = false

    @ObservationIgnored private var monitorTask: Task<Void, Never>?
    @ObservationIgnored private let buffer = CpuTelemetryBuffer()
    @ObservationIgnored private let wifiService = VitalsWiFiService.shared
    @ObservationIgnored private var thermalCache:
        (date: Date, cpu: Double?, gpu: Double?, fanRPM: Int?)?
    @ObservationIgnored private let hostPort: mach_port_t = mach_host_self()
    @ObservationIgnored private var saveThrottleCounter = 0
    @ObservationIgnored private let processNetworkSampler: ProcessNetworkSampler
    @ObservationIgnored private var processNetworkTask: Task<Void, Never>?
    @ObservationIgnored private var processNetworkSpeeds: [Int32: ProcessNetworkSpeed] = [:]
    @ObservationIgnored private(set) var isProcessesTabVisible = false
    @ObservationIgnored private var processSamplingTask: Task<Void, Never>?
    @ObservationIgnored private var processSamplingGeneration = 0

    // Dedicated Permanent Storage: ~/Library/Application Support/Purah/Vitals/
    @ObservationIgnored public static let defaultStorageDirectory: URL = {
        // A test process mounts the pod, and unmounting saves history. Point
        // that at a throwaway directory so a test run can never overwrite the
        // person's real telemetry file.
        if NSClassFromString("XCTestCase") != nil {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "PurahTests/Vitals-\(UUID().uuidString)",
                    isDirectory: true
                )
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return appSupport.appendingPathComponent("Purah/Vitals", isDirectory: true)
    }()

    @ObservationIgnored public let storageDirectory: URL
    @ObservationIgnored private let diskIOProbe: (() -> (
        readBytesPerSec: Double,
        writeBytesPerSec: Double,
        readTotalGB: Double,
        writeTotalGB: Double
    ))?
    @ObservationIgnored private let batteryProbe: (() -> (
        level: Int,
        isCharging: Bool,
        source: String,
        healthPercent: Int,
        cycleCount: Int,
        temperatureCelsius: Double,
        isPresent: Bool,
        voltageVolts: Double,
        chargeWatts: Double,
        timeRemainingMinutes: Int?,
        condition: String,
        systemWatts: Double,
        systemVolts: Double,
        systemAmps: Double,
        adapterWatts: Double,
        maxCapacityMAh: Double,
        designCapacityMAh: Double
    ))?
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

    public init(
        storageDirectory: URL = defaultStorageDirectory,
        processNetworkSampler: ProcessNetworkSampler = ProcessNetworkSampler()
    ) {
        self.storageDirectory = storageDirectory
        self.processNetworkSampler = processNetworkSampler
        self.diskIOProbe = nil
        self.batteryProbe = nil
        loadHistoryFromDisk()
        // Collect initial baseline snapshot on startup without kicking off continuous kernel polling
        refreshMetrics(includeProcesses: false)
    }

    init(
        storageDirectory: URL,
        processNetworkSampler: ProcessNetworkSampler = ProcessNetworkSampler(),
        diskIOProbe: @escaping () -> (
            readBytesPerSec: Double,
            writeBytesPerSec: Double,
            readTotalGB: Double,
            writeTotalGB: Double
        ),
        batteryProbe: @escaping () -> (
            level: Int,
            isCharging: Bool,
            source: String,
            healthPercent: Int,
            cycleCount: Int,
            temperatureCelsius: Double,
            isPresent: Bool,
            voltageVolts: Double,
            chargeWatts: Double,
            timeRemainingMinutes: Int?,
            condition: String,
            systemWatts: Double,
            systemVolts: Double,
            systemAmps: Double,
            adapterWatts: Double,
            maxCapacityMAh: Double,
            designCapacityMAh: Double
        )
    ) {
        self.storageDirectory = storageDirectory
        self.processNetworkSampler = processNetworkSampler
        self.diskIOProbe = diskIOProbe
        self.batteryProbe = batteryProbe
        loadHistoryFromDisk()
        refreshMetrics(includeProcesses: false)
    }

    private func buffer(for metric: VitalsMetricType) -> VitalsHistoryBuffer {
        switch metric {
        case .cpu: return cpuBuffer
        case .gpu: return gpuBuffer
        case .ram: return ramBuffer
        case .power: return powerBuffer
        case .network: return networkDownBuffer
        case .disk: return diskBuffer
        }
    }

    private func applyFastCapacityToBuffers() {
        let capacity = VitalsHistoryBuffer.fastCapacity(forInterval: samplingInterval)
        cpuBuffer.setFastCapacity(capacity)
        gpuBuffer.setFastCapacity(capacity)
        ramBuffer.setFastCapacity(capacity)
        powerBuffer.setFastCapacity(capacity)
        networkDownBuffer.setFastCapacity(capacity)
        networkUpBuffer.setFastCapacity(capacity)
        diskBuffer.setFastCapacity(capacity)
        diskReadBuffer.setFastCapacity(capacity)
        diskWriteBuffer.setFastCapacity(capacity)
    }

    public func history(for metric: VitalsMetricType, scope: VitalsTimeScope? = nil) -> [VitalsHistoryPoint] {
        let activeScope = scope ?? selectedTimeScope
        let source = VitalsHistoryBuffer.source(
            tiers: buffer(for: metric).tiers,
            scope: activeScope,
            fastResolution: samplingInterval
        )
        let cutoff = Date().addingTimeInterval(-activeScope.durationSeconds)
        return source.points.filter { $0.timestamp >= cutoff }
    }

    public func networkUpHistory(scope: VitalsTimeScope? = nil) -> [VitalsHistoryPoint] {
        let activeScope = scope ?? selectedTimeScope
        let source = VitalsHistoryBuffer.source(
            tiers: networkUpBuffer.tiers,
            scope: activeScope,
            fastResolution: samplingInterval
        )
        let cutoff = Date().addingTimeInterval(-activeScope.durationSeconds)
        return source.points.filter { $0.timestamp >= cutoff }
    }

    public func diskReadHistory(scope: VitalsTimeScope? = nil) -> [VitalsHistoryPoint] {
        let activeScope = scope ?? selectedTimeScope
        let source = VitalsHistoryBuffer.source(
            tiers: diskReadBuffer.tiers,
            scope: activeScope,
            fastResolution: samplingInterval
        )
        let cutoff = Date().addingTimeInterval(-activeScope.durationSeconds)
        return source.points.filter { $0.timestamp >= cutoff }
    }

    public func diskWriteHistory(scope: VitalsTimeScope? = nil) -> [VitalsHistoryPoint] {
        let activeScope = scope ?? selectedTimeScope
        let source = VitalsHistoryBuffer.source(
            tiers: diskWriteBuffer.tiers,
            scope: activeScope,
            fastResolution: samplingInterval
        )
        let cutoff = Date().addingTimeInterval(-activeScope.durationSeconds)
        return source.points.filter { $0.timestamp >= cutoff }
    }

    // MARK: - Column API

    public func columns(
        for metric: VitalsMetricType,
        scope: VitalsTimeScope,
        maximumColumns: Int = 60
    ) -> [VitalsBucket] {
        VitalsHistoryBuffer.columns(
            tiers: buffer(for: metric).tiers,
            scope: scope,
            fastResolution: samplingInterval,
            maximumColumns: maximumColumns
        )
    }

    public func networkUpColumns(scope: VitalsTimeScope) -> [VitalsBucket] {
        VitalsHistoryBuffer.columns(
            tiers: networkUpBuffer.tiers,
            scope: scope,
            fastResolution: samplingInterval
        )
    }

    public func diskReadColumns(scope: VitalsTimeScope) -> [VitalsBucket] {
        VitalsHistoryBuffer.columns(
            tiers: diskReadBuffer.tiers,
            scope: scope,
            fastResolution: samplingInterval
        )
    }

    public func diskWriteColumns(scope: VitalsTimeScope) -> [VitalsBucket] {
        VitalsHistoryBuffer.columns(
            tiers: diskWriteBuffer.tiers,
            scope: scope,
            fastResolution: samplingInterval
        )
    }

    /// The real span the series can currently cover, used by the footers to
    /// say "12 h · available 1 h 20 m" while the tiers are still filling.
    public func availableSpan(for metric: VitalsMetricType, now: Date = Date()) -> TimeInterval {
        guard let oldest = buffer(for: metric).oldestTimestamp else { return 0 }
        return max(now.timeIntervalSince(oldest), 0)
    }

    public func batteryStateCells(range: TimeInterval, now: Date = Date()) -> [VitalsStateCell] {
        batteryStateHistory.cells(
            range: range,
            now: now,
            currentState: metrics.batteryIsPresent ? batteryStateValue : nil
        )
    }

    func recordBatteryState(_ state: Int, at now: Date) {
        let interval = VitalsStateHistory.interval
        let start = Date(
            timeIntervalSince1970: floor(now.timeIntervalSince1970 / interval) * interval
        )
        if let lastStart = batteryStateBucketStart {
            if start > lastStart {
                batteryStateHistory.appendCompleted(
                    start: lastStart,
                    state: batteryStateValue
                )
                batteryStateBucketStart = start
            }
        } else {
            batteryStateBucketStart = start
        }
        batteryStateValue = state
    }

    public func saveHistoryToDisk() {
        let pending = pendingBuckets()
        let container = VitalsPersistedHistory(
            cpu: cpuBuffer.tiers,
            gpu: gpuBuffer.tiers,
            ram: ramBuffer.tiers,
            power: powerBuffer.tiers,
            networkDown: networkDownBuffer.tiers,
            networkUp: networkUpBuffer.tiers,
            disk: diskBuffer.tiers,
            diskRead: diskReadBuffer.tiers,
            diskWrite: diskWriteBuffer.tiers,
            batteryState: batteryStateHistory,
            pendingMinute: pending.minute.isEmpty ? nil : pending.minute,
            pendingCoarse: pending.coarse.isEmpty ? nil : pending.coarse
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

    /// Every series' in-progress aggregation, keyed by its persisted name.
    private func pendingBuckets() -> (
        minute: [String: VitalsPendingBucket],
        coarse: [String: VitalsPendingBucket]
    ) {
        let series: [(String, VitalsHistoryBuffer)] = [
            ("cpu", cpuBuffer),
            ("gpu", gpuBuffer),
            ("ram", ramBuffer),
            ("power", powerBuffer),
            ("network", networkDownBuffer),
            ("networkUp", networkUpBuffer),
            ("disk", diskBuffer),
            ("diskRead", diskReadBuffer),
            ("diskWrite", diskWriteBuffer)
        ]
        var minute: [String: VitalsPendingBucket] = [:]
        var coarse: [String: VitalsPendingBucket] = [:]
        for (key, buffer) in series {
            minute[key] = buffer.pendingMinuteBucket
            coarse[key] = buffer.pendingCoarseBucket
        }
        return (minute.compactMapValues { $0 }, coarse.compactMapValues { $0 })
    }

    public func loadHistoryFromDisk() {
        guard FileManager.default.fileExists(atPath: historyFileURL.path) else { return }
        do {
            let data = try Data(contentsOf: historyFileURL)
            let container = try JSONDecoder().decode(VitalsPersistedHistory.self, from: data)
            let now = Date()
            let fastCap = VitalsHistoryBuffer.fastCapacity(forInterval: samplingInterval)

            func filtered(_ history: VitalsTieredHistory) -> VitalsTieredHistory {
                VitalsTieredHistory(
                    fast: Array(history.fast
                        .filter { now.timeIntervalSince($0.timestamp) <= 300 }
                        .suffix(fastCap)),
                    minute: Array(history.minute
                        .filter { now.timeIntervalSince($0.timestamp) <= 3600 }
                        .suffix(VitalsHistoryBuffer.minuteCapacity)),
                    coarse: Array(history.coarse
                        .filter { now.timeIntervalSince($0.timestamp) <= 43_200 }
                        .suffix(VitalsHistoryBuffer.coarseCapacity))
                )
            }

            func restored(_ history: VitalsTieredHistory, key: String) -> VitalsHistoryBuffer {
                let pendingMinute = container.pendingMinute?[key].flatMap {
                    now.timeIntervalSince($0.start) <= 3_600 ? $0 : nil
                }
                let pendingCoarse = container.pendingCoarse?[key].flatMap {
                    now.timeIntervalSince($0.start) <= 43_200 ? $0 : nil
                }
                return VitalsHistoryBuffer(
                    tiers: filtered(history),
                    maximumFastSamples: fastCap,
                    pendingMinute: pendingMinute,
                    pendingCoarse: pendingCoarse
                )
            }

            self.cpuBuffer = restored(container.cpu, key: "cpu")
            self.gpuBuffer = restored(container.gpu, key: "gpu")
            self.ramBuffer = restored(container.ram, key: "ram")
            self.powerBuffer = restored(container.power, key: "power")
            self.networkDownBuffer = restored(container.networkDown, key: "network")
            self.networkUpBuffer = restored(container.networkUp, key: "networkUp")
            self.diskBuffer = restored(container.disk, key: "disk")
            self.diskReadBuffer = restored(container.diskRead, key: "diskRead")
            self.diskWriteBuffer = restored(container.diskWrite, key: "diskWrite")
            self.batteryStateHistory = VitalsStateHistory(
                points: container.batteryState.points.filter {
                    now.timeIntervalSince($0.timestamp) <= 43_200
                }
            )
        } catch {
            // In case of corrupt file, fallback to empty history
            cpuBuffer = VitalsHistoryBuffer()
            gpuBuffer = VitalsHistoryBuffer()
            ramBuffer = VitalsHistoryBuffer()
            powerBuffer = VitalsHistoryBuffer()
            networkDownBuffer = VitalsHistoryBuffer()
            networkUpBuffer = VitalsHistoryBuffer()
            diskBuffer = VitalsHistoryBuffer()
            diskReadBuffer = VitalsHistoryBuffer()
            diskWriteBuffer = VitalsHistoryBuffer()
            batteryStateHistory = VitalsStateHistory()
        }
    }

    private static func normalizedSamplingInterval(_ interval: TimeInterval) -> TimeInterval {
        guard interval.isFinite, interval >= 1 else { return 1 }
        return interval
    }

    public func startMonitoring(interval: TimeInterval = 1.0) {
        let interval = Self.normalizedSamplingInterval(interval)
        if monitorTask != nil {
            if abs(samplingInterval - interval) > 0.0001 {
                restartMonitoring(interval: interval)
            }
            return
        }
        samplingInterval = interval
        applyFastCapacityToBuffers()
        let saveIntervalTicks = Self.saveIntervalTicks(for: interval)
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { break }
                self.saveThrottleCounter += 1
                // GPU is read from the whole IOAccelerator property dictionary and
                // is by far the most expensive probe here. It feeds a colour
                // signal, not a clock, so once every five ticks is plenty unless
                // someone is actually looking at the drawer.
                self.refreshMetrics(
                    includeProcesses: self.isProcessesTabVisible && (self.saveThrottleCounter % 3 == 0),
                    includeGPU: self.isDrawerVisible || self.saveThrottleCounter % 5 == 0
                )
                // The history is redrawn from memory; the file is a crash
                // recovery copy, and ten minutes of it is ~150MB a day instead
                // of ~1.4GB. `stopMonitoring` still writes on quit.
                if self.saveThrottleCounter >= saveIntervalTicks {
                    self.saveThrottleCounter = 0
                    self.saveHistoryToDisk()
                }
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    /// The history file is a crash recovery copy, so its cadence is a wall
    /// clock budget, not a tick count: a slow sampler must not stretch the
    /// ten-minute save window to fifty.
    static func saveIntervalTicks(for interval: TimeInterval) -> Int {
        guard interval.isFinite, interval > 0 else { return 600 }
        return max(1, Int((600.0 / interval).rounded()))
    }

    /// Restarts an already-running monitor with a new cadence. If the monitor
    /// is idle, this only records the cadence so the next start uses it.
    public func restartMonitoring(interval: TimeInterval) {
        let interval = Self.normalizedSamplingInterval(interval)
        let wasMonitoring = monitorTask != nil
        guard wasMonitoring else {
            samplingInterval = interval
            applyFastCapacityToBuffers()
            return
        }
        guard abs(samplingInterval - interval) > 0.0001 else { return }
        // `stopMonitoring` is the real teardown and hides the Processes tab.
        // A cadence change is not a teardown, so restore the tab afterwards
        // or the inspector freezes with no way back on.
        let processesVisible = isProcessesTabVisible
        stopMonitoring()
        startMonitoring(interval: interval)
        if processesVisible {
            setProcessesTabVisible(true)
        }
    }

    public func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
        wifiService.stop()
        processSamplingTask?.cancel()
        processSamplingTask = nil
        processSamplingGeneration += 1
        setProcessesTabVisible(false)
        saveHistoryToDisk()
    }

    public func refreshMetrics(includeProcesses: Bool = true, includeGPU: Bool = true) {
        let cpuBreakdown = readCPUBreakdown()
        let loads = readLoadAverages()
        let gpuDetailed = includeGPU ? readGPUUsageDetailed() : nil
        let gpu = gpuDetailed?.device ?? metrics.gpuUsage
        let mem = readMemoryBreakdown()
        let disk = readDiskSpace()
        let diskIO: (
            readBytesPerSec: Double,
            writeBytesPerSec: Double,
            readTotalGB: Double,
            writeTotalGB: Double
        ) = isDrawerVisible
            ? (diskIOProbe?() ?? readDiskIOThroughput())
            : (
                metrics.diskReadBytesPerSec,
                metrics.diskWriteBytesPerSec,
                metrics.diskReadTotalGB,
                metrics.diskWriteTotalGB
            )
        let battery: (
            level: Int,
            isCharging: Bool,
            source: String,
            healthPercent: Int,
            cycleCount: Int,
            temperatureCelsius: Double,
            isPresent: Bool,
            voltageVolts: Double,
            chargeWatts: Double,
            timeRemainingMinutes: Int?,
            condition: String,
            systemWatts: Double,
            systemVolts: Double,
            systemAmps: Double,
            adapterWatts: Double,
            maxCapacityMAh: Double,
            designCapacityMAh: Double
        ) = (isDrawerVisible || Self.isPowerMetricVisibleOnRail)
            ? (batteryProbe?() ?? readBatteryInfo())
            : (
                metrics.batteryLevel,
                metrics.isCharging,
                metrics.powerSource,
                metrics.batteryHealthPercent,
                metrics.batteryCycleCount,
                metrics.batteryTemperatureCelsius,
                metrics.batteryIsPresent,
                metrics.batteryVoltageVolts,
                metrics.batteryChargeWatts,
                metrics.batteryTimeRemainingMinutes,
                metrics.batteryCondition,
                metrics.powerSystemWatts,
                metrics.powerSystemVolts,
                metrics.powerSystemAmps,
                metrics.powerAdapterWatts,
                metrics.batteryMaxCapacityMAh,
                metrics.batteryDesignCapacityMAh
            )
        let net = readNetworkThroughputDetailed()
        let thermal = readThermalStateLabel()
        let sensors: (cpu: Double?, gpu: Double?, fanRPM: Int?) = {
            if let cached = thermalCache,
               Date().timeIntervalSince(cached.date) < 5 {
                return (cached.cpu, cached.gpu, cached.fanRPM)
            }
            let readings = HardwareSMCReader.thermalReadings()
            thermalCache = (Date(), readings.cpu, readings.gpu, readings.fanRPM)
            return readings
        }()
        wifiService.refreshLink()

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
            topProcesses: metrics.topProcesses,
            cpuUserUsage: cpuBreakdown.userUsage,
            cpuSystemUsage: cpuBreakdown.sysUsage,
            cpuIdleUsage: cpuBreakdown.idleUsage,
            cpuCoreUsages: cpuBreakdown.coreUsages,
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
            memorySwapTotalMB: mem.swapTotalMB,
            memoryActiveGB: mem.activeGB,
            memoryCachedGB: mem.cachedGB,
            memoryFreeGB: mem.freeGB,
            memoryPressureLevel: mem.pressureLevel,
            networkInterfaceName: net.interfaceName,
            localIPAddress: net.localIP,
            networkTotalReceivedGB: net.totalReceivedGB,
            networkTotalSentGB: net.totalSentGB,
            diskReadBytesPerSec: diskIO.readBytesPerSec,
            diskWriteBytesPerSec: diskIO.writeBytesPerSec,
            diskReadTotalGB: max(diskIO.readTotalGB, metrics.diskReadTotalGB),
            diskWriteTotalGB: max(diskIO.writeTotalGB, metrics.diskWriteTotalGB),
            gpuRendererUsage: gpuDetailed?.renderer ?? metrics.gpuRendererUsage,
            gpuTilerUsage: gpuDetailed?.tiler ?? metrics.gpuTilerUsage,
            gpuMemoryInUseMB: gpuDetailed?.memoryInUseMB ?? metrics.gpuMemoryInUseMB,
            gpuCoreCount: gpuDetailed?.coreCount ?? metrics.gpuCoreCount,
            batteryHealthPercent: battery.healthPercent,
            batteryCycleCount: battery.cycleCount,
            batteryTemperatureCelsius: battery.temperatureCelsius,
            batteryIsPresent: battery.isPresent,
            batteryVoltageVolts: battery.voltageVolts,
            batteryChargeWatts: battery.chargeWatts,
            batteryTimeRemainingMinutes: battery.timeRemainingMinutes,
            batteryCondition: battery.condition,
            powerSystemWatts: battery.systemWatts,
            powerSystemVolts: battery.systemVolts,
            powerSystemAmps: battery.systemAmps,
            powerAdapterWatts: battery.adapterWatts,
            batteryMaxCapacityMAh: battery.maxCapacityMAh,
            batteryDesignCapacityMAh: battery.designCapacityMAh,
            cpuTemperatureCelsius: sensors.cpu,
            gpuTemperatureCelsius: sensors.gpu,
            fanRPM: sensors.fanRPM,
            wifiSSID: wifiService.info.ssid,
            wifiRSSI: wifiService.info.rssi,
            wifiTransmitRateMbps: wifiService.info.transmitRateMbps,
            wifiLatencyMs: wifiService.info.latencyMs,
            wifiPacketLossPercent: wifiService.info.packetLossPercent,
            systemUptimeSeconds: ProcessInfo.processInfo.systemUptime
        )

        let now = Date()
        cpuBuffer.append(VitalsHistoryPoint(timestamp: now, value: cpuBreakdown.totalUsage))
        gpuBuffer.append(VitalsHistoryPoint(timestamp: now, value: gpu))
        ramBuffer.append(VitalsHistoryPoint(timestamp: now, value: mem.usage))
        powerBuffer.append(VitalsHistoryPoint(timestamp: now, value: Double(battery.level) / 100.0))
        // Throughput is stored raw, in bytes per second. The column bands map
        // it onto a log domain; the legacy dual-line graph normalises it at
        // its own call sites.
        networkDownBuffer.append(VitalsHistoryPoint(timestamp: now, value: net.down))
        networkUpBuffer.append(VitalsHistoryPoint(timestamp: now, value: net.up))
        let diskRatio = disk.totalGB > 0 ? (disk.totalGB - disk.freeGB) / disk.totalGB : 0.5
        diskBuffer.append(VitalsHistoryPoint(timestamp: now, value: diskRatio))
        diskReadBuffer.append(VitalsHistoryPoint(
            timestamp: now,
            value: diskIO.readBytesPerSec
        ))
        diskWriteBuffer.append(VitalsHistoryPoint(
            timestamp: now,
            value: diskIO.writeBytesPerSec
        ))
        let batteryState: Int = {
            guard battery.isPresent else { return 0 }
            if battery.level >= 100, !battery.isCharging, battery.source == "AC Power" {
                return 2
            }
            return battery.isCharging ? 1 : 0
        }()
        if battery.isPresent {
            recordBatteryState(batteryState, at: now)
        }

        // The rail only needs the cheap metrics above. The 580-process walk
        // runs in the background and publishes on a later main-actor turn.
        if includeProcesses {
            requestProcessRefresh()
        }
    }

    /// Like `refreshMetrics`, but waits for the background process sample so
    /// callers that explicitly ask for a fresh list (tests, the Process
    /// Inspector opening) can observe it before returning.
    public func refreshMetricsAsync(includeProcesses: Bool = false) async {
        refreshMetrics(includeProcesses: includeProcesses)
        if includeProcesses {
            // An explicit async refresh is a request for a fresh list even
            // when its caller has not yet toggled the inspector-visible flag.
            requestProcessRefresh(force: true)
            if let processSamplingTask {
                await processSamplingTask.value
            }
        }
    }

    /// `nettop` is visible-work only: the sampler runs while the Processes tab
    /// is on screen and stops as soon as it leaves the view hierarchy.
    public func setProcessesTabVisible(_ visible: Bool) {
        guard isProcessesTabVisible != visible else { return }
        isProcessesTabVisible = visible
        if visible {
            startProcessNetworkSampling()
            requestProcessRefresh(force: true)
        } else {
            processSamplingTask?.cancel()
            processSamplingTask = nil
            processSamplingGeneration += 1
            stopProcessNetworkSampling()
        }
    }

    public func killProcess(pid: Int32) {
        guard pid > 1 else { return }

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

    /// Kick a background process sample. The drawer keeps rendering the last
    /// published list, so this can take as long as the process table needs.
    private func requestProcessRefresh(force: Bool = false) {
        guard force || isProcessesTabVisible else { return }
        guard processSamplingTask == nil else { return }

        let friendlyNames = Dictionary(
            uniqueKeysWithValues: NSWorkspace.shared.runningApplications.compactMap { app -> (Int32, String)? in
                let pid = app.processIdentifier
                guard pid > 0,
                      let name = app.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !name.isEmpty else { return nil }
                return (pid, name)
            }
        )
        let input = ProcessSamplingInput(
            snapshot: ProcessSamplingSnapshot(
                previousCPUTicks: buffer.previousProcessCPUTicks,
                previousResources: buffer.previousProcessResources,
                previousTimestamp: buffer.previousProcessSampleTimestamp
            ),
            nameCache: buffer.processNames,
            bundleCache: buffer.appBundles,
            friendlyNames: friendlyNames,
            networkSpeeds: processNetworkSpeeds
        )

        processSamplingGeneration += 1
        let generation = processSamplingGeneration
        processSamplingTask = Task { [weak self] in
            let output = await Self.sampleProcessesInBackground(input)
            guard !Task.isCancelled,
                  let self,
                  self.processSamplingGeneration == generation else { return }
            self.publishProcessSample(output)
        }
    }

    private nonisolated static func sampleProcessesInBackground(
        _ input: ProcessSamplingInput
    ) async -> ProcessSamplingOutput {
        await Task.detached(priority: .utility) {
            ProcessSamplingWorker.sample(input)
        }.value
    }

    private func publishProcessSample(_ output: ProcessSamplingOutput) {
        processSamplingTask = nil
        buffer.previousProcessCPUTicks = output.cpuTicks
        buffer.previousProcessResources = output.resources
        buffer.previousProcessSampleTimestamp = output.timestamp
        buffer.processNames = output.nameCache
        buffer.appBundles = output.bundleCache

        var updated = metrics
        updated.topProcesses = output.items
        metrics = updated
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

    public func readDiskIOThroughput() -> (
        readBytesPerSec: Double,
        writeBytesPerSec: Double,
        readTotalGB: Double,
        writeTotalGB: Double
    ) {
        var iterator: io_iterator_t = 0
        let matchDict = IOServiceMatching("IOBlockStorageDriver")
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matchDict, &iterator)
        guard result == kIOReturnSuccess, iterator != 0 else { return (0.0, 0.0, 0.0, 0.0) }
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

        return (
            max(readSpeed, 0.0),
            max(writeSpeed, 0.0),
            Double(totalRead) / 1_073_741_824.0,
            Double(totalWrite) / 1_073_741_824.0
        )
    }

    public func readBatteryInfo() -> (
        level: Int,
        isCharging: Bool,
        source: String,
        healthPercent: Int,
        cycleCount: Int,
        temperatureCelsius: Double,
        isPresent: Bool,
        voltageVolts: Double,
        chargeWatts: Double,
        timeRemainingMinutes: Int?,
        condition: String,
        systemWatts: Double,
        systemVolts: Double,
        systemAmps: Double,
        adapterWatts: Double,
        maxCapacityMAh: Double,
        designCapacityMAh: Double
    ) {
        var level = 100
        var isCharging = false
        var sourceName = "AC Power"
        var isPresent = false
        var timeRemainingMinutes: Int?

        if let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] {
            for source in sources {
                if let desc = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] {
                    isPresent = desc[kIOPSCurrentCapacityKey as String] != nil
                    level = desc[kIOPSCurrentCapacityKey] as? Int ?? 100
                    isCharging = desc[kIOPSIsChargingKey] as? Bool ?? false
                    let source = desc[kIOPSPowerSourceStateKey] as? String ?? "AC Power"
                    sourceName = (source == kIOPSACPowerValue) ? "AC Power" : "Battery"

                    let timeKey = isCharging
                        ? kIOPSTimeToFullChargeKey
                        : kIOPSTimeToEmptyKey
                    let minutes = (desc[timeKey as String] as? NSNumber)?.intValue
                        ?? (desc[timeKey as String] as? Int)
                    if let minutes, minutes > 0, minutes != 65535 {
                        timeRemainingMinutes = minutes
                    }
                    break
                }
            }
        }

        var cycleCount = 0
        var temperatureCelsius = 31.0
        var healthPercent = 100
        var voltageVolts = 0.0
        var chargeWatts = 0.0
        var maxCapacityMAh = 0.0
        var designCapacityMAh = 0.0
        var condition = "Normal"
        var systemWatts = 0.0
        var systemVolts = 0.0
        var systemAmps = 0.0
        var adapterWatts = 0.0

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

                    if let rawVoltage = (dict["Voltage"] as? NSNumber)?.doubleValue {
                        voltageVolts = rawVoltage / 1000.0
                    }
                    let amperage = (dict["Amperage"] as? NSNumber)?.doubleValue
                        ?? (dict["InstantAmperage"] as? NSNumber)?.doubleValue
                    if let amperage {
                        // mA × V / 1000 = W; the raw sign is charging-positive.
                        chargeWatts = amperage * voltageVolts / 1000.0
                    }

                    if let health = dict["BatteryHealth"] as? String, !health.isEmpty {
                        condition = health
                    }

                    // Adapter → system → battery. `PowerTelemetryData` is
                    // absent on desktops and older Intel Macs; every field
                    // then stays 0 and the UI hides the flow band. The adapter
                    // figure is the negotiated rating, never a live draw.
                    let telemetry = dict["PowerTelemetryData"] as? [String: Any]
                    systemWatts = ((telemetry?["SystemPowerIn"] as? NSNumber)?.doubleValue ?? 0) / 1000.0
                    systemVolts = ((telemetry?["SystemVoltageIn"] as? NSNumber)?.doubleValue ?? 0) / 1000.0
                    systemAmps = ((telemetry?["SystemCurrentIn"] as? NSNumber)?.doubleValue ?? 0) / 1000.0

                    let adapter = dict["AdapterDetails"] as? [String: Any]
                    let ratedWatts = (adapter?["Watts"] as? NSNumber)?.doubleValue ?? 0
                    if ratedWatts > 0 {
                        adapterWatts = ratedWatts
                    } else {
                        let port = dict["PortControllerInfo"] as? [String: Any]
                        let maxMilliwatts = (port?["PortControllerMaxPower"] as? NSNumber)?.doubleValue ?? 0
                        adapterWatts = maxMilliwatts / 1000.0
                    }

                    let batteryData = dict["BatteryData"] as? [String: Any]
                    maxCapacityMAh = (batteryData?["AppleRawMaxCapacity"] as? NSNumber)?.doubleValue
                        ?? (batteryData?["FullChargeCapacity"] as? NSNumber)?.doubleValue
                        ?? (batteryData?["NominalChargeCapacity"] as? NSNumber)?.doubleValue
                        ?? (dict["AppleRawMaxCapacity"] as? NSNumber)?.doubleValue
                        ?? 0
                    designCapacityMAh = (batteryData?["DesignCapacity"] as? NSNumber)?.doubleValue
                        ?? (dict["DesignCapacity"] as? NSNumber)?.doubleValue
                        ?? 0
                }
            }
        }

        return (
            level,
            isCharging,
            sourceName,
            healthPercent,
            cycleCount,
            temperatureCelsius,
            isPresent,
            voltageVolts,
            chargeWatts,
            timeRemainingMinutes,
            condition,
            systemWatts,
            systemVolts,
            systemAmps,
            adapterWatts,
            maxCapacityMAh,
            designCapacityMAh
        )
    }

    public func readMemoryBreakdown() -> (
        usage: Double,
        usedGB: Double,
        totalGB: Double,
        appGB: Double,
        wiredGB: Double,
        compressedGB: Double,
        swapUsedMB: Double,
        pressureLevel: String,
        activeGB: Double,
        cachedGB: Double,
        freeGB: Double,
        swapTotalMB: Double
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
            return (0.45, totalGB * 0.45, totalGB, 4.0, 2.0, 1.0, 0.0, "Normal", 0, 0, 0, 0)
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
        let cachedGB = ((Double(vmStats.inactive_count) + Double(vmStats.speculative_count)) * pageSize) / 1_073_741_824.0
        // Derived as the remainder so the five composition segments always add
        // up to physical memory; `free_count` alone leaves pages unaccounted.
        let freeGB = max(totalGB - (usedGB + cachedGB), 0)
        let appGB = max(internalMinusPurgeable, activeGB)

        var swapUsage = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        var swapUsedMB: Double = 0.0
        var swapTotalMB: Double = 0.0
        if sysctlbyname("vm.swapusage", &swapUsage, &swapSize, nil, 0) == 0 {
            swapUsedMB = Double(swapUsage.xsu_used) / 1_048_576.0
            swapTotalMB = Double(swapUsage.xsu_total) / 1_048_576.0
        }

        let pressureLevel: String = {
            if usage >= 0.85 { return "Critical" }
            if usage >= 0.70 { return "Warning" }
            return "Normal"
        }()

        return (
            usage,
            usedGB,
            totalGB,
            appGB,
            wiredGB,
            compressedGB,
            swapUsedMB,
            pressureLevel,
            activeGB,
            cachedGB,
            freeGB,
            swapTotalMB
        )
    }

    public func readCPUBreakdown() -> (
        totalUsage: Double,
        userUsage: Double,
        sysUsage: Double,
        idleUsage: Double,
        coreUsages: [Double]
    ) {
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
            return (0.15, 0.10, 0.05, 0.85, [])
        }

        var totalUsage: Double = 0.15
        var userUsage: Double = 0.10
        var sysUsage: Double = 0.05
        var idleUsage: Double = 0.85
        var coreUsages: [Double] = []

        if let prev = buffer.previousCpuInfo, buffer.previousCpuInfoCount == numCpuInfo {
            var userTicks: Int64 = 0
            var sysTicks: Int64 = 0
            var idleTicks: Int64 = 0
            var totalTicks: Int64 = 0
            coreUsages.reserveCapacity(Int(numProcessors))

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
                let coreTicks = u + s + n + id
                totalTicks += coreTicks
                // Kernel logical CPU order: on Apple Silicon the performance
                // cores occupy the first `performanceCoreCount` indices.
                coreUsages.append(
                    coreTicks > 0
                        ? Double(u + s + n) / Double(coreTicks)
                        : 0
                )
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
            min(max(idleUsage, 0.0), 1.0),
            coreUsages.map { min(max($0, 0.0), 1.0) }
        )
    }

    deinit {
        monitorTask?.cancel()
        processNetworkTask?.cancel()
        processSamplingTask?.cancel()
        mach_port_deallocate(mach_task_self_, hostPort)
    }

    private func startProcessNetworkSampling() {
        guard processNetworkTask == nil else { return }

        processNetworkSpeeds.removeAll()
        applyProcessNetworkSpeeds([:])

        processNetworkTask = Task { [weak self] in
            await self?.processNetworkSampler.reset()

            while !Task.isCancelled {
                guard let self else { break }
                let speeds = await self.processNetworkSampler.sample()
                guard !Task.isCancelled, self.isProcessesTabVisible else { break }
                self.applyProcessNetworkSpeeds(speeds)

                do {
                    try await Task.sleep(for: .seconds(2))
                } catch {
                    break
                }
            }
        }
    }

    private func stopProcessNetworkSampling() {
        isProcessesTabVisible = false
        processNetworkTask?.cancel()
        processNetworkTask = nil
    }

    private func applyProcessNetworkSpeeds(_ speeds: [Int32: ProcessNetworkSpeed]) {
        let appPIDs = Set(
            NSWorkspace.shared.runningApplications
                .map(\.processIdentifier)
                .filter { $0 > 0 }
        )
        let attributedSpeeds = attributeNetworkSpeeds(speeds, appPIDs: appPIDs)
        processNetworkSpeeds = attributedSpeeds.filter { appPIDs.contains($0.key) }
        guard !metrics.topProcesses.isEmpty else { return }

        var rows = metrics.topProcesses
        for index in rows.indices {
            let speed = processNetworkSpeeds[rows[index].id]
            rows[index].networkDownBytesPerSecond = speed?.downBytesPerSecond ?? 0
            rows[index].networkUpBytesPerSecond = speed?.upBytesPerSecond ?? 0
        }

        var updated = metrics
        updated.topProcesses = rows
        metrics = updated
    }

    private func attributeNetworkSpeeds(
        _ speeds: [Int32: ProcessNetworkSpeed],
        appPIDs: Set<Int32>
    ) -> [Int32: ProcessNetworkSpeed] {
        var parentPIDs: [Int32: Int32] = [:]
        for pid in speeds.keys {
            var info = proc_bsdinfo()
            let size = proc_pidinfo(
                pid,
                PROC_PIDTBSDINFO,
                0,
                &info,
                Int32(MemoryLayout<proc_bsdinfo>.size)
            )
            guard size > 0 else { continue }
            parentPIDs[pid] = Int32(clamping: info.pbi_ppid)
        }

        return ProcessNetworkAttribution.attribute(
            speeds,
            parentPIDs: parentPIDs,
            appPIDs: appPIDs
        )
    }

    // MARK: - Zero-Overhead GPU & Network Telemetry

    public func readGPUUsage() -> Double {
        readGPUUsageDetailed().device
    }

    public func readGPUUsageDetailed() -> (
        device: Double,
        renderer: Double,
        tiler: Double,
        memoryInUseMB: Double,
        coreCount: Int
    ) {
        var iterator: io_iterator_t = 0
        let matchDict = IOServiceMatching("IOAccelerator")
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matchDict, &iterator)
        guard result == kIOReturnSuccess, iterator != 0 else { return (0, 0, 0, 0, 0) }
        defer { IOObjectRelease(iterator) }

        var device: Double = 0
        var renderer: Double = 0
        var tiler: Double = 0
        var memoryInUseMB: Double = 0
        var coreCount = 0
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
                let devUtil = (perfStats["Device Utilization %"] as? NSNumber)?.doubleValue
                    ?? (perfStats["Device Utilization %"] as? Int).map(Double.init)
                let rendUtil = (perfStats["Renderer Utilization %"] as? NSNumber)?.doubleValue
                    ?? (perfStats["Renderer Utilization %"] as? Int).map(Double.init)
                let tilerUtil = (perfStats["Tiler Utilization %"] as? NSNumber)?.doubleValue
                    ?? (perfStats["Tiler Utilization %"] as? Int).map(Double.init)
                let memoryBytes = (perfStats["In use system memory"] as? NSNumber)?.doubleValue
                    ?? (perfStats["In use system memory"] as? Int).map(Double.init)

                // Today's headline chain: Device → Renderer.
                if let devUtil {
                    device = max(device, devUtil / 100.0)
                } else if let rendUtil {
                    device = max(device, rendUtil / 100.0)
                }
                if let rendUtil { renderer = max(renderer, rendUtil / 100.0) }
                if let tilerUtil { tiler = max(tiler, tilerUtil / 100.0) }
                if let memoryBytes { memoryInUseMB = max(memoryInUseMB, memoryBytes / 1_048_576.0) }

                let cores = (dict["gpu-core-count"] as? NSNumber)?.intValue
                    ?? (dict["gpu-core-count"] as? Int)
                if let cores { coreCount = max(coreCount, cores) }
            }
        }
        return (
            min(max(device, 0.0), 1.0),
            min(max(renderer, 0.0), 1.0),
            min(max(tiler, 0.0), 1.0),
            max(memoryInUseMB, 0),
            max(coreCount, 0)
        )
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
                let deltaIn = Double(NetworkCounterDelta.bytes(previous: prevIn, current: totalIn))
                let deltaOut = Double(NetworkCounterDelta.bytes(previous: prevOut, current: totalOut))
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
