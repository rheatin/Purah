// Sources/PurahCore/Models/EdgeTriggerMode.swift
import Foundation

public enum EdgeTriggerMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case hoverDwell = "hoverDwell"
    case pushForce = "pushForce"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .hoverDwell: return "Hover Dwell"
        case .pushForce: return "Push Force"
        }
    }

    public var subtitle: String {
        switch self {
        case .hoverDwell: return "Rest on edge rail for dwell duration to open"
        case .pushForce: return "Thrust cursor firmly into bezel to pop open instantly"
        }
    }
}
