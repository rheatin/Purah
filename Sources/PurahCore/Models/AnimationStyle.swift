// Sources/PurahCore/Models/AnimationStyle.swift
import Foundation

public enum AnimationStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case magneticCascade
    case minimal

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .magneticCascade: return "华丽磁吸体感 (默认 · 抽屉弹射+邻近凸出)"
        case .minimal: return "极简轻量 (仅抽屉弹出)"
        }
    }
}
