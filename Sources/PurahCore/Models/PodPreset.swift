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
        case .balanced: return "Balanced Ergonomics"
        case .sprintProductivity: return "Sprint Productivity"
        case .immersiveMultimedia: return "Immersive Media"
        }
    }

    public var defaultDescription: String {
        switch self {
        case .balanced: return "Balanced distribution. Timeline on right, shelf and notes on left, music on bottom."
        case .sprintProductivity: return "Dedicated left rail for stash and notes. Right rail focused on timeline and tasks."
        case .immersiveMultimedia: return "Minimalist calendar on right, dynamic audio wave meter on left."
        }
    }
}
