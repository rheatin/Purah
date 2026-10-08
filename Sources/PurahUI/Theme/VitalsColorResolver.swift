// Sources/PurahUI/Theme/VitalsColorResolver.swift
import SwiftUI
import PurahCore

public enum VitalsColorResolver: Sendable {
    public static let healthyGreen = Color(red: 0.0, green: 0.90, blue: 0.60)
    public static let warningYellow = Color(red: 1.0, green: 0.72, blue: 0.15)
    public static let dangerRed = Color(red: 1.0, green: 0.28, blue: 0.38)

    public static func color(
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
