// Sources/PurahCore/Models/MountEdge.swift
import Foundation

public enum MountEdge: String, Codable, Sendable, CaseIterable {
    case left
    case right

    public var opposite: MountEdge {
        switch self {
        case .left: return .right
        case .right: return .left
        }
    }
}
