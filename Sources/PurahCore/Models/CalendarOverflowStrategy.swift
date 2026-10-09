// Sources/PurahCore/Models/CalendarOverflowStrategy.swift
import Foundation

public enum CalendarOverflowStrategy: String, CaseIterable, Identifiable, Codable, Sendable {
    case smartFold = "smartFold"
    case continuousStream = "continuous"

    public var id: String { rawValue }

    @MainActor
    public var displayName: String {
        switch self {
        case .smartFold: return "calendar.overflow.smartFold".localized
        case .continuousStream: return "calendar.overflow.continuous".localized
        }
    }

    @MainActor
    public var subtitle: String {
        switch self {
        case .smartFold: return "calendar.overflow.smartFold.desc".localized
        case .continuousStream: return "calendar.overflow.continuous.desc".localized
        }
    }
}
