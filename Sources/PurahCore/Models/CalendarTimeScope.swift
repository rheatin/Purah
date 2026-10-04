// Sources/PurahCore/Models/CalendarTimeScope.swift
import Foundation

public enum CalendarTimeScope: String, CaseIterable, Identifiable, Codable, Sendable {
    case today
    case thisWeek
    case thisMonth
    case next7Days

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .today: return "今日 (Day)"
        case .thisWeek: return "本周 (Week)"
        case .thisMonth: return "本月 (Month)"
        case .next7Days: return "未来7天 (7 Days)"
        }
    }

    public func dateInterval(from referenceDate: Date = Date()) -> DateInterval {
        let cal = Calendar.current
        let start = cal.startOfDay(for: referenceDate)
        switch self {
        case .today:
            let end = cal.date(byAdding: .day, value: 1, to: start) ?? start
            return DateInterval(start: start, end: end)
        case .thisWeek:
            let weekday = cal.component(.weekday, from: start)
            let daysToStart = (weekday == 1 ? -6 : 2 - weekday)
            let weekStart = cal.date(byAdding: .day, value: daysToStart, to: start) ?? start
            let weekEnd = cal.date(byAdding: .day, value: 7, to: weekStart) ?? start
            return DateInterval(start: weekStart, end: weekEnd)
        case .thisMonth:
            let components = cal.dateComponents([.year, .month], from: start)
            let monthStart = cal.date(from: components) ?? start
            let monthEnd = cal.date(byAdding: .month, value: 1, to: monthStart) ?? start
            return DateInterval(start: monthStart, end: monthEnd)
        case .next7Days:
            let end = cal.date(byAdding: .day, value: 7, to: start) ?? start
            return DateInterval(start: start, end: end)
        }
    }
}
