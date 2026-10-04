// Sources/PurahCore/Models/RemindersScope.swift
import Foundation

public enum RemindersScope: String, CaseIterable, Identifiable, Codable, Sendable {
    case allIncomplete
    case dueToday
    case dueThisWeek
    case completed

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .allIncomplete: return "全部未办"
        case .dueToday: return "今日到期"
        case .dueThisWeek: return "本周待办"
        case .completed: return "已完成"
        }
    }
}
