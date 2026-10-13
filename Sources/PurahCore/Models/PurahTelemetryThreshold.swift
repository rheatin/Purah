// Sources/PurahCore/Models/PurahTelemetryThreshold.swift
import Foundation

public enum TelemetryStatusLevel: String, Codable, Sendable {
    case normal
    case warning
    case danger
}

/// General threshold specification for any continuous metric, supporting warning and danger levels.
public struct PurahTelemetryThreshold: Codable, Sendable, Equatable {
    /// Value threshold triggering a warning status (e.g. 0.7 for 70% RAM, or 0.2 for 20% battery if inverted)
    public var warning: Double
    /// Value threshold triggering a danger/critical status (e.g. 0.85 for 85% RAM)
    public var danger: Double
    /// If true, lower values trigger warning/danger (e.g. battery level, remaining free disk space).
    public var isInverted: Bool

    public init(warning: Double, danger: Double, isInverted: Bool = false) {
        self.warning = warning
        self.danger = danger
        self.isInverted = isInverted
    }

    /// Evaluates value against threshold levels.
    public func status(for value: Double) -> TelemetryStatusLevel {
        if isInverted {
            if value <= danger { return .danger }
            if value <= warning { return .warning }
            return .normal
        } else {
            if value >= danger { return .danger }
            if value >= warning { return .warning }
            return .normal
        }
    }
}
