// Sources/PurahCore/Models/MusicRailStyle.swift
import Foundation

public enum MusicRailStyle: String, Codable, Sendable, CaseIterable {
    case minimalist = "minimalist"         // 1. Static Ambient Pod (minimalist clean rounded capsule)
    case smoothProgress = "smoothProgress" // 2. 60 FPS silky smooth progress bar (time-anchor monotonic refresh)
    case dynamicWaveform = "dynamicWaveform" // 3. Dynamic rhythm wave (with configurable sub-styles)
}

public enum DynamicWaveformSubStyle: String, Codable, Sendable, CaseIterable {
    case neonVUTower = "neonVUTower"       // 1. Cyberpunk Neon VU Tower
    case auroraWave = "auroraWave"         // 2. Aurora Wave Ribbon

    public var displayName: String {
        switch self {
        case .neonVUTower: return "Neon VU Tower"
        case .auroraWave: return "Aurora Wave"
        }
    }
}
