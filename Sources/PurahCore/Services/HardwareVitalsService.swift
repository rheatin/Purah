// Sources/PurahCore/Services/HardwareVitalsService.swift
import Foundation
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
        memoryUsage: Double = 0.55,
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
        refreshMetrics()
    }

    public func startMonitoring(interval: TimeInterval = 3.0) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshMetrics()
            }
        }
    }

    public func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    public func refreshMetrics() {
        let cpu = readCPUUsage()
        let mem = readMemoryUsage()
        let thermal = (cpu > 0.85 || mem > 0.88)
        let top = readTopProcesses()

        metrics = HardwareVitalsInfo(
            cpuUsage: cpu,
            memoryUsage: mem,
            isUnderThermalPressure: thermal,
            topProcesses: top
        )
    }

    public func killProcess(pid: Int32) {
        kill(pid, SIGTERM)
        // 稍等 0.5 秒重新采集
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.refreshMetrics()
        }
    }

    // MARK: - Mach Kernel APIs
    private func readMemoryUsage() -> Double {
        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return 0.5 }

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

        guard result == KERN_SUCCESS, let cpuInfo = cpuInfo else { return 0.2 }

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
            totalUsage = 0.2
        }

        if let prev = previousCpuInfo {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: prev), vm_size_t(previousCpuInfoCount))
        }

        previousCpuInfo = cpuInfo
        previousCpuInfoCount = numCpuInfo

        return min(max(totalUsage, 0.0), 1.0)
    }

    private func readTopProcesses() -> [ProcessInfoItem] {
        let task = Process()
        task.launchPath = "/bin/ps"
        task.arguments = ["-arcx", "-o", "%cpu,%mem,pid,comm"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return [] }

            var items: [ProcessInfoItem] = []
            let lines = output.split(separator: "\n").dropFirst() // 跳过首行表头

            for line in lines.prefix(3) {
                let parts = line.split(separator: " ", omittingEmptySubsequences: true)
                guard parts.count >= 4,
                      let cpu = Double(parts[0]),
                      let mem = Double(parts[1]),
                      let pid = Int32(parts[2]) else { continue }
                let name = parts[3...].joined(separator: " ")
                items.append(ProcessInfoItem(id: pid, name: name, cpuPercent: cpu, memoryPercent: mem))
            }
            return items
        } catch {
            return []
        }
    }
}
