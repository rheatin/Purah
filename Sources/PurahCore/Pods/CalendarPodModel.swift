// Sources/PurahCore/Pods/CalendarPodModel.swift
import Foundation

public struct CalendarEventItem: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public var title: String
    public var location: String
    public var calendarTitle: String
    public var colorHex: String?
    public var url: URL?
    public var notes: String?
    public var startTime: Date
    public var endTime: Date
    public var isAllDay: Bool

    public init(
        id: String = UUID().uuidString,
        title: String,
        location: String = "Apple Calendar",
        calendarTitle: String = "Calendar",
        colorHex: String? = nil,
        url: URL? = nil,
        notes: String? = nil,
        startTime: Date,
        endTime: Date,
        isAllDay: Bool = false
    ) {
        self.id = id
        self.title = title
        self.location = location
        self.calendarTitle = calendarTitle
        self.colorHex = colorHex
        self.url = url
        self.notes = notes
        self.startTime = startTime
        self.endTime = endTime
        self.isAllDay = isAllDay
    }

    /// "All Day", or "9:30 AM - 10:15 AM".
    ///
    /// The rail bar, the composite drawer and the stepped card each carried
    /// their own copy of this formatter, so changing the format in one left
    /// the other two showing something else for the same event.
    public var timeRangeLabel: String {
        if isAllDay { return "All Day" }
        let start = startTime.formatted(date: .omitted, time: .shortened)
        let end = endTime.formatted(date: .omitted, time: .shortened)
        return "\(start) - \(end)"
    }

    public var isPast: Bool {
        endTime < Date()
    }

    public var isOngoing: Bool {
        let now = Date()
        return now >= startTime && now <= endTime
    }

    public var isImminent: Bool {
        isImminent(leadTime: .fifteenMinutes)
    }

    public func isImminent(leadTime: CalendarAlertLeadTime, now: Date = Date()) -> Bool {
        leadTime.isAlertWindow(startTime: startTime, now: now)
    }
}

/// Shared "now as anchor" semantics for the rail chips, the agenda drawer, and
/// the +N overview: all-day events pin to the very top, the upcoming block
/// runs ascending (an ongoing event sorts first naturally — its startTime is
/// already in the past), and ended events roll to the bottom, newest-ended
/// first, so both sides of the boundary hug "now".
public enum CalendarOrdering {
    public static func railComparator(now: Date) -> (CalendarEventItem, CalendarEventItem) -> Bool {
        { a, b in
            if a.isAllDay != b.isAllDay { return a.isAllDay }
            if a.isAllDay && b.isAllDay { return a.startTime < b.startTime }
            let aPast = a.endTime < now
            let bPast = b.endTime < now
            if aPast != bPast { return !aPast }
            if aPast { return a.endTime > b.endTime }
            return a.startTime < b.startTime
        }
    }

    /// Splits at "now": upcoming ascending (ongoing & all-day included), ended
    /// descending. Both returned blocks are already boundary-hugging ordered.
    public static func splitByNow(
        _ events: [CalendarEventItem],
        now: Date = Date()
    ) -> (upcoming: [CalendarEventItem], ended: [CalendarEventItem]) {
        let upcoming = events
            .filter { $0.endTime >= now }
            .sorted { $0.startTime < $1.startTime }
        let ended = events
            .filter { $0.endTime < now }
            .sorted { $0.endTime > $1.endTime }
        return (upcoming, ended)
    }

    /// First event that has not ended — the scroll anchor for agenda views.
    public static func recentAnchorID(
        in events: [CalendarEventItem],
        now: Date = Date()
    ) -> String? {
        events.first(where: { $0.endTime >= now })?.id
    }

    /// Smart-fold slot allocation for decomposed rail chips: visible slots go
    /// to upcoming events first (all-day/ongoing on top, nearest first), any
    /// leftover slots take the most recently ended events as rolled-back
    /// history, and the overflow — far-future first, then older-ended — lands
    /// in the +N overview.
    public static func foldIntoRailSlots(
        _ events: [CalendarEventItem],
        slotCount: Int,
        now: Date = Date()
    ) -> (visible: [CalendarEventItem], overflow: [CalendarEventItem]) {
        guard slotCount > 0 else {
            return ([], events.sorted(by: railComparator(now: now)))
        }
        let (upcoming, ended) = splitByNow(events, now: now)
        let visibleUpcoming = Array(upcoming.prefix(slotCount))
        let pastSlots = max(slotCount - visibleUpcoming.count, 0)
        let visibleEnded = Array(ended.prefix(pastSlots))

        let visible = visibleUpcoming + visibleEnded
        let overflow = Array(upcoming.dropFirst(visibleUpcoming.count))
            + Array(ended.dropFirst(visibleEnded.count))
        return (visible, overflow)
    }
}
