// Sources/PurahCore/Models/VitalsTelemetryFormatter.swift
import Foundation

/// Presentation spacing styles for byte-rate telemetry readings.
public enum VitalsRateStyle: Sendable {
    /// Tight inline pill / sparkline readout: `"1.2M/s"`, `"512K/s"`, `"0B/s"`.
    case compact
    /// Spaced drawer label readout: `"1.2 MB/s"`, `"512 KB/s"`, `"0 B/s"`.
    case spaced
}

/// Single source of truth for Hardware Vitals telemetry formatting across
/// `PurahCore` and `PurahUI` (rail chips, focused column bands, and drawers).
public enum VitalsTelemetryFormatter {
    public static func formatRate(_ bytesPerSecond: Double, style: VitalsRateStyle = .compact) -> String {
        switch style {
        case .compact:
            if bytesPerSecond >= 1_048_576.0 {
                return String(format: "%.1fM/s", bytesPerSecond / 1_048_576.0)
            }
            if bytesPerSecond >= 1024.0 {
                return String(format: "%.0fK/s", bytesPerSecond / 1024.0)
            }
            return String(format: "%.0fB/s", bytesPerSecond)
        case .spaced:
            if bytesPerSecond >= 1_048_576.0 {
                return String(format: "%.1f MB/s", bytesPerSecond / 1_048_576.0)
            }
            if bytesPerSecond >= 1024.0 {
                return String(format: "%.0f KB/s", bytesPerSecond / 1024.0)
            }
            return String(format: "%.0f B/s", bytesPerSecond)
        }
    }

    /// Formats gigabytes while dropping trailing `.0` for whole numbers.
    public static func compactGB(_ value: Double) -> String {
        let tenths = (value * 10).rounded() / 10
        return tenths == tenths.rounded()
            ? String(format: "%.0f", tenths)
            : String(format: "%.1f", tenths)
    }

    /// Formats swap usage in megabytes (`"0"`, `"512M"`, `"1.5G"`).
    public static func compactSwap(_ megabytes: Double) -> String {
        if megabytes >= 1024 {
            return compactGB(megabytes / 1024) + "G"
        }
        if megabytes < 1 {
            return "0"
        }
        return "\(Int(megabytes))M"
    }

    /// Effective system power draw in watts, falling back to battery discharge
    /// when SMC system wattage is unavailable.
    public static func systemWatts(_ metrics: HardwareVitalsInfo) -> Double {
        if metrics.powerSystemWatts > 0 { return metrics.powerSystemWatts }
        if metrics.powerSource == "AC Power" { return 0 }
        return max(-metrics.batteryChargeWatts, 0)
    }
}
