// Tests/PurahCoreTests/CalendarUpNextTests.swift
import Testing
import Foundation
@testable import PurahCore
@testable import PurahUI

@Suite("Calendar Up Next", .serialized)
@MainActor
struct CalendarUpNextTests {
    private func makeState(
        events: [CalendarEventItem],
        permissionStatus: @escaping @MainActor () -> AccessStatus = { .denied },
        eventFetcher: @escaping CalendarPluginState.EventFetcher = { _ in [] }
    ) -> CalendarPluginState {
        let state = CalendarPluginState(
            storage: ScopedPluginStorage(pluginId: "calendar_up_next_\(UUID().uuidString)"),
            permissionStatus: permissionStatus,
            eventFetcher: eventFetcher
        )
        state.events = events
        state.scope = .thisMonth
        return state
    }

    private func fixedNow() -> Date {
        Date(timeIntervalSince1970: 1_800_000_000)
    }

    private func event(
        id: String,
        title: String = "Meeting",
        start: Date,
        duration: TimeInterval = 1_800,
        isAllDay: Bool = false
    ) -> CalendarEventItem {
        CalendarEventItem(
            id: id,
            title: title,
            startTime: start,
            endTime: start.addingTimeInterval(duration),
            isAllDay: isAllDay
        )
    }

    @Test("An ongoing meeting wins over every future meeting")
    func ongoingWinsOverFuture() {
        let now = fixedNow()
        let ongoing = event(
            id: "ongoing",
            start: now.addingTimeInterval(-600),
            duration: 2_400
        )
        let future = event(id: "future", start: now.addingTimeInterval(300))
        let state = makeState(events: [future, ongoing])

        #expect(state.resolveUpNextEvent(now: now)?.id == ongoing.id)
    }

    @Test("Without an ongoing meeting, the earliest future meeting wins")
    func earliestFutureWins() {
        let now = fixedNow()
        let later = event(id: "later", start: now.addingTimeInterval(5_400))
        let sooner = event(id: "sooner", start: now.addingTimeInterval(900))
        let state = makeState(events: [later, sooner])

        #expect(state.resolveUpNextEvent(now: now)?.id == sooner.id)
    }

    @Test("All-day events remain listed but never become Up Next")
    func allDayNeverBecomesUpNext() {
        let now = fixedNow()
        let allDay = event(
            id: "all-day",
            start: now.addingTimeInterval(-3_600),
            duration: 7_200,
            isAllDay: true
        )
        let future = event(id: "future", start: now.addingTimeInterval(1_200))
        let state = makeState(events: [allDay, future])

        #expect(state.resolveUpNextEvent(now: now)?.id == future.id)

        state.events = [allDay]
        #expect(state.resolveUpNextEvent(now: now) == nil)
    }

    @Test("An empty calendar has no Up Next event")
    func emptyCalendarHasNoUpNext() {
        let state = makeState(events: [])
        #expect(state.resolveUpNextEvent(now: fixedNow()) == nil)
        #expect(state.upNextCountdownText(at: fixedNow()) == nil)
    }

    @Test("Countdown formatting covers sub-minute, minutes, hours, days, and now")
    func countdownFormatting() {
        let localization = LocalizationManager.shared
        let previous = localization.currentLanguage
        defer { localization.currentLanguage = previous }
        localization.currentLanguage = .english

        let now = fixedNow()
        func text(offset: TimeInterval, duration: TimeInterval = 1_800) -> String {
            CalendarPluginState.countdownText(
                for: event(id: "e", start: now.addingTimeInterval(offset), duration: duration),
                now: now
            )
        }

        #expect(text(offset: 30) == "in <1m")
        #expect(text(offset: 60) == "in 1m")
        #expect(text(offset: 3_600) == "in 1h")
        #expect(text(offset: 8_100) == "in 2h 15m")
        #expect(text(offset: 3 * 86_400) == "in 3d")
        #expect(text(offset: -60, duration: 3_600) == "now")
    }

    @Test("The rail puts Up Next first and sorts everything else by start time")
    func upNextLeadsRailOrdering() throws {
        let now = Date()
        let later = event(id: "later", start: now.addingTimeInterval(7_200))
        let sooner = event(id: "sooner", start: now.addingTimeInterval(3_600))
        let allDay = CalendarEventItem(
            id: "all-day",
            title: "All Day",
            startTime: Calendar.current.startOfDay(for: now),
            endTime: Calendar.current.startOfDay(for: now).addingTimeInterval(86_400),
            isAllDay: true
        )

        let state = makeState(events: [later, allDay, sooner])
        state.scope = .today
        state.isDecomposed = true
        state.maxRailEvents = 5

        let store = PurahWorkspaceStore(
            userDefaults: UserDefaults(suiteName: "calendar_up_next_store_\(UUID().uuidString)")!
        )
        store._calendarEvents = []
        let pod = try #require(store.pods.first(where: { $0.id == "calendar" }))
        let context = PurahPluginContext(
            pod: pod,
            edge: .right,
            railWidth: 8,
            slotHeight: 180,
            drawerWidth: 310,
            isExpanded: false,
            isPinned: false,
            accentColor: .orange,
            palette: ThemeManager.shared.palette,
            store: store,
            requestExpand: {},
            requestDismiss: {},
            togglePin: {}
        )

        let items = CalendarPlugin(state: state).steppedItems(context: context)
        #expect(items.map(\.id) == ["sooner", "all-day", "later"])
        #expect(items.first?.badge == CalendarPluginState.countdownText(for: sooner, now: Date()))
    }

    @Test("Proximity thresholds are normal over 30m, amber 10-30m, and alert under 10m")
    func proximityThresholdBoundaries() {
        let now = fixedNow()
        func status(minutes: Double) -> TelemetryStatusLevel {
            CalendarUpNextStyle.status(
                for: event(id: "e", start: now.addingTimeInterval(minutes * 60)),
                now: now
            )
        }

        #expect(status(minutes: 31) == .normal)
        #expect(status(minutes: 30) == .warning)
        #expect(status(minutes: 10) == .warning)
        #expect(status(minutes: 9.9) == .danger)
        #expect(status(minutes: 0) == .danger)
    }

    @Test("The alert check runs after sync and never repeats the same event id")
    func syncCompletionChecksAlertsOnce() async throws {
        let ongoing = event(
            id: "cold-start-meeting",
            title: "Cold Start Meeting",
            start: Date().addingTimeInterval(-60),
            duration: 3_600
        )
        let store = PurahWorkspaceStore(
            userDefaults: UserDefaults(suiteName: "calendar_up_next_alerts_\(UUID().uuidString)")!
        )
        var messages: [String] = []
        store.onCapacityWarningToast = { messages.append($0) }

        let state = CalendarPluginState(
            storage: ScopedPluginStorage(pluginId: "calendar_up_next_alerts_\(UUID().uuidString)"),
            permissionStatus: { .authorized },
            eventFetcher: { _ in [ongoing] }
        )
        state.mount(store: store)

        for _ in 0..<200 where messages.isEmpty {
            try await Task.sleep(for: .milliseconds(5))
        }

        #expect(messages.count == 1)
        #expect(messages.first?.contains(ongoing.title) == true)

        state.checkUpcomingAlerts(store: store)
        #expect(messages.count == 1, "the same event id must not notify twice")
        state.unmount(store: store)
    }
}
