// Sources/PurahCore/Models/EdgeTriggerSensitivity.swift
import Foundation

public enum EdgeTriggerSensitivity: String, CaseIterable, Codable, Sendable {
    case agile = "agile"         // 80ms dwell, 180ms exit grace
    case balanced = "balanced"   // 150ms dwell, 280ms exit grace (Recommended default)
    case cautious = "cautious"   // 250ms dwell, 400ms exit grace (Strict anti-accidental)
    case custom = "custom"       // Fine-tuned by calibration instrument

    public var displayName: String {
        switch self {
        case .agile: return "Agile (80ms dwell · 180ms grace)"
        case .balanced: return "Balanced (150ms dwell · 280ms grace · Recommended)"
        case .cautious: return "Cautious (250ms dwell · 400ms grace)"
        case .custom: return "Custom Calibration"
        }
    }

    public var initialDwellSeconds: Double {
        switch self {
        case .agile: return 0.08
        case .balanced: return 0.15
        case .cautious: return 0.25
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
}
