// Sources/PurahCore/Theme/PurahTypography.swift
import Foundation

public enum PurahTypography {
    /// Apple WWDC optical size-specific tracking (letter-spacing)
    public static func opticalTracking(for size: Double) -> Double {
        if size >= 18.0 {
            return -0.40  // Large display headers & numbers
        } else if size >= 14.0 {
            return -0.20  // Section titles & card names
        } else if size <= 8.0 {
            return 0.35   // Micro badges, telemetry numbers, tiny caps
        } else if size <= 9.5 {
            return 0.20   // Captions, monospaced preview, process rows
        } else {
            return 0.00   // Body & standard text (10~13pt)
        }
    }
}
