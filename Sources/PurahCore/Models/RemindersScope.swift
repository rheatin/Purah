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
        case .allIncomplete: return "All Incomplete"
        case .dueToday: return "Due Today"
        case .dueThisWeek: return "Due This Week"
        case .completed: return "Completed"
        }
    }
}
