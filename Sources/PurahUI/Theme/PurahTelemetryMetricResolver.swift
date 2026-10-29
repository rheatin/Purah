// Sources/PurahUI/Theme/PurahTelemetryMetricResolver.swift
import SwiftUI
import PurahCore

public enum PurahTelemetryMetricResolver: Sendable {
    // One definition of the brand palette: these are the plugin-facing names
    // for the same three colours `VitalsColorResolver` uses on the rail.
    public static let healthyGreen = VitalsColorResolver.healthyGreen
    public static let warningYellow = VitalsColorResolver.warningYellow
    public static let dangerRed = VitalsColorResolver.dangerRed

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
