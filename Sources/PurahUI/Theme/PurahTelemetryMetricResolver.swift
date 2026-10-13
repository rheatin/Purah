// Sources/PurahUI/Theme/PurahTelemetryMetricResolver.swift
import SwiftUI
import PurahCore

public enum PurahTelemetryMetricResolver: Sendable {
    public static let healthyGreen = Color(red: 0.0, green: 0.90, blue: 0.60)
    public static let warningYellow = Color(red: 1.0, green: 0.72, blue: 0.15)
    public static let dangerRed = Color(red: 1.0, green: 0.28, blue: 0.38)

    public static func color(for level: TelemetryStatusLevel, normalColor: Color? = nil) -> Color {
        switch level {
        case .normal:
            return normalColor ?? healthyGreen
        case .warning:
            return warningYellow
        case .danger:
            return dangerRed
        }
    }

    public static func color(
        for value: Double,
        threshold: PurahTelemetryThreshold,
        normalColor: Color? = nil
    ) -> Color {
        let level = threshold.status(for: value)
        return color(for: level, normalColor: normalColor)
    }
}
