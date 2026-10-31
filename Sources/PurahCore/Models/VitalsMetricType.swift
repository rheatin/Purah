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

// MARK: - 24-Hour Vitals Persisted Telemetry Container
public struct VitalsPersistedHistory: Codable, Sendable {
    public var cpu: [VitalsHistoryPoint]
    public var gpu: [VitalsHistoryPoint]
    public var ram: [VitalsHistoryPoint]
    public var power: [VitalsHistoryPoint]
    public var networkDown: [VitalsHistoryPoint]
    public var networkUp: [VitalsHistoryPoint]
    public var disk: [VitalsHistoryPoint]

    public init(
        cpu: [VitalsHistoryPoint] = [],
        gpu: [VitalsHistoryPoint] = [],
        ram: [VitalsHistoryPoint] = [],
        power: [VitalsHistoryPoint] = [],
        networkDown: [VitalsHistoryPoint] = [],
        networkUp: [VitalsHistoryPoint] = [],
        disk: [VitalsHistoryPoint] = []
    ) {
        self.cpu = cpu
        self.gpu = gpu
        self.ram = ram
        self.power = power
        self.networkDown = networkDown
        self.networkUp = networkUp
        self.disk = disk
    }
}

// MARK: - Multi-Resolution Vitals Time Scope
public enum VitalsTimeScope: String, Codable, Sendable, CaseIterable, Identifiable {
    case realTime30s = "30s"
    case hour1 = "1h"
    case day24h = "24h"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .realTime30s: return "30s"
        case .hour1: return "1h"
        case .day24h: return "24h"
        }
    }

    public var durationSeconds: TimeInterval {
        switch self {
        case .realTime30s: return 30.0
        case .hour1: return 3600.0
        case .day24h: return 86400.0
        }
    }

    public var markings: (left: String, middle: String, right: String) {
        switch self {
        case .realTime30s: return ("-30s", "-15s", "Now")
        case .hour1: return ("-60m", "-30m", "Now")
        case .day24h: return ("-24h", "-12h", "Now")
        }
    }
}
