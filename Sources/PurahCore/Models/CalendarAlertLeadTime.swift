// Sources/PurahCore/Models/CalendarAlertLeadTime.swift
import Foundation

/// User-configurable advance alert notice window before a calendar event begins.
public enum CalendarAlertLeadTime: String, CaseIterable, Identifiable, Codable, Sendable {
    case atEventTime = "atEventTime"
    case fiveMinutes = "5min"
    case fifteenMinutes = "15min"
    case thirtyMinutes = "30min"
    case oneHour = "1hour"
    case twoHours = "2hours"
    case fourHours = "4hours"
    case eightHours = "8hours"
    case sameDay = "sameDay"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .atEventTime: return "At event time (准时)"
        case .fiveMinutes: return "5 minutes before (提前5分钟)"
        case .fifteenMinutes: return "15 minutes before (提前15分钟)"
        case .thirtyMinutes: return "30 minutes before (提前30分钟)"
        case .oneHour: return "1 hour before (提前1小时)"
        case .twoHours: return "2 hours before (提前2小时)"
        case .fourHours: return "4 hours before (提前4小时)"
        case .eightHours: return "8 hours before (提前8小时)"
        case .sameDay: return "Day of event (当天)"
        }
    }

    /// Evaluates whether an event starting at `startTime` is within the alert window relative to `now`.
    public func isAlertWindow(startTime: Date, now: Date = Date()) -> Bool {
        guard now < startTime else { return false }
        switch self {
        case .atEventTime:
            return false
        case .fiveMinutes:
            return startTime.timeIntervalSince(now) <= 300
        case .fifteenMinutes:
            return startTime.timeIntervalSince(now) <= 900
        case .thirtyMinutes:
            return startTime.timeIntervalSince(now) <= 1800
        case .oneHour:
            return startTime.timeIntervalSince(now) <= 3600
        case .twoHours:
            return startTime.timeIntervalSince(now) <= 7200
        case .fourHours:
            return startTime.timeIntervalSince(now) <= 14400
        case .eightHours:
            return startTime.timeIntervalSince(now) <= 28800
        case .sameDay:
            let cal = Calendar.current
            return cal.isDate(startTime, inSameDayAs: now)
        }
    }
}
