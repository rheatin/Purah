// Sources/PurahUI/Theme/VitalsColorResolver.swift
import SwiftUI
import PurahCore

public enum VitalsColorResolver: Sendable {
    public static let healthyGreen = Color(red: 0.0, green: 0.90, blue: 0.60)
    public static let warningYellow = Color(red: 1.0, green: 0.72, blue: 0.15)
    public static let dangerRed = Color(red: 1.0, green: 0.28, blue: 0.38)

    /// The drawer's instrument hues, sampled from the approved Vitals mockups.
    /// They are the band's identity, not its health: the alert colours above
    /// still win on a threshold breach, which is why these sit slightly
    /// softer than the full-saturation alarm pair.
    public static let cpuIdentity = Color(red: 0.35, green: 0.78, blue: 0.98)
    public static let gpuIdentity = Color(red: 0.75, green: 0.45, blue: 0.95)
    public static let ramIdentity = Color(red: 1.00, green: 0.62, blue: 0.10)
    public static let networkIdentity = Color(red: 0.20, green: 0.82, blue: 0.55)
    public static let diskIdentity = Color(red: 1.00, green: 0.45, blue: 0.55)
    /// Power keeps the app's long-standing green: the mockup's battery band
    /// shares the network green, but the two bands sit in one drawer and a
    /// distinct green keeps them legible as separate instruments.
    public static let powerIdentity = healthyGreen
    /// A full battery is a good state, not a disabled control. The ribbon's
    /// third hue makes it read as an instrument alongside charging.
    public static let batteryFullIdentity = Color(red: 0.30, green: 0.85, blue: 0.90)

    public static func identityColor(for metric: VitalsMetricType) -> Color {
        switch metric {
        case .cpu: return cpuIdentity
        case .gpu: return gpuIdentity
        case .ram: return ramIdentity
        case .network: return networkIdentity
        case .disk: return diskIdentity
        case .power: return powerIdentity
        }
    }

    /// The drawer's ink: identity hue while healthy, alarm hue above a
    /// threshold. The rail bar and stepped chips read `statusColor(for:)`
    /// instead so their healthy state stays the single green they always had.
    public static func color(
        for metric: VitalsMetricType,
        vitals: HardwareVitalsInfo,
        thresholds: VitalsColorThresholds,
        palette: ThemePalette = ThemePalette.palette(for: .native)
    ) -> Color {
        let identity = identityColor(for: metric)
        let yellow = warningYellow
        let red = dangerRed

        switch metric {
        case .cpu:
            let u = vitals.cpuUsage
            if u > thresholds.cpuDanger { return red }
            if u > thresholds.cpuWarning { return yellow }
            return identity
        case .gpu:
            let u = vitals.gpuUsage
            if u > thresholds.gpuDanger { return red }
            if u > thresholds.gpuWarning { return yellow }
            return identity
        case .ram:
            let u = vitals.memoryUsage
            if u > thresholds.ramDanger { return red }
            if u > thresholds.ramWarning { return yellow }
            return identity
        case .power:
            if vitals.isCharging { return identity }
            let b = Double(vitals.batteryLevel) / 100.0
            if b <= thresholds.batteryLow / 2.0 { return red }
            if b <= thresholds.batteryLow { return yellow }
            return identity
        case .network:
            let totalMB = (vitals.networkDownSpeed + vitals.networkUpSpeed) / 1_048_576.0
            if totalMB > thresholds.networkDangerMB { return red }
            if totalMB > thresholds.networkWarningMB { return yellow }
            return identity
        case .disk:
            let total = vitals.diskTotalGB
            let free = vitals.diskFreeGB
            let usedRatio = total > 0 ? (total - free) / total : 0.5
            if usedRatio > thresholds.diskDanger { return red }
            if usedRatio > thresholds.diskWarning { return yellow }
            return identity
        }
    }

    /// The rail bar, header pill and stepped chips keep the original healthy
    /// green: only the drawer's own ink carries the instrument hues.
    public static func statusColor(
        for metric: VitalsMetricType,
        vitals: HardwareVitalsInfo,
        thresholds: VitalsColorThresholds,
        palette: ThemePalette = ThemePalette.palette(for: .native)
    ) -> Color {
        let green = healthyGreen
        let yellow = warningYellow
        let red = dangerRed

        switch metric {
        case .cpu:
            let u = vitals.cpuUsage
            if u > thresholds.cpuDanger { return red }
            if u > thresholds.cpuWarning { return yellow }
            return green
        case .gpu:
            let u = vitals.gpuUsage
            if u > thresholds.gpuDanger { return red }
            if u > thresholds.gpuWarning { return yellow }
            return green
        case .ram:
            let u = vitals.memoryUsage
            if u > thresholds.ramDanger { return red }
            if u > thresholds.ramWarning { return yellow }
            return green
        case .power:
            if vitals.isCharging { return green }
            let b = Double(vitals.batteryLevel) / 100.0
            if b <= thresholds.batteryLow / 2.0 { return red }
            if b <= thresholds.batteryLow { return yellow }
            return green
        case .network:
            let totalMB = (vitals.networkDownSpeed + vitals.networkUpSpeed) / 1_048_576.0
            if totalMB > thresholds.networkDangerMB { return red }
            if totalMB > thresholds.networkWarningMB { return yellow }
            return green
        case .disk:
            let total = vitals.diskTotalGB
            let free = vitals.diskFreeGB
            let usedRatio = total > 0 ? (total - free) / total : 0.5
            if usedRatio > thresholds.diskDanger { return red }
            if usedRatio > thresholds.diskWarning { return yellow }
            return green
        }
    }

    public static func overallVitalsColor(
        vitals: HardwareVitalsInfo,
        thresholds: VitalsColorThresholds,
        palette: ThemePalette = ThemePalette.palette(for: .native)
    ) -> Color {
        let green = healthyGreen
        let yellow = warningYellow
        let red = dangerRed

        let batteryRatio = Double(vitals.batteryLevel) / 100.0
        let totalNetMB = (vitals.networkDownSpeed + vitals.networkUpSpeed) / 1_048_576.0
        let diskRatio = vitals.diskTotalGB > 0 ? (vitals.diskTotalGB - vitals.diskFreeGB) / vitals.diskTotalGB : 0.5

        if vitals.cpuUsage > thresholds.cpuDanger ||
            vitals.gpuUsage > thresholds.gpuDanger ||
            vitals.memoryUsage > thresholds.ramDanger ||
            (!vitals.isCharging && batteryRatio <= thresholds.batteryLow / 2.0) ||
            totalNetMB > thresholds.networkDangerMB ||
            diskRatio > thresholds.diskDanger {
            return red
        }

        if vitals.cpuUsage > thresholds.cpuWarning ||
            vitals.gpuUsage > thresholds.gpuWarning ||
            vitals.memoryUsage > thresholds.ramWarning ||
            (!vitals.isCharging && batteryRatio <= thresholds.batteryLow) ||
            totalNetMB > thresholds.networkWarningMB ||
            diskRatio > thresholds.diskWarning {
            return yellow
        }

        return green
    }
}
