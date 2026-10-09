// Sources/PurahCore/Pods/CalendarPodModel.swift
import Foundation

public struct CalendarEventItem: Identifiable, Codable, Sendable {
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

    public var isPast: Bool {
        endTime < Date()
    }

    public var isOngoing: Bool {
        let now = Date()
        return now >= startTime && now <= endTime
    }

    public var isImminent: Bool {
        let now = Date()
        return now < startTime && startTime.timeIntervalSince(now) <= 900 // 15分钟内
    }
}
