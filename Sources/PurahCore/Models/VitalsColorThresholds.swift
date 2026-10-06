// Sources/PurahCore/Models/VitalsColorThresholds.swift
import Foundation

public struct VitalsColorThresholds: Codable, Sendable, Equatable {
    public var cpuWarning: Double = 0.50
    public var cpuDanger: Double = 0.80
    public var gpuWarning: Double = 0.50
    public var gpuDanger: Double = 0.80
    public var ramWarning: Double = 0.70
    public var ramDanger: Double = 0.85
    public var diskWarning: Double = 0.80
    public var diskDanger: Double = 0.90
    public var batteryLow: Double = 0.20
    public var networkWarningMB: Double = 10.0
    public var networkDangerMB: Double = 50.0

    public init(
        cpuWarning: Double = 0.50,
        cpuDanger: Double = 0.80,
        gpuWarning: Double = 0.50,
        gpuDanger: Double = 0.80,
        ramWarning: Double = 0.70,
        ramDanger: Double = 0.85,
        diskWarning: Double = 0.80,
        diskDanger: Double = 0.90,
        batteryLow: Double = 0.20,
        networkWarningMB: Double = 10.0,
        networkDangerMB: Double = 50.0
    ) {
        self.cpuWarning = cpuWarning
        self.cpuDanger = cpuDanger
        self.gpuWarning = gpuWarning
        self.gpuDanger = gpuDanger
        self.ramWarning = ramWarning
        self.ramDanger = ramDanger
        self.diskWarning = diskWarning
        self.diskDanger = diskDanger
        self.batteryLow = batteryLow
        self.networkWarningMB = networkWarningMB
        self.networkDangerMB = networkDangerMB
    }
}
