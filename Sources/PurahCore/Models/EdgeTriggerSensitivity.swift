// Sources/PurahCore/Models/EdgeTriggerSensitivity.swift
import Foundation

public enum EdgeTriggerSensitivity: String, CaseIterable, Codable, Sendable {
    case agile = "agile"         // 80ms dwell, fast deep edge
    case balanced = "balanced"   // 150ms dwell or 60ms deep edge push (Recommended default)
    case cautious = "cautious"   // 250ms dwell (strict anti-accidental)

    public var displayName: String {
        switch self {
        case .agile: return "Agile (80ms)"
        case .balanced: return "Balanced (150ms · Recommended)"
        case .cautious: return "Cautious (250ms · Strict Anti-Accidental)"
        }
    }

    public var initialDwellSeconds: Double {
        switch self {
        case .agile: return 0.08
        case .balanced: return 0.15
        case .cautious: return 0.25
        }
    }

    public var deepEdgeDwellSeconds: Double {
        switch self {
        case .agile: return 0.03
        case .balanced: return 0.06
        case .cautious: return 0.12
        }
    }
}
