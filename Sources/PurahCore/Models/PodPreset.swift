// Sources/PurahCore/Models/PodPreset.swift
import Foundation

public enum PodPreset: String, Codable, Sendable, CaseIterable, Identifiable {
    case balanced
    case sprintProductivity
    case immersiveMultimedia

    public var id: String { rawValue }

    public var titleKey: String {
        switch self {
        case .balanced: return "preset.balanced.title"
        case .sprintProductivity: return "preset.sprint.title"
        case .immersiveMultimedia: return "preset.media.title"
        }
    }

    public var descKey: String {
        switch self {
        case .balanced: return "preset.balanced.desc"
        case .sprintProductivity: return "preset.sprint.desc"
        case .immersiveMultimedia: return "preset.media.desc"
        }
    }

    public var defaultTitle: String {
        switch self {
        case .balanced: return "均衡工学模式 (Balanced)"
        case .sprintProductivity: return "冲刺生产力模式 (Sprint)"
        case .immersiveMultimedia: return "沉浸多媒体模式 (Media)"
        }
    }

    public var defaultDescription: String {
        switch self {
        case .balanced: return "双侧平衡分布，日程居右中，待办与暂存架居左，音乐居右下"
        case .sprintProductivity: return "左侧全部分配给暂存架与便签，右侧集中周日程与待办"
        case .immersiveMultimedia: return "右侧极简日历，左侧音乐波形律动与快速通讯"
        }
    }
}
