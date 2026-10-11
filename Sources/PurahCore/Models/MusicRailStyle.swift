// Sources/PurahCore/Models/MusicRailStyle.swift
import Foundation

public enum MusicRailStyle: String, Codable, Sendable, CaseIterable {
    case minimalist = "minimalist"         // 1. 普通静止 Pod (极简纯净圆角胶囊)
    case smoothProgress = "smoothProgress" // 2. 60 FPS 平滑流淌进度条 (时间锚点无顿挫刷新)
    case dynamicWaveform = "dynamicWaveform" // 3. 动态律动音浪 (可进一步选择子方案)
}

public enum DynamicWaveformSubStyle: String, Codable, Sendable, CaseIterable {
    case neonVUTower = "neonVUTower"       // 1. 赛博霓虹电平塔 (Cyberpunk Neon VU Tower)
    case moltenPlasma = "moltenPlasma"     // 2. 熔融等离子光流 (Molten Plasma Surge)
    case auroraWave = "auroraWave"         // 3. 极光呼吸声波带 (Aurora Wave Ribbon)

    public var displayName: String {
        switch self {
        case .neonVUTower: return "Neon VU Tower"
        case .moltenPlasma: return "Molten Plasma"
        case .auroraWave: return "Aurora Wave"
        }
    }
}
