// Sources/PurahUI/Plugins/States/CalendarPluginState.swift
import SwiftUI
import AppKit
import Foundation
import Observation
import EventKit
import PurahCore

@Observable
@MainActor
public final class CalendarPluginState: Sendable {
    public var events: [CalendarEventItem]
    public var scope: CalendarTimeScope
    public var alertStyle: PluginAlertStyle
    public var alertLeadTime: CalendarAlertLeadTime
    public var dismissAlertOnHover: Bool
    public var isEventGlowAlertEnabled: Bool
    public var isEventToastAlertEnabled: Bool
    public var overflowStrategy: CalendarOverflowStrategy
    public var maxRailEvents: Int
    public var isUsingRealCalendar: Bool
    public var isSyncing: Bool
    public var acknowledgedAlertIds: Set<String>
    public var notifiedToastEventIds: Set<String>
    public var lastAlertTick: Date
    public let storage: any PurahPluginStorage

    @ObservationIgnored public var cachedSubItemHeaders: [(id: String, title: String)] = []
    @ObservationIgnored public var cacheTimestamp: TimeInterval = 0
    @ObservationIgnored private var eventStoreObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    @ObservationIgnored private weak var boundStore: PurahWorkspaceStore?

    public var calendarEvents: [CalendarEventItem] {
        get { events }
        set { events = newValue }
    }

    public var calendarScope: CalendarTimeScope {
        get { scope }
        set { scope = newValue }
    }

    public init(storage: any PurahPluginStorage = ScopedPluginStorage(pluginId: "calendar")) {
        self.storage = storage
        self.scope = storage.codable(forKey: "scope", as: CalendarTimeScope.self) ?? .today
        self.alertStyle = storage.codable(forKey: "alertStyle", as: PluginAlertStyle.self) ?? .subtleGlow
        self.alertLeadTime = storage.codable(forKey: "alertLeadTime", as: CalendarAlertLeadTime.self) ?? .fifteenMinutes
        self.dismissAlertOnHover = storage.bool(forKey: "dismissAlertOnHover")
        self.isEventGlowAlertEnabled = storage.codable(forKey: "isEventGlowAlertEnabled", as: Bool.self) ?? true
        self.isEventToastAlertEnabled = storage.codable(forKey: "isEventToastAlertEnabled", as: Bool.self) ?? true
        self.overflowStrategy = storage.codable(forKey: "overflowStrategy", as: CalendarOverflowStrategy.self) ?? .smartFold
        let savedMax = storage.int(forKey: "maxRailEvents")
        self.maxRailEvents = (savedMax > 0) ? savedMax : 4
        self.isUsingRealCalendar = false
        self.isSyncing = false
        self.acknowledgedAlertIds = []
        self.notifiedToastEventIds = []
        self.lastAlertTick = Date()
        self.events = storage.codable(forKey: "events", as: [CalendarEventItem].self) ?? Self.defaultEvents()
    }

    public func load() {
        if let savedScope = storage.codable(forKey: "scope", as: CalendarTimeScope.self) {
            self.scope = savedScope
        }
        if let savedStyle = storage.codable(forKey: "alertStyle", as: PluginAlertStyle.self) {
            self.alertStyle = savedStyle
        }
        if let savedLead = storage.codable(forKey: "alertLeadTime", as: CalendarAlertLeadTime.self) {
            self.alertLeadTime = savedLead
        }
        self.dismissAlertOnHover = storage.bool(forKey: "dismissAlertOnHover")
        if let glow = storage.codable(forKey: "isEventGlowAlertEnabled", as: Bool.self) {
            self.isEventGlowAlertEnabled = glow
        }
        if let toast = storage.codable(forKey: "isEventToastAlertEnabled", as: Bool.self) {
            self.isEventToastAlertEnabled = toast
        }
        if let savedStrategy = storage.codable(forKey: "overflowStrategy", as: CalendarOverflowStrategy.self) {
            self.overflowStrategy = savedStrategy
        }
        let savedMax = storage.int(forKey: "maxRailEvents")
        if savedMax > 0 {
            self.maxRailEvents = savedMax
        }
        if let savedEvents = storage.codable(forKey: "events", as: [CalendarEventItem].self) {
            self.events = savedEvents
        }
    }

    public func save() {
        storage.setCodable(scope, forKey: "scope")
        storage.setCodable(alertStyle, forKey: "alertStyle")
        storage.setCodable(alertLeadTime, forKey: "alertLeadTime")
        storage.set(dismissAlertOnHover, forKey: "dismissAlertOnHover")
        storage.setCodable(isEventGlowAlertEnabled, forKey: "isEventGlowAlertEnabled")
        storage.setCodable(isEventToastAlertEnabled, forKey: "isEventToastAlertEnabled")
        storage.setCodable(overflowStrategy, forKey: "overflowStrategy")
        storage.set(maxRailEvents, forKey: "maxRailEvents")
        storage.setCodable(events, forKey: "events")
    }

    public func isAlertAcknowledged(id: String) -> Bool {
        acknowledgedAlertIds.contains(id)
    }

    public func acknowledgeAlert(id: String) {
        acknowledgedAlertIds.insert(id)
    }

    public func resetAcknowledgedAlerts() {
        acknowledgedAlertIds.removeAll()
    }

    /// Background inspection driving live in-rail attention beacon glow and HUD toast notifications.
    /// Runs periodically without requiring UI interaction or app restarts.
    public func checkUpcomingAlerts(store: PurahWorkspaceStore? = nil, now: Date = Date()) {
        let targetStore = store ?? boundStore
        self.lastAlertTick = now

        for event in events {
            let isPast = event.endTime < now
            let isOngoing = (now >= event.startTime && now <= event.endTime)
            let isImminent = event.isImminent(leadTime: alertLeadTime, now: now)
            let isAcknowledged = isAlertAcknowledged(id: event.id) || (targetStore?.isAlertAcknowledged(id: event.id) ?? false)
            let isAlerting = (isOngoing || isImminent) && isEventGlowAlertEnabled && !isAcknowledged

            if isAlerting {
                if isEventToastAlertEnabled && !notifiedToastEventIds.contains(event.id) {
                    notifiedToastEventIds.insert(event.id)
                    let msg: String
                    if isOngoing {
                        msg = "📅 \(event.title) is starting now"
                    } else {
                        let mins = max(Int(ceil(event.startTime.timeIntervalSince(now) / 60.0)), 1)
                        if mins >= 60 {
                            let hours = max(Int(ceil(Double(mins) / 60.0)), 1)
                            msg = "📅 \(event.title) starts in \(hours)h"
                        } else {
                            msg = "📅 \(event.title) starts in \(mins)m"
                        }
                    }
                    targetStore?.postToastNotification(id: event.id, message: msg)
                }
            } else if isPast {
                notifiedToastEventIds.remove(event.id)
            }
        }
    }

    public func loadSampleEvents(into store: PurahWorkspaceStore? = nil) {
        let targetStore = store ?? boundStore
        let sample = Self.defaultEvents(for: self.scope)
        self.events = sample
        self.isUsingRealCalendar = false
        self.save()
        if let targetStore {
            targetStore.isUsingRealCalendar = false
            targetStore._calendarEvents = sample
            targetStore.invalidateLayoutCache()
            targetStore.onWindowsRebuildNeeded?()
        }
    }

    public func syncEvents(into store: PurahWorkspaceStore? = nil) {
        if let store {
            self.boundStore = store
        }
        let targetStore = store ?? boundStore

        isSyncing = true
        let currentScope = self.scope
        let interval = currentScope.dateInterval(from: Date())

        let status = PermissionManager.status(from: EKEventStore.authorizationStatus(for: .event))
        guard status.isGranted else {
            isUsingRealCalendar = false
            targetStore?.isUsingRealCalendar = false
            isSyncing = false
            let sample = Self.defaultEvents(for: currentScope)
            let previousIds = self.events.map(\.id)
            let newIds = sample.map(\.id)
            let hasChanged = previousIds != newIds
            self.events = sample
            targetStore?._calendarEvents = sample
            self.save()
            targetStore?.invalidateLayoutCache()
            if hasChanged {
                targetStore?.onWindowsRebuildNeeded?()
            }
            return
        }

        syncTask?.cancel()
        syncTask = Task.detached(priority: .userInitiated) { [weak self] in
            let backgroundStore = EKEventStore()
            backgroundStore.refreshSourcesIfNecessary()
            let allCalendars = backgroundStore.calendars(for: .event)
            let predicate = backgroundStore.predicateForEvents(
                withStart: interval.start,
                end: interval.end,
                calendars: allCalendars.isEmpty ? nil : allCalendars
            )
            let ekEvents = backgroundStore.events(matching: predicate)
            let deduplicated = SystemCalendarSyncService.processEvents(ekEvents)

            await MainActor.run { [weak self] in
                guard let self else { return }
                let previousIds = self.events.map(\.id)
                let newIds = deduplicated.map(\.id)
                let hasChanged = previousIds != newIds

                self.events = deduplicated
                self.isUsingRealCalendar = true
                self.isSyncing = false
                self.save()
                if let targetStore = self.boundStore {
                    targetStore.calendarScope = currentScope
                    targetStore.isUsingRealCalendar = true
                    targetStore._calendarEvents = deduplicated
                    targetStore.invalidateLayoutCache()
                    if hasChanged {
                        targetStore.onWindowsRebuildNeeded?()
                    }
                }
            }
        }
    }

    public func mount(store: PurahWorkspaceStore) {
        self.boundStore = store
        if !store._calendarEvents.isEmpty && self.events.isEmpty {
            self.events = store._calendarEvents
        }
        if eventStoreObserver == nil {
            eventStoreObserver = NotificationCenter.default.addObserver(
                forName: .EKEventStoreChanged,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.syncEvents()
                    self?.checkUpcomingAlerts()
                }
            }
        }
        syncEvents(into: store)
        checkUpcomingAlerts(store: store)
    }

    public func unmount(store: PurahWorkspaceStore) {
        if let obs = eventStoreObserver {
            NotificationCenter.default.removeObserver(obs)
            eventStoreObserver = nil
        }
        syncTask?.cancel()
        syncTask = nil
        save()
        if boundStore === store {
            boundStore = nil
        }
    }

    public static func defaultEvents(for scope: CalendarTimeScope = .today) -> [CalendarEventItem] {
        let cal = Calendar.current
        let today = Date()
        let d1 = cal.date(bySettingHour: 10, minute: 0, second: 0, of: today) ?? today
        let d2 = cal.date(bySettingHour: 11, minute: 30, second: 0, of: today) ?? today
        let d3 = cal.date(bySettingHour: 14, minute: 0, second: 0, of: today) ?? today
        let d4 = cal.date(bySettingHour: 15, minute: 0, second: 0, of: today) ?? today

        var list = [
            CalendarEventItem(id: "default-event-1", title: "Architecture Review", location: "Central Workshop", notes: "Review cross-process rail synchronization and zero-copy Metal framebuffer pipeline.", startTime: d1, endTime: d2),
            CalendarEventItem(id: "default-event-2", title: "Environmental Monitoring", location: "Observation Station", notes: "Inspect thermal dissipation logs, battery health stats, and ambient light sensors.", startTime: d3, endTime: d4)
        ]

        if scope == .next7Days || scope == .thisWeek || scope == .thisMonth {
            if let d5 = cal.date(byAdding: .day, value: 1, to: d1), let d6 = cal.date(byAdding: .day, value: 1, to: d2) {
                list.append(CalendarEventItem(id: "default-event-3", title: "Kernel Sprint Standup", location: "Design Lab", notes: "Daily sync on Mach kernel thread priority and AppKit window level management.", startTime: d5, endTime: d6))
            }
            if let d7 = cal.date(byAdding: .day, value: 2, to: d3), let d8 = cal.date(byAdding: .day, value: 2, to: d4) {
                list.append(CalendarEventItem(id: "default-event-4", title: "Purah Pad UI Polish", location: "Virtual Studio", url: URL(string: "https://zoom.us/j/999"), notes: "Refine spring deceleration curves, haptic feedback profiles, and safe edge corridors.", startTime: d7, endTime: d8))
            }
        }
        if scope == .thisMonth {
            if let d9 = cal.date(byAdding: .day, value: 10, to: d1), let d10 = cal.date(byAdding: .day, value: 10, to: d2) {
                list.append(CalendarEventItem(id: "default-event-5", title: "WWDC Keynote Debrief", location: "Apple Park", notes: "Deep dive on latest macOS ergonomics, system services, and dynamic attention APIs.", startTime: d9, endTime: d10))
            }
        }
        return list
    }
}
