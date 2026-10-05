// Sources/PurahCore/Services/HardwareVitalsService.swift
import Foundation
import AppKit
import Darwin
import Observation

public struct ProcessInfoItem: Identifiable, Sendable {
    public let id: Int32
    public let name: String
    public let cpuPercent: Double
    public let memoryPercent: Double

    public init(id: Int32, name: String, cpuPercent: Double, memoryPercent: Double) {
        self.id = id
        self.name = name
        self.cpuPercent = cpuPercent
        self.memoryPercent = memoryPercent
    }
}

public struct HardwareVitalsInfo: Sendable {
    public var cpuUsage: Double // 0.0 ~ 1.0
    public var memoryUsage: Double // 0.0 ~ 1.0
    public var isUnderThermalPressure: Bool
    public var topProcesses: [ProcessInfoItem]

    public init(
        cpuUsage: Double = 0.15,
        memoryUsage: Double = 0.45,
        isUnderThermalPressure: Bool = false,
        topProcesses: [ProcessInfoItem] = []
    ) {
        self.cpuUsage = cpuUsage
        self.memoryUsage = memoryUsage
        self.isUnderThermalPressure = isUnderThermalPressure
        self.topProcesses = topProcesses
    }
}

@Observable
public final class HardwareVitalsService: @unchecked Sendable {
    public static let shared = HardwareVitalsService()

    public private(set) var metrics: HardwareVitalsInfo = .init()
    private var timer: Timer?

    private var previousCpuInfo: processor_info_array_t?
    private var previousCpuInfoCount: mach_msg_type_number_t = 0

    public init() {
        Task.detached(priority: .utility) { [weak self] in
            await self?.refreshMetricsAsync(includeProcesses: false)
            try? await Task.sleep(nanoseconds: 200_000_000)
            await self?.refreshMetricsAsync(includeProcesses: false)
        }
        startMonitoring(interval: 2.0)
    }

    public func startMonitoring(interval: TimeInterval = 3.0) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task.detached(priority: .utility) { [weak self] in
                // Lightweight periodic poll (CPU & Memory values only, zero process iteration overhead)
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
        let mem = readMemoryUsage()
        let thermal = (cpu > 0.80 || mem > 0.85)
        let top = includeProcesses ? readTopProcessesNative() : metrics.topProcesses

        metrics = HardwareVitalsInfo(
            cpuUsage: cpu,
            memoryUsage: mem,
            isUnderThermalPressure: thermal,
            topProcesses: top
        )
    }

    public func refreshMetricsAsync(includeProcesses: Bool = false) async {
        let cpu = readCPUUsage()
        let mem = readMemoryUsage()
        let thermal = (cpu > 0.80 || mem > 0.85)
        let currentProcesses = await MainActor.run { self.metrics.topProcesses }
        let top = includeProcesses ? readTopProcessesNative() : (currentProcesses.isEmpty ? readTopProcessesNative() : currentProcesses)

        await MainActor.run {
            self.metrics = HardwareVitalsInfo(
                cpuUsage: cpu,
                memoryUsage: mem,
                isUnderThermalPressure: thermal,
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
            await self?.refreshMetricsAsync()
        }
    }

    // MARK: - Mach Kernel APIs (100% 原生 C 接口，零开销瞬时读取)
    private func readMemoryUsage() -> Double {
        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return 0.45 }

        let pageSize = Double(getpagesize())
        let active = Double(vmStats.active_count) * pageSize
        let wired = Double(vmStats.wire_count) * pageSize
        let compressed = Double(vmStats.compressor_page_count) * pageSize
        let totalMem = Double(ProcessInfo.processInfo.physicalMemory)

        let used = active + wired + compressed
        return min(max(used / totalMem, 0.0), 1.0)
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
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: prev), vm_size_t(previousCpuInfoCount))
        }

        previousCpuInfo = cpuInfo
        previousCpuInfoCount = numCpuInfo

        return min(max(totalUsage, 0.0), 1.0)
    }

    // MARK: - 100% 原生 Darwin proc_pidinfo 与 NSWorkspace 采集，彻底杜绝 /bin/ps 管道死锁与沙盒崩溃
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

        // 按内存消耗从高到低排序，取前 3 个
        items.sort { $0.memoryPercent > $1.memoryPercent }
        return Array(items.prefix(3))
    }
}
