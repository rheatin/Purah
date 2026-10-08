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
