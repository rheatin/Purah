// Sources/PurahCore/Models/ZoneType.swift
import Foundation

public enum ZoneType: String, Codable, Sendable, CaseIterable, Comparable {
    case glance       // 0.0 ~ 0.20
    case goldenAction // 0.20 ~ 0.75
    case quickFlick   // 0.75 ~ 1.00

    public var rank: Int {
        switch self {
        case .glance: return 0
        case .goldenAction: return 1
        case .quickFlick: return 2
        }
    }

    public static func < (lhs: ZoneType, rhs: ZoneType) -> Bool {
        lhs.rank < rhs.rank
    }

    public var normalizedRange: ClosedRange<Double> {
        switch self {
        case .glance: return 0.0...0.20
        case .goldenAction: return 0.20...0.75
        case .quickFlick: return 0.75...1.00
        }
    }

    public var defaultLocalizedKey: String {
        switch self {
        case .glance: return "zone.glance"
        case .goldenAction: return "zone.goldenAction"
        case .quickFlick: return "zone.quickFlick"
        }
    }

    public static func zone(for normalizedY: Double) -> ZoneType {
        normalizedY < 0.20 ? .glance : (normalizedY < 0.75 ? .goldenAction : .quickFlick)
    }
}
