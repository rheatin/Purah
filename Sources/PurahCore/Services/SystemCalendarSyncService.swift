// Sources/PurahCore/Services/SystemCalendarSyncService.swift
import Foundation
import EventKit
import Observation

@Observable
public final class SystemCalendarSyncService: @unchecked Sendable {
    public static let shared = SystemCalendarSyncService()

    private var eventStore = EKEventStore()
    public private(set) var isSyncing: Bool = false
    public private(set) var lastSyncDate: Date?
    public private(set) var calendarCount: Int = 0

    public init() {
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.syncEvents(into: nil)
            }
        }
    }

    /// 刷新底层 EventStore，保证权限变动后立即生效
    public func resetStore() {
        self.eventStore = EKEventStore()
    }

    /// 计算当日时间流逝归一化进度 (0.0 ~ 1.0)
    public func todayProgress(referenceDate: Date = Date()) -> Double {
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: referenceDate)
        guard let endOfDay = cal.date(byAdding: .day, value: 1, to: startOfDay) else {
            return 0.5
        }
        let totalSeconds = endOfDay.timeIntervalSince(startOfDay)
        let elapsed = referenceDate.timeIntervalSince(startOfDay)
        return min(max(elapsed / totalSeconds, 0.0), 1.0)
    }

    public func syncEvents(into store: PurahWorkspaceStore?, scope: CalendarTimeScope? = nil) {
        eventStore.refreshSourcesIfNecessary()

        let status = PermissionManager.status(from: EKEventStore.authorizationStatus(for: .event))
        guard status.isGranted else {
            store?.isUsingRealCalendar = false
            return
        }

        isSyncing = true
        let targetScope = scope ?? store?.calendarScope ?? .today
        let interval = targetScope.dateInterval(from: Date())

        let allCalendars = eventStore.calendars(for: .event)
        self.calendarCount = allCalendars.count

        let predicate = eventStore.predicateForEvents(
            withStart: interval.start,
            end: interval.end,
            calendars: allCalendars.isEmpty ? nil : allCalendars
        )
        let events = eventStore.events(matching: predicate)

        let mapped = events.map { ekEvent in
            var extractedURL = ekEvent.url
            if extractedURL == nil {
                let textToScan = "\(ekEvent.notes ?? "") \(ekEvent.location ?? "")"
                extractedURL = Self.extractFirstURL(from: textToScan)
            }

            return CalendarEventItem(
                id: ekEvent.eventIdentifier ?? UUID().uuidString,
                title: ekEvent.title ?? "未命名日程",
                location: ekEvent.location ?? "Apple 日历",
                calendarTitle: ekEvent.calendar?.title ?? "日历",
                url: extractedURL,
                startTime: ekEvent.startDate,
                endTime: ekEvent.endDate,
                isAllDay: ekEvent.isAllDay
            )
        }

        if let store = store {
            store.calendarScope = targetScope
            store.isUsingRealCalendar = true
            store.calendarEvents = mapped.sorted { $0.startTime < $1.startTime }
        }

        lastSyncDate = Date()
        isSyncing = false
    }

    public static func extractFirstURL(from text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let matches = detector.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
        return matches.first?.url
    }
}
