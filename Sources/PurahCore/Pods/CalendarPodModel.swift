// Sources/PurahCore/Pods/CalendarPodModel.swift
import Foundation

public struct CalendarEventItem: Identifiable, Codable, Sendable {
    public let id: String
    public var title: String
    public var location: String
    public var calendarTitle: String
    public var colorHex: String?
    public var startTime: Date
    public var endTime: Date
    public var isAllDay: Bool

    public init(
        id: String = UUID().uuidString,
        title: String,
        location: String = "Apple 日历",
        calendarTitle: String = "默认日历",
        colorHex: String? = nil,
        startTime: Date,
        endTime: Date,
        isAllDay: Bool = false
    ) {
        self.id = id
        self.title = title
        self.location = location
        self.calendarTitle = calendarTitle
        self.colorHex = colorHex
        self.startTime = startTime
        self.endTime = endTime
        self.isAllDay = isAllDay
    }
}
