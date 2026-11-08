// Sources/PurahCore/Models/VitalsMetricType.swift
import Foundation

public enum VitalsMetricType: String, CaseIterable, Codable, Sendable, Identifiable {
    case cpu = "cpu"
    case gpu = "gpu"
    case ram = "ram"
    case power = "power"
    case network = "network"
    case disk = "disk"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .cpu: "CPU Load"
        case .gpu: "GPU Activity"
        case .ram: "Memory (RAM)"
        case .power: "Battery & Power"
        case .network: "Network I/O"
        case .disk: "Disk Storage"
        }
    }

    /// The chip label. A decomposed chip is one row beside a live graph, and
    /// "Network I/O" spent a third of that width on words every Mac user
    /// already reads as NET.
    public var shortName: String {
        switch self {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .ram: "RAM"
        case .power: "PWR"
        case .network: "NET"
        case .disk: "DISK"
        }
    }

    public var systemIcon: String {
        switch self {
        case .cpu: "cpu"
        case .gpu: "display"
        case .ram: "memorychip"
        case .power: "bolt.batteryblock.fill"
        case .network: "network"
        case .disk: "internaldrive"
        }
    }
}

// MARK: - Vitals History Data Point
public struct VitalsHistoryPoint: Codable, Sendable, Identifiable {
    public var id: UUID
    public let timestamp: Date
    public let value: Double

    public init(id: UUID = UUID(), timestamp: Date = Date(), value: Double) {
        self.id = id
        self.timestamp = timestamp
        self.value = value
    }

    enum CodingKeys: String, CodingKey {
        case timestamp
        case value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.timestamp = try container.decode(Date.self, forKey: .timestamp)
        self.value = try container.decode(Double.self, forKey: .value)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(value, forKey: .value)
    }
}

// MARK: - Vitals Persisted Telemetry Container
public struct VitalsPersistedHistory: Codable, Sendable {
    public static let currentVersion = 3

    public var version: Int
    public var cpu: VitalsTieredHistory
    public var gpu: VitalsTieredHistory
    public var ram: VitalsTieredHistory
    public var power: VitalsTieredHistory
    public var networkDown: VitalsTieredHistory
    public var networkUp: VitalsTieredHistory
    public var disk: VitalsTieredHistory
    public var diskRead: VitalsTieredHistory
    public var diskWrite: VitalsTieredHistory
    public var batteryState: VitalsStateHistory
    /// In-progress minute buckets keyed by series (`cpu`, `gpu`, `network`…).
    public var pendingMinute: [String: VitalsPendingBucket]?
    /// In-progress twelve-minute buckets, same keys.
    public var pendingCoarse: [String: VitalsPendingBucket]?

    public init(
        version: Int = VitalsPersistedHistory.currentVersion,
        cpu: VitalsTieredHistory = .init(),
        gpu: VitalsTieredHistory = .init(),
        ram: VitalsTieredHistory = .init(),
        power: VitalsTieredHistory = .init(),
        networkDown: VitalsTieredHistory = .init(),
        networkUp: VitalsTieredHistory = .init(),
        disk: VitalsTieredHistory = .init(),
        diskRead: VitalsTieredHistory = .init(),
        diskWrite: VitalsTieredHistory = .init(),
        batteryState: VitalsStateHistory = .init(),
        pendingMinute: [String: VitalsPendingBucket]? = nil,
        pendingCoarse: [String: VitalsPendingBucket]? = nil
    ) {
        self.version = version
        self.cpu = cpu
        self.gpu = gpu
        self.ram = ram
        self.power = power
        self.networkDown = networkDown
        self.networkUp = networkUp
        self.disk = disk
        self.diskRead = diskRead
        self.diskWrite = diskWrite
        self.batteryState = batteryState
        self.pendingMinute = pendingMinute
        self.pendingCoarse = pendingCoarse
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case cpu
        case gpu
        case ram
        case power
        case networkDown
        case networkUp
        case disk
        case diskRead
        case diskWrite
        case batteryState
        case pendingMinute
        case pendingCoarse
    }

    /// Version 1 held a single 1-second array per series. Those points load
    /// into the fast tier by age; the minute and coarse tiers start empty and
    /// fill as the app runs. Anything that fails to decode still yields an
    /// empty history at the service boundary.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let storedVersion = try container.decodeIfPresent(Int.self, forKey: .version)

        if let storedVersion, storedVersion >= 2 {
            self.version = storedVersion
            let networkDown = try container.decodeIfPresent(VitalsTieredHistory.self, forKey: .networkDown) ?? .init()
            let networkUp = try container.decodeIfPresent(VitalsTieredHistory.self, forKey: .networkUp) ?? .init()
            let diskRead = try container.decodeIfPresent(VitalsTieredHistory.self, forKey: .diskRead) ?? .init()
            let diskWrite = try container.decodeIfPresent(VitalsTieredHistory.self, forKey: .diskWrite) ?? .init()
            self.cpu = try container.decodeIfPresent(VitalsTieredHistory.self, forKey: .cpu) ?? .init()
            self.gpu = try container.decodeIfPresent(VitalsTieredHistory.self, forKey: .gpu) ?? .init()
            self.ram = try container.decodeIfPresent(VitalsTieredHistory.self, forKey: .ram) ?? .init()
            self.power = try container.decodeIfPresent(VitalsTieredHistory.self, forKey: .power) ?? .init()
            self.disk = try container.decodeIfPresent(VitalsTieredHistory.self, forKey: .disk) ?? .init()
            if storedVersion < 3 {
                // Versions 1–2 stored throughput as a 0…1 ratio clamped at
                // 10 MiB/s. Version 3 stores bytes per second.
                let scale = 10_485_760.0
                self.networkDown = Self.scaled(networkDown, by: scale)
                self.networkUp = Self.scaled(networkUp, by: scale)
                self.diskRead = Self.scaled(diskRead, by: scale)
                self.diskWrite = Self.scaled(diskWrite, by: scale)
            } else {
                self.networkDown = networkDown
                self.networkUp = networkUp
                self.diskRead = diskRead
                self.diskWrite = diskWrite
            }
            self.batteryState = try container.decodeIfPresent(VitalsStateHistory.self, forKey: .batteryState) ?? .init()
            self.pendingMinute = try container.decodeIfPresent(
                [String: VitalsPendingBucket].self,
                forKey: .pendingMinute
            )
            self.pendingCoarse = try container.decodeIfPresent(
                [String: VitalsPendingBucket].self,
                forKey: .pendingCoarse
            )
            return
        }

        self.version = 1
        func legacy(_ key: CodingKeys) throws -> VitalsTieredHistory {
            VitalsTieredHistory(
                fast: try container.decodeIfPresent([VitalsHistoryPoint].self, forKey: key) ?? []
            )
        }
        let scale = 10_485_760.0
        self.cpu = try legacy(.cpu)
        self.gpu = try legacy(.gpu)
        self.ram = try legacy(.ram)
        self.power = try legacy(.power)
        self.networkDown = Self.scaled(try legacy(.networkDown), by: scale)
        self.networkUp = Self.scaled(try legacy(.networkUp), by: scale)
        self.disk = try legacy(.disk)
        self.diskRead = .init()
        self.diskWrite = .init()
        self.batteryState = .init()
        self.pendingMinute = nil
        self.pendingCoarse = nil
    }

    private static func scaled(
        _ history: VitalsTieredHistory,
        by factor: Double
    ) -> VitalsTieredHistory {
        func scale(_ points: [VitalsHistoryPoint]) -> [VitalsHistoryPoint] {
            points.map {
                VitalsHistoryPoint(timestamp: $0.timestamp, value: $0.value * factor)
            }
        }
        return VitalsTieredHistory(
            fast: scale(history.fast),
            minute: scale(history.minute),
            coarse: scale(history.coarse)
        )
    }
}

// MARK: - Multi-Resolution Vitals Time Scope
public enum VitalsTimeScope: String, Codable, Sendable, CaseIterable, Identifiable {
    case realTime30s = "30s"
    case minutes5 = "5m"
    case hour1 = "1h"
    case hours12 = "12h"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .realTime30s: return "30s"
        case .minutes5: return "5m"
        case .hour1: return "1h"
        case .hours12: return "12h"
        }
    }

    public var durationSeconds: TimeInterval {
        switch self {
        case .realTime30s: return 30.0
        case .minutes5: return 300.0
        case .hour1: return 3600.0
        case .hours12: return 43_200.0
        }
    }

    public var markings: (left: String, middle: String, right: String) {
        switch self {
        case .realTime30s: return ("-30s", "-15s", "Now")
        case .minutes5: return ("-5m", "-2.5m", "Now")
        case .hour1: return ("-60m", "-30m", "Now")
        case .hours12: return ("-12h", "-6h", "Now")
        }
    }
}
