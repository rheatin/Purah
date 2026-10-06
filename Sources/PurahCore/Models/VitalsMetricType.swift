// Sources/PurahCore/Models/VitalsMetricType.swift
import Foundation

public enum VitalsMetricType: String, CaseIterable, Codable, Sendable, Identifiable {
    case cpu = "cpu"
    case ram = "ram"
    case power = "power"
    case disk = "disk"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .cpu: return "CPU Load"
        case .ram: return "Memory (RAM)"
        case .power: return "Power & Thermal"
        case .disk: return "Disk Storage"
        }
    }

    public var systemIcon: String {
        switch self {
        case .cpu: return "cpu"
        case .ram: return "memorychip"
        case .power: return "bolt.batteryblock.fill"
        case .disk: return "internaldrive"
        }
    }
}
