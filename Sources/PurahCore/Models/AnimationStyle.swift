// Sources/PurahCore/Models/AnimationStyle.swift
import Foundation

public enum AnimationStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case magneticCascade
    case minimal

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .magneticCascade: return "Magnetic Cascade"
        case .minimal: return "Minimal Dock"
        }
    }
}
