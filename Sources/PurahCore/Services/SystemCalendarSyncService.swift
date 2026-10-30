// Sources/PurahCore/Services/SystemCalendarSyncService.swift
import Foundation
import EventKit
import Observation

@Observable
@MainActor
public final class SystemCalendarSyncService {
    public static let shared = SystemCalendarSyncService()

    private var eventStore: EKEventStore?
    @ObservationIgnored private var syncGeneration: UInt64 = 0
    public weak var boundStore: PurahWorkspaceStore?
    public private(set) var isSyncing: Bool = false
    public private(set) var lastSyncDate: Date?
    public private(set) var calendarCount: Int = 0

    /// Intentionally registers no `EKEventStoreChanged` observer.
    ///
    /// `CalendarPluginState` (the mounted pod) already observes that
    /// notification and owns the authoritative `events` array. Both sides used
    /// to observe it, so every calendar edit ran two EventKit queries and
    /// raced to write `store._calendarEvents`. The service stays a query layer
    /// driven by explicit `syncEvents(into:)` calls.
    public init() {}

    /// Refreshes the underlying EventStore so permission changes take effect immediately
    public func resetStore() {
        self.eventStore = nil
    }

    /// Calculates normalized day elapsed progress (0.0 to 1.0)
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

    public func syncEvents(into store: PurahWorkspaceStore? = nil, scope: CalendarTimeScope? = nil) {
        if let store = store {
            self.boundStore = store
        }
        let targetStore = store ?? self.boundStore

        let status = PermissionManager.status(from: EKEventStore.authorizationStatus(for: .event))
        guard status.isGranted else {
            targetStore?.isUsingRealCalendar = false
            return
        }

        isSyncing = true
        let targetScope = scope ?? targetStore?.calendarScope ?? .today
        let interval = targetScope.dateInterval(from: Date())

        syncGeneration &+= 1
        let currentGen = syncGeneration

        Task.detached(priority: .userInitiated) { [weak self] in
            let backgroundStore = EKEventStore()
            backgroundStore.refreshSourcesIfNecessary()

            let allCalendars = backgroundStore.calendars(for: .event)
            let predicate = backgroundStore.predicateForEvents(
                withStart: interval.start,
                end: interval.end,
                calendars: allCalendars.isEmpty ? nil : allCalendars
            )
            let events = backgroundStore.events(matching: predicate)
            let deduplicated = Self.processEvents(events)

            await MainActor.run { [weak self] in
                guard let self = self else { return }
                guard currentGen == self.syncGeneration else { return }
                if let targetStore = self.boundStore {
                    targetStore.calendarScope = targetScope
                    targetStore.isUsingRealCalendar = true
                    targetStore._calendarEvents = deduplicated
                }
                self.calendarCount = allCalendars.count
                self.lastSyncDate = Date()
                self.isSyncing = false
            }
        }
    }

    /// Destinations Save can offer, with the system default first.
    ///
    /// The default is what a draft with no named calendar has always gone into,
    /// and that is not always the calendar the person expects — the card shows
    /// this list precisely so the target is never a surprise after the fact.
    public func writableContainerTitles() -> [String] {
        guard PermissionManager.status(from: EKEventStore.authorizationStatus(for: .event)).isGranted else {
            return []
        }
        let store = writableStore()
        let names = store.calendars(for: .event)
            .filter(\.allowsContentModifications)
            .map(\.title)
            .sorted()
        guard let fallback = store.defaultCalendarForNewEvents?.title, names.contains(fallback) else {
            return names
        }
        return [fallback] + names.filter { $0 != fallback }
    }

    /// Writes one event. The pod refreshes itself from `EKEventStoreChanged`,
    /// which `save(commit:)` posts, so nothing here touches `boundStore`.
    ///
    /// A named calendar that cannot be written to is an error, never a silent
    /// fallback to the default: saving a work meeting into a personal calendar
    /// is not what the person asked for, and they would find out weeks later.
    @discardableResult
    public func createEvent(
        title: String,
        start: Date,
        end: Date? = nil,
        allDay: Bool = false,
        notes: String? = nil,
        calendarTitle: String? = nil
    ) throws -> String {
        guard PermissionManager.status(from: EKEventStore.authorizationStatus(for: .event)).isGranted else {
            throw AIActionWriteError.accessDenied
        }

        let store = writableStore()
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = end ?? start.addingTimeInterval(allDay ? 86_400 : 3600)
        event.isAllDay = allDay
        event.notes = notes

        let calendars = store.calendars(for: .event).filter(\.allowsContentModifications)
        if let calendarTitle, !calendarTitle.isEmpty {
            let match = calendars.first {
                $0.title.compare(calendarTitle, options: .caseInsensitive) == .orderedSame
            }
            guard let match else { throw AIActionWriteError.noWritableContainer(calendarTitle) }
            event.calendar = match
        } else {
            guard let fallback = store.defaultCalendarForNewEvents ?? calendars.first else {
                throw AIActionWriteError.noWritableContainer(nil)
            }
            event.calendar = fallback
        }

        do {
            try store.save(event, span: .thisEvent, commit: true)
        } catch {
            throw AIActionWriteError.saveFailed(error.localizedDescription)
        }
        return event.eventIdentifier ?? ""
    }

    private func writableStore() -> EKEventStore {
        if let eventStore { return eventStore }
        let store = EKEventStore()
        eventStore = store
        return store
    }

    nonisolated public static func processEvents(_ events: [EKEvent]) -> [CalendarEventItem] {
        let mapped = events.map { ekEvent in
            var extractedURL = ekEvent.url
            if extractedURL == nil {
                let textToScan = "\(ekEvent.notes ?? "") \(ekEvent.location ?? "")"
                extractedURL = extractFirstURL(from: textToScan)
            }

            // Construct guaranteed unique ID per occurrence for recurring events
            let baseId = ekEvent.eventIdentifier ?? UUID().uuidString
            let occurrenceTimestamp = Int(ekEvent.startDate.timeIntervalSince1970)
            let uniqueId = "\(baseId)_\(occurrenceTimestamp)"

            let cleanedNotes = ekEvent.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
            let validNotes = (cleanedNotes?.isEmpty == false) ? cleanedNotes : nil

            return CalendarEventItem(
                id: uniqueId,
                title: ekEvent.title ?? "Untitled Event",
                location: ekEvent.location ?? "Apple Calendar",
                calendarTitle: ekEvent.calendar?.title ?? "Calendar",
                colorHex: hexString(from: ekEvent.calendar?.cgColor),
                url: extractedURL,
                notes: validNotes,
                startTime: ekEvent.startDate,
                endTime: ekEvent.endDate,
                isAllDay: ekEvent.isAllDay
            )
        }

        // Deduplicate events by (normalized title + start timestamp) so synced accounts/invitations don't produce duplicate chips
        var seenKeys = Set<String>()
        return mapped
            .sorted(by: { $0.startTime < $1.startTime })
            .filter { event in
                seenKeys.insert("\(event.title.trimmingCharacters(in: .whitespacesAndNewlines))_\(Int(event.startTime.timeIntervalSince1970))").inserted
            }
    }

    nonisolated public static func hexString(from cgColor: CGColor?) -> String? {
        guard let cgColor, let components = cgColor.components, components.count >= 3 else {
            return nil
        }
        let r = Int(round(components[0] * 255.0))
        let g = Int(round(components[1] * 255.0))
        let b = Int(round(components[2] * 255.0))
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    nonisolated public static func extractFirstURL(from text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let matches = detector.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
        return matches.first?.url
    }
}
