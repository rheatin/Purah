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
        case .cpu: "CPU Load"
        case .ram: "Memory (RAM)"
        case .power: "Power & Thermal"
        case .disk: "Disk Storage"
        }
    }

    public var systemIcon: String {
        switch self {
        case .cpu: "cpu"
        case .ram: "memorychip"
        case .power: "bolt.batteryblock.fill"
        case .disk: "internaldrive"
        }
    }
}
