import Foundation
import Darwin

public enum ProcessSortMetric: String, CaseIterable, Identifiable, Sendable {
    case cpu
    case memory
    case network
    case disk
    case power

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .cpu: return "CPU"
        case .memory: return "MEM"
        case .network: return "NET"
        case .disk: return "DISK"
        case .power: return "PWR"
        }
    }

    public func value(for process: ProcessInfoItem) -> Double {
        switch self {
        case .cpu:
            return max(process.cpuPercent, 0)
        case .memory:
            return max(process.memoryMB, 0)
        case .network:
            return max(process.networkDownBytesPerSecond + process.networkUpBytesPerSecond, 0)
        case .disk:
            return max(process.diskReadBytesPerSecond + process.diskWriteBytesPerSecond, 0)
        case .power:
            return max(process.energyWatts, 0)
        }
    }
}

public enum ProcessCPUPercent {
    /// `proc_taskinfo` CPU counters use absolute-time units (mach ticks), not
    /// nanoseconds. The ratio is fixed for the life of the machine.
    public static let machTickConversion: Double = {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        guard timebase.denom > 0 else { return 1.0 }
        return Double(timebase.numer) / Double(timebase.denom)
    }()

    public static func calculate(
        previous: UInt64,
        current: UInt64,
        elapsed: TimeInterval,
        coreCount: Int,
        tickConversion: Double = 1.0
    ) -> Double {
        guard elapsed > 0.05,
              current >= previous,
              coreCount > 0,
              tickConversion.isFinite,
              tickConversion > 0 else { return 0 }
        let convertedNanoseconds = Double(current - previous) * tickConversion
        let usedSeconds = convertedNanoseconds / 1_000_000_000.0
        let cap = Double(coreCount) * 100.0
        return min(max((usedSeconds / elapsed) * 100.0, 0.0), cap)
    }
}

public struct ProcessInspectorRanking {
    public static func ranked(
        _ items: [ProcessInfoItem],
        by metric: ProcessSortMetric,
        limit: Int
    ) -> [ProcessInfoItem] {
        guard limit > 0 else { return [] }
        return Array(
            items.sorted { lhs, rhs in
                let left = metric.value(for: lhs)
                let right = metric.value(for: rhs)
                if left != right { return left > right }

                let nameOrder = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
                return lhs.id < rhs.id
            }.prefix(limit)
        )
    }
}
