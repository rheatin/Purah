// Sources/PurahCore/Models/EdgeTriggerSensitivity.swift
import Foundation

public enum EdgeTriggerSensitivity: String, CaseIterable, Codable, Sendable {
    case agile = "agile"         // 80ms dwell, 180ms exit grace, 260 pt/s push force
    case balanced = "balanced"   // 150ms dwell, 280ms exit grace, 36px barrier (Recommended default)
    case cautious = "cautious"   // 400ms dwell, 400ms exit grace, 52px barrier (Strict anti-accidental)
    case custom = "custom"       // Fine-tuned by calibration instrument (up to 1000ms)

    public var displayName: String {
        switch self {
        case .agile: return "Agile (Instant 0ms hover · 180ms grace)"
        case .balanced: return "Balanced (150ms dwell · 36px barrier · 280ms grace · Recommended)"
        case .cautious: return "Cautious (400ms dwell · 52px barrier · 400ms grace)"
        case .custom: return "Custom Calibration (0ms ~ 1000ms)"
        }
    }

    public var initialDwellSeconds: Double {
        switch self {
        case .agile: return 0.08
        case .balanced: return 0.15
        case .cautious: return 0.40
        case .custom: return 0.15
        }
    }

    public var deepEdgeDwellSeconds: Double {
        switch self {
        case .agile: return 0.03
        case .balanced: return 0.06
        case .cautious: return 0.12
        case .custom: return 0.06
        }
    }

    public var exitGraceDurationSeconds: Double {
        switch self {
        case .agile: return 0.18
        case .balanced: return 0.28
        case .cautious: return 0.40
        case .custom: return 0.28
        }
    }

    public var overshootCatchCorridor: Double {
        switch self {
        case .agile: return 35.0
        case .balanced: return 50.0
        case .cautious: return 65.0
        case .custom: return 50.0
        }
    }

    /// 边缘推力突破阈值 (横向压入像素速度 pt/s)
    public var pushForceThreshold: Double {
        switch self {
        case .agile: return 260.0
        case .balanced: return 380.0
        case .cautious: return 520.0
        case .custom: return 380.0
        }
    }

    /// 边缘推力阻力结界阈值 (Barrier/Loop 相对位移累加像素 px)
    public var pushResistanceBarrier: Double {
        switch self {
        case .agile: return 24.0      // 敏捷轻推即破
        case .balanced: return 36.0   // 稳健推力 (推荐默认)
        case .cautious: return 52.0   // 强阻力墙 (严苛防误触)
        case .custom: return 36.0
        }
    }
}
