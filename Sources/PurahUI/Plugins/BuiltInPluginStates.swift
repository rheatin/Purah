// Sources/PurahUI/Plugins/BuiltInPluginStates.swift
import SwiftUI
import AppKit
import Foundation
import Observation
import EventKit
import PurahCore

// MARK: - Calendar Plugin State
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
            self.events = sample
            targetStore?._calendarEvents = sample
            self.save()
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
                self.events = deduplicated
                self.isUsingRealCalendar = true
                self.isSyncing = false
                self.save()
                if let targetStore = self.boundStore {
                    targetStore.calendarScope = currentScope
                    targetStore.isUsingRealCalendar = true
                    targetStore._calendarEvents = deduplicated
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

// MARK: - Todo Plugin State
@Observable
@MainActor
public final class TodoPluginState: Sendable {
    public var todos: [TodoItem]
    public var scope: RemindersScope
    public var isUsingRealReminders: Bool
    public var isSyncing: Bool
    public var maxRailTodos: Int
    public let storage: any PurahPluginStorage

    @ObservationIgnored private var reminderStoreObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    @ObservationIgnored private weak var boundStore: PurahWorkspaceStore?

    public var remindersScope: RemindersScope {
        get { scope }
        set { scope = newValue }
    }

    public init(storage: any PurahPluginStorage = ScopedPluginStorage(pluginId: "todo")) {
        self.storage = storage
        self.scope = storage.codable(forKey: "scope", as: RemindersScope.self) ?? .allIncomplete
        self.isUsingRealReminders = false
        self.isSyncing = false
        let savedMax = storage.int(forKey: "maxRailTodos")
        self.maxRailTodos = savedMax > 0 ? savedMax : 6
        self.todos = storage.codable(forKey: "todos", as: [TodoItem].self) ?? Self.defaultTodos()
    }

    public func load() {
        if let savedScope = storage.codable(forKey: "scope", as: RemindersScope.self) {
            self.scope = savedScope
        }
        let savedMax = storage.int(forKey: "maxRailTodos")
        if savedMax > 0 {
            self.maxRailTodos = savedMax
        }
        if let savedTodos = storage.codable(forKey: "todos", as: [TodoItem].self) {
            self.todos = savedTodos
        }
    }

    public func save() {
        storage.setCodable(scope, forKey: "scope")
        storage.set(maxRailTodos, forKey: "maxRailTodos")
        storage.setCodable(todos, forKey: "todos")
    }

    public func syncReminders(into store: PurahWorkspaceStore? = nil) async {
        if let store {
            self.boundStore = store
        }
        let targetStore = store ?? boundStore

        let status = PermissionManager.status(from: EKEventStore.authorizationStatus(for: .reminder))
        guard status.isGranted else {
            isUsingRealReminders = false
            targetStore?.isUsingRealReminders = false
            return
        }

        isSyncing = true
        let fetched = await SystemRemindersSyncService.shared.fetchReminders(scope: scope)
        self.todos = fetched
        self.isUsingRealReminders = true
        self.save()
        if let targetStore {
            targetStore.isUsingRealReminders = self.isUsingRealReminders
            targetStore._todos = self.todos
        }
        isSyncing = false
    }

    public func toggleCompletion(id: String, store: PurahWorkspaceStore? = nil) async {
        if let idx = todos.firstIndex(where: { $0.id == id }) {
            todos[idx].isCompleted.toggle()
            save()
        }
        let targetStore = store ?? boundStore
        if let targetStore {
            await SystemRemindersSyncService.shared.toggleCompletion(id: id, into: targetStore)
            if let idx = targetStore._todos.firstIndex(where: { $0.id == id }),
               let selfIdx = todos.firstIndex(where: { $0.id == id }) {
                todos[selfIdx].isCompleted = targetStore._todos[idx].isCompleted
            }
        }
    }

    public func updateTitle(id: String, title: String) {
        if let idx = todos.firstIndex(where: { $0.id == id }) {
            todos[idx].title = title
            save()
        }
        if let boundStore, let idx = boundStore._todos.firstIndex(where: { $0.id == id }) {
            boundStore._todos[idx].title = title
        }
    }

    public func add(todo: TodoItem) {
        todos.append(todo)
        save()
        boundStore?._todos.append(todo)
    }

    public func remove(id: String) {
        todos.removeAll { $0.id == id }
        save()
        boundStore?._todos.removeAll { $0.id == id }
    }

    public func mount(store: PurahWorkspaceStore) {
        self.boundStore = store
        if !store._todos.isEmpty && self.todos.isEmpty {
            self.todos = store._todos
        }
        if reminderStoreObserver == nil {
            reminderStoreObserver = NotificationCenter.default.addObserver(
                forName: .EKEventStoreChanged,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    await self?.syncReminders()
                }
            }
        }
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            await self?.syncReminders(into: store)
        }
    }

    public func unmount(store: PurahWorkspaceStore) {
        if let obs = reminderStoreObserver {
            NotificationCenter.default.removeObserver(obs)
            reminderStoreObserver = nil
        }
        syncTask?.cancel()
        syncTask = nil
        save()
        if boundStore === store {
            boundStore = nil
        }
    }

    public static func defaultTodos() -> [TodoItem] {
        [
            TodoItem(title: "Calibrate left tactile edge sensor", isCompleted: true),
            TodoItem(title: "Update energy waveform telemetry", isCompleted: false),
            TodoItem(title: "Verify multi-display adaptive layout", isCompleted: false),
            TodoItem(title: "Tune Fitts Law flick threshold filtering", isCompleted: false)
        ]
    }
}

// MARK: - Music Plugin State
@Observable
@MainActor
public final class MusicPluginState: Sendable {
    public var track: MusicTrackInfo
    public var railStyle: MusicRailStyle
    public var dynamicSubStyle: DynamicWaveformSubStyle
    public var rhythmOffsetMs: Double
    public var isWaveformAnimationEnabled: Bool
    public let storage: any PurahPluginStorage

    @ObservationIgnored private var appleMusicObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var spotifyObserver: (any NSObjectProtocol)?
    @ObservationIgnored private weak var boundStore: PurahWorkspaceStore?

    public var musicTrack: MusicTrackInfo {
        get { track }
        set { track = newValue }
    }

    public var isMusicWaveformAnimationEnabled: Bool {
        get { isWaveformAnimationEnabled }
        set { isWaveformAnimationEnabled = newValue }
    }

    public var isPlaying: Bool {
        get { track.isPlaying }
        set { track.isPlaying = newValue }
    }

    public var waveformSamples: [Double] {
        get { track.waveformSamples }
        set { track.waveformSamples = newValue }
    }

    public init(storage: any PurahPluginStorage = ScopedPluginStorage(pluginId: "music")) {
        self.storage = storage
        self.railStyle = storage.codable(forKey: "railStyle", as: MusicRailStyle.self) ?? .dynamicWaveform
        self.dynamicSubStyle = storage.codable(forKey: "dynamicSubStyle", as: DynamicWaveformSubStyle.self) ?? .neonVUTower
        self.rhythmOffsetMs = max(storage.double(forKey: "rhythmOffsetMs"), 0.0)
        self.isWaveformAnimationEnabled = storage.codable(forKey: "isWaveformAnimationEnabled", as: Bool.self) ?? true
        var loadedTrack = storage.codable(forKey: "lastTrack", as: MusicTrackInfo.self) ?? MusicTrackInfo()
        loadedTrack.isPlaying = false
        loadedTrack.playbackRate = 0.0
        self.track = loadedTrack
    }

    public func load() {
        if let style = storage.codable(forKey: "railStyle", as: MusicRailStyle.self) {
            self.railStyle = style
        }
        if let sub = storage.codable(forKey: "dynamicSubStyle", as: DynamicWaveformSubStyle.self) {
            self.dynamicSubStyle = sub
        }
        self.rhythmOffsetMs = max(storage.double(forKey: "rhythmOffsetMs"), 0.0)
        if let anim = storage.codable(forKey: "isWaveformAnimationEnabled", as: Bool.self) {
            self.isWaveformAnimationEnabled = anim
        }
        if var savedTrack = storage.codable(forKey: "lastTrack", as: MusicTrackInfo.self) {
            savedTrack.isPlaying = false
            savedTrack.playbackRate = 0.0
            self.track = savedTrack
        }
    }

    public func save() {
        storage.setCodable(railStyle, forKey: "railStyle")
        storage.setCodable(dynamicSubStyle, forKey: "dynamicSubStyle")
        storage.set(rhythmOffsetMs, forKey: "rhythmOffsetMs")
        storage.setCodable(isWaveformAnimationEnabled, forKey: "isWaveformAnimationEnabled")
        storage.setCodable(track, forKey: "lastTrack")
    }

    public func togglePlayPause(store: PurahWorkspaceStore? = nil) {
        let targetStore = store ?? boundStore
        if let targetStore {
            SystemMusicSyncService.shared.togglePlayPause(store: targetStore)
            self.track = targetStore._musicTrack
            self.isPlaying = targetStore._musicTrack.isPlaying
        } else {
            let frozenTime = track.calculatedCurrentTime
            let nowPlaying = !track.isPlaying
            let totalSec = max(track.durationSeconds, 1.0)
            track.currentPositionSeconds = frozenTime
            track.playbackProgress = min(max(frozenTime / totalSec, 0.0), 1.0)
            track.isPlaying = nowPlaying
            track.playbackRate = nowPlaying ? 1.0 : 0.0
            track.lastUpdated = Date()
            self.isPlaying = nowPlaying
        }
    }

    public func nextTrack(store: PurahWorkspaceStore? = nil) {
        let targetStore = store ?? boundStore
        SystemMusicSyncService.shared.nextTrack(store: targetStore)
    }

    public func previousTrack(store: PurahWorkspaceStore? = nil) {
        let targetStore = store ?? boundStore
        SystemMusicSyncService.shared.previousTrack(store: targetStore)
    }

    public func seek(to progress: Double, store: PurahWorkspaceStore? = nil) {
        let clamped = min(max(progress, 0.0), 1.0)
        let total = max(track.durationSeconds, 1.0)
        let targetSec = clamped * total
        track.currentPositionSeconds = targetSec
        track.lastUpdated = Date()
        track.playbackProgress = clamped

        let targetStore = store ?? boundStore
        if let targetStore {
            targetStore._musicTrack = track
        }
        SystemMusicSyncService.shared.seek(to: progress, store: targetStore)
    }

    public func update(from trackInfo: MusicTrackInfo) {
        self.track = trackInfo
        self.boundStore?._musicTrack = trackInfo
    }

    public func mount(store: PurahWorkspaceStore) {
        self.boundStore = store
        if !store._musicTrack.title.isEmpty {
            self.track = store._musicTrack
        }
        self.isWaveformAnimationEnabled = store.isMusicWaveformAnimationEnabled

        startListening()
        SystemMusicSyncService.shared.onTrackChanged = { [weak self] newTrack in
            self?.track = newTrack
        }
        SystemMusicSyncService.shared.startListening(into: store)

        // Initial fetch of artwork and local lyrics if not yet cached
        let currentTitle = self.track.title
        let currentArtist = self.track.artist
        let currentAlbum = self.track.album
        if self.track.artworkData == nil {
            Task { [weak self] in
                if let art = await SystemMusicSyncService.shared.fetchArtwork(title: currentTitle, artist: currentArtist, album: currentAlbum) {
                    await MainActor.run {
                        if self?.track.title == currentTitle {
                            self?.track.artworkData = art
                            self?.boundStore?._musicTrack.artworkData = art
                        }
                    }
                }
            }
        }
        if self.track.lyrics == nil {
            Task { [weak self] in
                if let lyrResult = await SystemMusicSyncService.shared.fetchOnlineLyrics(title: currentTitle, artist: currentArtist) {
                    await MainActor.run {
                        if self?.track.title == currentTitle {
                            self?.track.lyrics = lyrResult.plainLyrics
                            self?.track.syncedLyrics = lyrResult.syncedLyrics
                            self?.boundStore?._musicTrack.lyrics = lyrResult.plainLyrics
                            self?.boundStore?._musicTrack.syncedLyrics = lyrResult.syncedLyrics
                        }
                    }
                }
            }
        }
    }

    public func unmount(store: PurahWorkspaceStore) {
        stopListening()
        SystemMusicSyncService.shared.stopListening()
        SystemMusicSyncService.shared.onTrackChanged = nil
        SystemMusicSyncService.shared.clearArtworkCache()
        track.artworkData = nil
        track.lyrics = nil
        track.syncedLyrics = nil
        save()
        if boundStore === store {
            boundStore = nil
        }
    }

    private func startListening() {
        stopListening()
        let center = DistributedNotificationCenter.default()

        appleMusicObserver = center.addObserver(
            forName: NSNotification.Name("com.apple.Music.playerInfo"),
            object: nil,
            queue: .main
        ) { [weak self] notif in
            nonisolated(unsafe) let notification = notif
            MainActor.assumeIsolated {
                self?.handleAppleMusicNotification(notification)
            }
        }

        spotifyObserver = center.addObserver(
            forName: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil,
            queue: .main
        ) { [weak self] notif in
            nonisolated(unsafe) let notification = notif
            MainActor.assumeIsolated {
                self?.handleSpotifyNotification(notification)
            }
        }
    }

    private func stopListening() {
        let center = DistributedNotificationCenter.default()
        if let obs = appleMusicObserver {
            center.removeObserver(obs)
            appleMusicObserver = nil
        }
        if let obs = spotifyObserver {
            center.removeObserver(obs)
            spotifyObserver = nil
        }
    }

    private func handleAppleMusicNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo else { return }
        let playerState = userInfo["Player State"] as? String ?? ""
        let isPlaying = (playerState == "Playing")
        let title = userInfo["Name"] as? String ?? "Unknown Track"
        let artist = userInfo["Artist"] as? String ?? "Apple Music"
        let album = userInfo["Album"] as? String ?? ""

        let totalTimeMs = SystemMusicSyncService.extractNumericValue(from: userInfo["Total Time"]) ?? 180000.0
        let totalSec = max(totalTimeMs / 1000.0, 1.0)

        let isSameTrack = (self.track.title == title && self.track.artist == artist)
        let existingPos = self.track.calculatedCurrentTime

        let parsedPosSec = SystemMusicSyncService.extractNumericValue(from: userInfo["Player Position"])
        let currentPosSec: Double = {
            if let pos = parsedPosSec {
                if !isPlaying && pos == 0.0 && isSameTrack && existingPos > 1.0 {
                    return existingPos
                }
                return min(max(pos, 0.0), totalSec)
            } else if isSameTrack {
                return existingPos
            }
            return 0.0
        }()

        let progress = min(max(currentPosSec / totalSec, 0.0), 1.0)
        let samples: [Double] = (0..<14).map { _ in
            isPlaying ? Double.random(in: 0.25...0.95) : 0.15
        }

        // Retain existing artwork if same track, or check cache
        let existingArtwork: Data? = {
            if isSameTrack && self.track.artworkData != nil {
                return self.track.artworkData
            }
            return SystemMusicSyncService.shared.cachedArtwork(for: title, artist: artist)
        }()

        let existingLyrics: String? = {
            if isSameTrack && self.track.lyrics != nil {
                return self.track.lyrics
            }
            return nil
        }()

        self.track = MusicTrackInfo(
            title: title,
            artist: artist,
            album: album,
            isPlaying: isPlaying,
            playbackProgress: progress,
            currentPositionSeconds: currentPosSec,
            durationSeconds: totalSec,
            lastUpdated: Date(),
            playbackRate: isPlaying ? 1.0 : 0.0,
            waveformSamples: samples,
            artworkData: existingArtwork,
            lyrics: existingLyrics,
            sourceApp: "Apple Music",
            sourceBundleId: "com.apple.Music"
        )
        if let store = boundStore {
            store._musicTrack = self.track
        }

        // Fetch artwork if not cached
        if existingArtwork == nil {
            Task { [weak self] in
                if let art = await SystemMusicSyncService.shared.fetchArtwork(title: title, artist: artist, album: album) {
                    await MainActor.run {
                        if self?.track.title == title && self?.track.artist == artist {
                            self?.track.artworkData = art
                            if let store = self?.boundStore {
                                store._musicTrack.artworkData = art
                            }
                        }
                    }
                }
            }
        }

        // Fetch online lyrics
        if existingLyrics == nil {
            Task { [weak self] in
                if let lyrResult = await SystemMusicSyncService.shared.fetchOnlineLyrics(title: title, artist: artist) {
                    await MainActor.run {
                        if self?.track.title == title && self?.track.artist == artist {
                            self?.track.lyrics = lyrResult.plainLyrics
                            self?.track.syncedLyrics = lyrResult.syncedLyrics
                            if let store = self?.boundStore {
                                store._musicTrack.lyrics = lyrResult.plainLyrics
                                store._musicTrack.syncedLyrics = lyrResult.syncedLyrics
                            }
                        }
                    }
                }
            }
        }
    }

    private func handleSpotifyNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo else { return }
        let spotifyState = userInfo["Player State"] as? String ?? ""
        let isPlaying = (spotifyState == "Playing" || spotifyState == "kPSP")
        let title = userInfo["Name"] as? String ?? "Unknown Track"
        let artist = userInfo["Artist"] as? String ?? "Spotify"
        let album = userInfo["Album"] as? String ?? ""

        let durationMs = SystemMusicSyncService.extractNumericValue(from: userInfo["Duration"]) ?? 180000.0
        let durationSec = max(durationMs / 1000.0, 1.0)

        let isSameTrack = (self.track.title == title && self.track.artist == artist)
        let existingPos = self.track.calculatedCurrentTime

        let parsedPosSec = SystemMusicSyncService.extractNumericValue(from: userInfo["Playback Position"])
        let currentPosSec: Double = {
            if let pos = parsedPosSec {
                if !isPlaying && pos == 0.0 && isSameTrack && existingPos > 1.0 {
                    return existingPos
                }
                return min(max(pos, 0.0), durationSec)
            } else if isSameTrack {
                return existingPos
            }
            return 0.0
        }()

        let progress = min(max(currentPosSec / durationSec, 0.0), 1.0)
        let samples: [Double] = (0..<14).map { _ in
            isPlaying ? Double.random(in: 0.25...0.95) : 0.15
        }

        let existingArtwork: Data? = {
            if isSameTrack && self.track.artworkData != nil {
                return self.track.artworkData
            }
            return SystemMusicSyncService.shared.cachedArtwork(for: title, artist: artist)
        }()

        let existingLyrics: String? = {
            if isSameTrack && self.track.lyrics != nil {
                return self.track.lyrics
            }
            return nil
        }()

        self.track = MusicTrackInfo(
            title: title,
            artist: artist,
            album: album,
            isPlaying: isPlaying,
            playbackProgress: progress,
            currentPositionSeconds: currentPosSec,
            durationSeconds: durationSec,
            lastUpdated: Date(),
            playbackRate: isPlaying ? 1.0 : 0.0,
            waveformSamples: samples,
            artworkData: existingArtwork,
            lyrics: existingLyrics,
            sourceApp: "Spotify",
            sourceBundleId: "com.spotify.client"
        )
        if let store = boundStore {
            store._musicTrack = self.track
        }

        if existingArtwork == nil {
            Task { [weak self] in
                if let art = await SystemMusicSyncService.shared.fetchArtwork(title: title, artist: artist, album: album) {
                    await MainActor.run {
                        if self?.track.title == title && self?.track.artist == artist {
                            self?.track.artworkData = art
                            if let store = self?.boundStore {
                                store._musicTrack.artworkData = art
                            }
                        }
                    }
                }
            }
        }

        if existingLyrics == nil {
            Task { [weak self] in
                if let lyrResult = await SystemMusicSyncService.shared.fetchOnlineLyrics(title: title, artist: artist) {
                    await MainActor.run {
                        if self?.track.title == title && self?.track.artist == artist {
                            self?.track.lyrics = lyrResult.plainLyrics
                            self?.track.syncedLyrics = lyrResult.syncedLyrics
                            if let store = self?.boundStore {
                                store._musicTrack.lyrics = lyrResult.plainLyrics
                                store._musicTrack.syncedLyrics = lyrResult.syncedLyrics
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Drop Shelf Plugin State
@Observable
@MainActor
public final class ShelfPluginState: Sendable {
    public var files: [ShelfFileItem]
    public let storage: any PurahPluginStorage
    @ObservationIgnored private weak var boundStore: PurahWorkspaceStore?

    public var shelfFiles: [ShelfFileItem] {
        get { files }
        set { files = newValue }
    }

    public init(storage: any PurahPluginStorage = ScopedPluginStorage(pluginId: "shelf")) {
        self.storage = storage
        self.files = storage.codable(forKey: "stashedFiles", as: [ShelfFileItem].self) ?? Self.defaultFiles()
    }

    public func load() {
        if let saved = storage.codable(forKey: "stashedFiles", as: [ShelfFileItem].self) {
            self.files = saved
        }
    }

    public func save() {
        storage.setCodable(files, forKey: "stashedFiles")
    }

    public func addFile(url: URL) {
        let name = url.lastPathComponent
        let ext = url.pathExtension
        let attr = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attr?[.size] as? Int64) ?? 0
        let sizeDesc = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        let item = ShelfFileItem(
            name: name,
            sizeDescription: sizeDesc,
            fileExtension: ext,
            filePath: url.path
        )
        files.append(item)
        save()
        boundStore?._shelfFiles.append(item)
    }

    public func addFileItem(_ item: ShelfFileItem) {
        files.append(item)
        save()
        boundStore?._shelfFiles.append(item)
    }

    public func removeFile(id: String) {
        files.removeAll { $0.id == id }
        save()
        boundStore?._shelfFiles.removeAll { $0.id == id }
    }

    public func clear() {
        files.removeAll()
        save()
        boundStore?._shelfFiles.removeAll()
    }

    public func mount(store: PurahWorkspaceStore) {
        self.boundStore = store
        if !store._shelfFiles.isEmpty && self.files.isEmpty {
            self.files = store._shelfFiles
        }
    }

    public func unmount(store: PurahWorkspaceStore) {
        save()
        if boundStore === store {
            boundStore = nil
        }
    }

    public static func defaultFiles() -> [ShelfFileItem] {
        [
            ShelfFileItem(name: "macOS_Workflow_Spec.pdf", sizeDescription: "2.4 MB", fileExtension: "pdf"),
            ShelfFileItem(name: "Architecture_Diagram.png", sizeDescription: "4.8 MB", fileExtension: "png")
        ]
    }
}

// MARK: - Notes Plugin State
@Observable
@MainActor
public final class NotesPluginState: Sendable {
    public var noteContent: NoteContent
    public var documents: [NoteDocument]
    public var availableFolders: [String]
    public var selectedFolder: String
    public var selectedNoteId: String?
    public var isPreviewMode: Bool
    public let storage: any PurahPluginStorage
    public let fileStorage: PurahPluginFileStorage
    @ObservationIgnored private weak var boundStore: PurahWorkspaceStore?

    public var quickNote: NoteContent {
        get { noteContent }
        set { noteContent = newValue }
    }

    public var text: String {
        get { currentDocument?.content ?? noteContent.text }
        set {
            if let doc = currentDocument {
                updateNoteContent(id: doc.id, content: newValue)
            } else {
                updateText(newValue)
            }
        }
    }

    public var currentDocument: NoteDocument? {
        if let id = selectedNoteId, let matched = documents.first(where: { $0.id == id }) {
            return matched
        }
        let folderDocs = documentsInCurrentFolder
        return folderDocs.first ?? documents.first
    }

    public var documentsInCurrentFolder: [NoteDocument] {
        if selectedFolder == "All" {
            return documents
        }
        return documents.filter { $0.folder == selectedFolder }
    }

    public init(
        storage: any PurahPluginStorage = ScopedPluginStorage(pluginId: "notes"),
        fileStorage: PurahPluginFileStorage = PurahPluginFileStorage(pluginId: "notes")
    ) {
        self.storage = storage
        self.fileStorage = fileStorage

        let loadedFolders = storage.codable(forKey: "availableFolders", as: [String].self) ?? ["General", "Work", "Ideas", "Snippets"]
        self.availableFolders = loadedFolders
        self.selectedFolder = storage.string(forKey: "selectedFolder") ?? "General"
        self.isPreviewMode = storage.string(forKey: "isPreviewMode") != nil ? storage.bool(forKey: "isPreviewMode") : true

        // Load legacy single-note content if present
        let legacyContent: NoteContent = {
            if let saved = storage.codable(forKey: "noteContent", as: NoteContent.self) {
                return saved
            } else if let legacyText = UserDefaults.standard.string(forKey: "purah.quickNote.text") {
                let legacyMod = (UserDefaults.standard.object(forKey: "purah.quickNote.lastModified") as? Date) ?? Date()
                return NoteContent(text: legacyText, lastModified: legacyMod)
            } else {
                return NoteContent()
            }
        }()
        self.noteContent = legacyContent

        // Load multi-document collection from disk index.json
        let indexURL = fileStorage.dataDirectory.appendingPathComponent("index.json")
        var loadedDocs: [NoteDocument] = []
        if let data = try? Data(contentsOf: indexURL),
           let decoded = try? JSONDecoder().decode([NoteDocument].self, from: data) {
            loadedDocs = decoded
        }

        if loadedDocs.isEmpty {
            let initialDoc = NoteDocument(
                id: "initial-scratchpad",
                title: "Quick Scratchpad",
                folder: "General",
                content: legacyContent.text,
                timestamp: legacyContent.lastModified,
                isFavorite: false
            )
            loadedDocs = [initialDoc]
        }

        self.documents = loadedDocs
        self.selectedNoteId = loadedDocs.first?.id
    }

    public func load() {
        if let saved = storage.codable(forKey: "noteContent", as: NoteContent.self) {
            self.noteContent = saved
        }
        let indexURL = fileStorage.dataDirectory.appendingPathComponent("index.json")
        if let data = try? Data(contentsOf: indexURL),
           let decoded = try? JSONDecoder().decode([NoteDocument].self, from: data) {
            self.documents = decoded
        }
    }

    public func save() {
        saveToDisk()
    }

    public func saveToDisk() {
        storage.setCodable(noteContent, forKey: "noteContent")
        storage.setCodable(availableFolders, forKey: "availableFolders")
        storage.set(selectedFolder, forKey: "selectedFolder")
        storage.set(isPreviewMode, forKey: "isPreviewMode")

        // 1. Atomic index.json
        let indexURL = fileStorage.dataDirectory.appendingPathComponent("index.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        if let data = try? encoder.encode(documents) {
            try? data.write(to: indexURL, options: .atomic)
        }

        // 2. Physical Markdown files organized by folder
        for folder in availableFolders {
            let folderDir = fileStorage.dataDirectory.appendingPathComponent(folder, isDirectory: true)
            try? FileManager.default.createDirectory(at: folderDir, withIntermediateDirectories: true)
        }

        for doc in documents {
            let folderDir = fileStorage.dataDirectory.appendingPathComponent(doc.folder, isDirectory: true)
            try? FileManager.default.createDirectory(at: folderDir, withIntermediateDirectories: true)
            let safeTitle = doc.title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            let fileURL = folderDir.appendingPathComponent("\(safeTitle).md")
            try? doc.content.data(using: .utf8)?.write(to: fileURL, options: .atomic)
        }
    }

    public func updateText(_ newText: String) {
        noteContent.text = newText
        noteContent.lastModified = Date()

        if let doc = currentDocument {
            updateNoteContent(id: doc.id, content: newText)
        } else {
            saveToDisk()
            if let boundStore {
                boundStore._quickNote = noteContent
            }
        }
    }

    public func updateNoteContent(id: String, content: String) {
        guard let idx = documents.firstIndex(where: { $0.id == id }) else { return }
        documents[idx].content = content
        documents[idx].timestamp = Date()
        documents[idx].title = NoteDocument.deriveTitle(from: content, fallback: documents[idx].title)

        noteContent.text = content
        noteContent.lastModified = documents[idx].timestamp

        saveToDisk()
        if let boundStore {
            boundStore._quickNote = noteContent
        }
    }

    public func createNote(title: String? = nil, folder: String? = nil, content: String = "") -> NoteDocument {
        let targetFolder = folder ?? (selectedFolder == "All" ? "General" : selectedFolder)
        let docTitle = title ?? NoteDocument.deriveTitle(from: content, fallback: "New Note")
        let doc = NoteDocument(
            title: docTitle,
            folder: targetFolder,
            content: content,
            timestamp: Date(),
            isFavorite: false
        )
        documents.insert(doc, at: 0)
        selectedNoteId = doc.id
        selectedFolder = targetFolder
        noteContent.text = content
        noteContent.lastModified = doc.timestamp
        isPreviewMode = !content.isEmpty

        saveToDisk()
        if let boundStore {
            boundStore._quickNote = noteContent
        }
        return doc
    }

    public func deleteNote(id: String) {
        guard let idx = documents.firstIndex(where: { $0.id == id }) else { return }
        let removed = documents.remove(at: idx)

        // Remove disk file if it exists
        let safeTitle = removed.title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let fileURL = fileStorage.dataDirectory.appendingPathComponent(removed.folder).appendingPathComponent("\(safeTitle).md")
        try? FileManager.default.removeItem(at: fileURL)

        if selectedNoteId == id {
            selectedNoteId = documentsInCurrentFolder.first?.id ?? documents.first?.id
        }

        if let current = currentDocument {
            noteContent.text = current.content
            noteContent.lastModified = current.timestamp
        } else {
            noteContent.text = ""
        }

        saveToDisk()
        if let boundStore {
            boundStore._quickNote = noteContent
        }
    }

    public func toggleFavorite(id: String) {
        guard let idx = documents.firstIndex(where: { $0.id == id }) else { return }
        documents[idx].isFavorite.toggle()
        saveToDisk()
    }

    public func addFolder(_ folder: String) {
        let trimmed = folder.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !availableFolders.contains(trimmed) else { return }
        availableFolders.append(trimmed)
        let folderDir = fileStorage.dataDirectory.appendingPathComponent(trimmed, isDirectory: true)
        try? FileManager.default.createDirectory(at: folderDir, withIntermediateDirectories: true)
        saveToDisk()
    }

    public func deleteFolder(_ folder: String) {
        guard folder != "General", let idx = availableFolders.firstIndex(of: folder) else { return }
        availableFolders.remove(at: idx)

        // Relocate notes in deleted folder to General
        for i in documents.indices where documents[i].folder == folder {
            documents[i].folder = "General"
        }

        if selectedFolder == folder {
            selectedFolder = "General"
        }

        saveToDisk()
    }

    public func selectFolder(_ folder: String) {
        self.selectedFolder = folder
        if let firstInFolder = documentsInCurrentFolder.first {
            self.selectedNoteId = firstInFolder.id
        }
        saveToDisk()
    }

    public func clear() {
        if let doc = currentDocument {
            updateNoteContent(id: doc.id, content: "")
        } else {
            noteContent.text = ""
            noteContent.lastModified = Date()
            saveToDisk()
            if let boundStore {
                boundStore._quickNote = noteContent
            }
        }
    }

    public func mount(store: PurahWorkspaceStore) {
        self.boundStore = store
        if !store._quickNote.text.isEmpty && self.documents.isEmpty {
            _ = createNote(title: "Quick Scratchpad", folder: "General", content: store._quickNote.text)
        }
    }

    public func unmount(store: PurahWorkspaceStore) {
        saveToDisk()
        if boundStore === store {
            boundStore = nil
        }
    }

    // MARK: - Markdown Formatting Helpers
    public func toggleChecklist(at lineIndex: Int) {
        guard let doc = currentDocument else { return }
        let lines = doc.content.components(separatedBy: "\n")
        guard lines.indices.contains(lineIndex) else { return }

        var modifiedLines = lines
        let targetLine = lines[lineIndex]
        if targetLine.contains("- [ ] ") {
            modifiedLines[lineIndex] = targetLine.replacingOccurrences(of: "- [ ] ", with: "- [x] ")
        } else if targetLine.contains("- [x] ") {
            modifiedLines[lineIndex] = targetLine.replacingOccurrences(of: "- [x] ", with: "- [ ] ")
        }

        let newContent = modifiedLines.joined(separator: "\n")
        updateNoteContent(id: doc.id, content: newContent)
    }

    public func appendTextToCurrentDocument(_ snippet: String) {
        guard let doc = currentDocument else {
            _ = createNote(content: snippet)
            return
        }
        let updated = doc.content.isEmpty ? snippet : "\(doc.content)\n\n\(snippet)"
        updateNoteContent(id: doc.id, content: updated)
    }

    public static func applyLineReturn(lines: [String], at index: Int) -> (updatedLines: [String], nextActiveIndex: Int) {
        NoteDocument.applyLineReturn(lines: lines, at: index)
    }

    public static func applyLineEdit(lines: [String], at index: Int, newValue: String) -> (updatedLines: [String], nextActiveIndex: Int) {
        NoteDocument.applyLineEdit(lines: lines, at: index, newValue: newValue)
    }

    public static func applyBackspaceOnEmptyLine(lines: [String], at index: Int) -> (updatedLines: [String], nextActiveIndex: Int)? {
        NoteDocument.applyBackspaceOnEmptyLine(lines: lines, at: index)
    }
}

// MARK: - Vitals Plugin State
@Observable
@MainActor
public final class VitalsPluginState: Sendable {
    public var isDecomposed: Bool
    public var enabledMetrics: [VitalsMetricType]
    public var thresholds: VitalsColorThresholds
    public let storage: any PurahPluginStorage

    @ObservationIgnored private weak var boundStore: PurahWorkspaceStore?

    public var metrics: HardwareVitalsInfo {
        HardwareVitalsService.shared.metrics
    }

    public var cpuHistory: [VitalsHistoryPoint] { HardwareVitalsService.shared.cpuHistory }
    public var gpuHistory: [VitalsHistoryPoint] { HardwareVitalsService.shared.gpuHistory }
    public var ramHistory: [VitalsHistoryPoint] { HardwareVitalsService.shared.ramHistory }
    public var powerHistory: [VitalsHistoryPoint] { HardwareVitalsService.shared.powerHistory }
    public var networkHistory: [VitalsHistoryPoint] { HardwareVitalsService.shared.networkHistory }
    public var networkDownHistory: [VitalsHistoryPoint] { HardwareVitalsService.shared.networkDownHistory }
    public var networkUpHistory: [VitalsHistoryPoint] { HardwareVitalsService.shared.networkUpHistory }
    public var diskHistory: [VitalsHistoryPoint] { HardwareVitalsService.shared.diskHistory }

    public var isVitalsDecomposed: Bool {
        get { isDecomposed }
        set { isDecomposed = newValue }
    }

    public var vitalsEnabledMetrics: [VitalsMetricType] {
        get { enabledMetrics }
        set { enabledMetrics = newValue }
    }

    public var vitalsThresholds: VitalsColorThresholds {
        get { thresholds }
        set { thresholds = newValue }
    }

    public init(storage: any PurahPluginStorage = ScopedPluginStorage(pluginId: "vitals")) {
        self.storage = storage
        if storage.string(forKey: "isDecomposed") != nil {
            self.isDecomposed = storage.bool(forKey: "isDecomposed")
        } else {
            self.isDecomposed = true
        }
        self.enabledMetrics = storage.codable(forKey: "enabledMetrics", as: [VitalsMetricType].self) ?? [.cpu, .ram, .power, .disk]
        self.thresholds = storage.codable(forKey: "thresholds", as: VitalsColorThresholds.self) ?? VitalsColorThresholds()
    }

    public func history(for metric: VitalsMetricType) -> [VitalsHistoryPoint] {
        HardwareVitalsService.shared.history(for: metric)
    }

    public func load() {
        if storage.string(forKey: "isDecomposed") != nil {
            self.isDecomposed = storage.bool(forKey: "isDecomposed")
        } else {
            self.isDecomposed = true
        }
        if let metrics = storage.codable(forKey: "enabledMetrics", as: [VitalsMetricType].self) {
            self.enabledMetrics = metrics
        }
        if let thresh = storage.codable(forKey: "thresholds", as: VitalsColorThresholds.self) {
            self.thresholds = thresh
        }
    }

    public func save() {
        storage.set(isDecomposed, forKey: "isDecomposed")
        storage.setCodable(enabledMetrics, forKey: "enabledMetrics")
        storage.setCodable(thresholds, forKey: "thresholds")
    }

    public func startPolling(interval: TimeInterval = 1.0) {
        HardwareVitalsService.shared.startMonitoring(interval: interval)
    }

    public func stopPolling() {
        HardwareVitalsService.shared.stopMonitoring()
    }

    public func refreshMetrics(includeProcesses: Bool = false) {
        HardwareVitalsService.shared.refreshMetrics(includeProcesses: includeProcesses)
    }

    public func resetThresholds() {
        thresholds = VitalsColorThresholds()
        save()
        boundStore?._vitalsThresholds = thresholds
    }

    public func mount(store: PurahWorkspaceStore) {
        self.boundStore = store
        self.thresholds = store._vitalsThresholds
        self.isDecomposed = store._isVitalsDecomposed
        self.enabledMetrics = store._vitalsEnabledMetrics
        HardwareVitalsService.shared.startMonitoring()
    }

    public func unmount(store: PurahWorkspaceStore) {
        stopPolling()
        HardwareVitalsService.shared.stopMonitoring()
        save()
        if boundStore === store {
            boundStore = nil
        }
    }
}

// MARK: - Scripts Plugin State
@Observable
@MainActor
public final class ScriptsPluginState: Sendable {
    public var isDecomposed: Bool
    public var enabledActionIds: [String]
    public var actions: [ScriptActionItem]
    public var lastOutput: String?
    public var isRunning: Bool
    public var lastExecutedActionId: String?
    public let storage: any PurahPluginStorage

    @ObservationIgnored private weak var boundStore: PurahWorkspaceStore?

    public var enabledActions: [ScriptActionItem] {
        if enabledActionIds.isEmpty {
            return actions
        }
        return actions.filter { enabledActionIds.contains($0.id) }
    }

    public var isScriptsDecomposed: Bool {
        get { isDecomposed }
        set { isDecomposed = newValue }
    }

    public var scriptsEnabledActionIds: [String] {
        get { enabledActionIds }
        set { enabledActionIds = newValue }
    }

    public var scriptsEnabledActions: [ScriptActionItem] {
        enabledActions
    }

    public init(storage: any PurahPluginStorage = ScopedPluginStorage(pluginId: "scripts")) {
        self.storage = storage
        if storage.string(forKey: "isDecomposed") != nil {
            self.isDecomposed = storage.bool(forKey: "isDecomposed")
        } else {
            self.isDecomposed = true
        }
        self.enabledActionIds = storage.codable(forKey: "enabledActionIds", as: [String].self) ?? []
        self.actions = storage.codable(forKey: "actions", as: [ScriptActionItem].self) ?? ScriptRunwayService.shared.actions
        self.lastOutput = nil
        self.isRunning = false
        self.lastExecutedActionId = nil
    }

    public func load() {
        if storage.string(forKey: "isDecomposed") != nil {
            self.isDecomposed = storage.bool(forKey: "isDecomposed")
        } else {
            self.isDecomposed = true
        }
        if let ids = storage.codable(forKey: "enabledActionIds", as: [String].self) {
            self.enabledActionIds = ids
        }
        if let savedActions = storage.codable(forKey: "actions", as: [ScriptActionItem].self) {
            self.actions = savedActions
        }
    }

    public func save() {
        storage.set(isDecomposed, forKey: "isDecomposed")
        storage.setCodable(enabledActionIds, forKey: "enabledActionIds")
        storage.setCodable(actions, forKey: "actions")
    }

    public func action(for id: String) -> ScriptActionItem? {
        actions.first(where: { $0.id == id })
    }

    public func addAction(_ action: ScriptActionItem) {
        actions.append(action)
        if !enabledActionIds.isEmpty {
            enabledActionIds.append(action.id)
        }
        save()
        ScriptRunwayService.shared.addAction(action)
        boundStore?._scriptsEnabledActionIds = enabledActionIds
    }

    public func removeAction(id: String) {
        actions.removeAll { $0.id == id }
        enabledActionIds.removeAll { $0 == id }
        save()
        ScriptRunwayService.shared.removeAction(id: id)
        boundStore?._scriptsEnabledActionIds = enabledActionIds
    }

    public func updateAction(_ action: ScriptActionItem) {
        if let idx = actions.firstIndex(where: { $0.id == action.id }) {
            actions[idx] = action
            save()
        }
        ScriptRunwayService.shared.updateAction(action)
    }

    public func resetToDefaults() {
        ScriptRunwayService.shared.resetToDefaults()
        actions = ScriptRunwayService.shared.actions
        enabledActionIds = actions.map(\.id)
        save()
        boundStore?._scriptsEnabledActionIds = enabledActionIds
    }

    public func executeAction(_ action: ScriptActionItem, store: PurahWorkspaceStore? = nil) async -> (success: Bool, message: String) {
        isRunning = true
        lastExecutedActionId = action.id
        defer {
            isRunning = false
        }
        let result = await ScriptRunwayService.shared.executeAction(action)
        lastOutput = result.message
        return result
    }

    public func mount(store: PurahWorkspaceStore) {
        self.boundStore = store
        self.isDecomposed = store._isScriptsDecomposed
        if !store._scriptsEnabledActionIds.isEmpty {
            self.enabledActionIds = store._scriptsEnabledActionIds
        }
        if actions.isEmpty {
            actions = ScriptRunwayService.shared.actions
        }
    }

    public func unmount(store: PurahWorkspaceStore) {
        save()
        if boundStore === store {
            boundStore = nil
        }
    }
}

// MARK: - Terminal Plugin State
@Observable
@MainActor
public final class TerminalPluginState: Sendable {
    public var fontFamily: String
    public var fontSize: Double
    public let storage: any PurahPluginStorage
    @ObservationIgnored private weak var boundStore: PurahWorkspaceStore?

    public var terminalFontFamily: String {
        get { fontFamily }
        set { fontFamily = newValue }
    }

    public var terminalFontSize: Double {
        get { fontSize }
        set { fontSize = newValue }
    }

    public var shellName: String {
        TerminalManager.shared.shellName
    }

    public var isProcessRunning: Bool {
        TerminalManager.shared.isProcessRunning
    }

    public init(storage: any PurahPluginStorage = ScopedPluginStorage(pluginId: "terminal")) {
        self.storage = storage
        self.fontFamily = storage.string(forKey: "fontFamily") ?? "Auto (Nerd Font)"
        let savedSize = storage.double(forKey: "fontSize")
        self.fontSize = savedSize > 0 ? savedSize : 11.5
    }

    public func load() {
        if let font = storage.string(forKey: "fontFamily"), !font.isEmpty {
            self.fontFamily = font
        }
        let size = storage.double(forKey: "fontSize")
        if size > 0 {
            self.fontSize = size
        }
    }

    public func save() {
        storage.set(fontFamily, forKey: "fontFamily")
        storage.set(fontSize, forKey: "fontSize")
    }

    public func restartShell(palette: ThemePalette = ThemePalette.palette(for: .native)) {
        TerminalManager.shared.restartShell(
            fontFamily: fontFamily,
            fontSize: CGFloat(fontSize),
            palette: palette
        )
    }

    public func clearScreen() {
        TerminalManager.shared.clearScreen()
    }

    public func sendInterrupt() {
        TerminalManager.shared.sendInterrupt()
    }

    public func mount(store: PurahWorkspaceStore) {
        self.boundStore = store
        if !store._terminalFontFamily.isEmpty {
            self.fontFamily = store._terminalFontFamily
        }
        if store._terminalFontSize > 0 {
            self.fontSize = store._terminalFontSize
        }
    }

    public func unmount(store: PurahWorkspaceStore) {
        TerminalManager.shared.stopProcess()
        save()
        if boundStore === store {
            boundStore = nil
        }
    }
}

// MARK: - Clipboard Plugin State
@Observable
@MainActor
public final class ClipboardPluginState: Sendable {
    public var isDecomposed: Bool
    public var maxRailItems: Int
    public var retentionPeriod: ClipboardRetentionPeriod
    public var diskQuota: ClipboardDiskQuota
    public var autoPruneOnQuota: Bool
    public var items: [ClipboardItem]
    public let storage: any PurahPluginStorage
    @ObservationIgnored private weak var boundStore: PurahWorkspaceStore?

    public init(storage: any PurahPluginStorage = ScopedPluginStorage(pluginId: "clipboard")) {
        self.storage = storage
        if storage.string(forKey: "isDecomposed") != nil {
            self.isDecomposed = storage.bool(forKey: "isDecomposed")
        } else {
            self.isDecomposed = true // Default decomposed principle
        }
        let savedMax = storage.int(forKey: "maxRailItems")
        self.maxRailItems = (savedMax > 0) ? savedMax : 4

        let retention = storage.codable(forKey: "retentionPeriod", as: ClipboardRetentionPeriod.self) ?? .sevenDays
        let quota = storage.codable(forKey: "diskQuota", as: ClipboardDiskQuota.self) ?? .mb500
        let autoPrune = storage.string(forKey: "autoPruneOnQuota") != nil ? storage.bool(forKey: "autoPruneOnQuota") : true

        self.retentionPeriod = retention
        self.diskQuota = quota
        self.autoPruneOnQuota = autoPrune
        self.items = SystemClipboardSyncService.shared.history

        // Configure underlying service with user preferences
        SystemClipboardSyncService.shared.retentionPeriod = retention
        SystemClipboardSyncService.shared.diskQuota = quota
        SystemClipboardSyncService.shared.autoPruneOnQuota = autoPrune

        // Purge legacy bloated JSON history from UserDefaults to release resident process memory
        storage.removeObject(forKey: "history")
    }

    public func mount(store: PurahWorkspaceStore) {
        self.boundStore = store
        store.clipboardMaxRailItems = self.maxRailItems

        SystemClipboardSyncService.shared.retentionPeriod = self.retentionPeriod
        SystemClipboardSyncService.shared.diskQuota = self.diskQuota
        SystemClipboardSyncService.shared.autoPruneOnQuota = self.autoPruneOnQuota
        SystemClipboardSyncService.shared.onQuotaWarning = { [weak store] msg in
            store?.onCapacityWarningToast?(msg)
        }

        // Lazy lifecycle: Only initiate pasteboard polling when the clipboard pod is active/enabled
        if store.pods.first(where: { $0.id == "clipboard" })?.isEnabled == true {
            SystemClipboardSyncService.shared.startListening()
        }
        SystemClipboardSyncService.shared.onItemAdded = { [weak self] _ in
            self?.items = SystemClipboardSyncService.shared.history
        }
        self.items = SystemClipboardSyncService.shared.history
    }

    public func unmount(store: PurahWorkspaceStore) {
        SystemClipboardSyncService.shared.stopListening()
        SystemClipboardSyncService.shared.onItemAdded = nil
        SystemClipboardSyncService.shared.onQuotaWarning = nil
        save()
        if boundStore === store {
            boundStore = nil
        }
    }

    public func save() {
        storage.set(isDecomposed, forKey: "isDecomposed")
        storage.set(maxRailItems, forKey: "maxRailItems")
        storage.setCodable(retentionPeriod, forKey: "retentionPeriod")
        storage.setCodable(diskQuota, forKey: "diskQuota")
        storage.set(autoPruneOnQuota, forKey: "autoPruneOnQuota")

        SystemClipboardSyncService.shared.retentionPeriod = self.retentionPeriod
        SystemClipboardSyncService.shared.diskQuota = self.diskQuota
        SystemClipboardSyncService.shared.autoPruneOnQuota = self.autoPruneOnQuota
    }

    public func toggleFavorite(id: String) {
        SystemClipboardSyncService.shared.toggleFavorite(id: id)
        self.items = SystemClipboardSyncService.shared.history
    }

    public func togglePin(id: String) {
        toggleFavorite(id: id)
    }

    public func moveItem(from sourceIndex: Int, to destinationIndex: Int) {
        SystemClipboardSyncService.shared.moveItem(from: sourceIndex, to: destinationIndex)
        self.items = SystemClipboardSyncService.shared.history
    }

    public func copyItem(_ item: ClipboardItem) {
        SystemClipboardSyncService.shared.copyToPasteboard(item)
    }

    public func deleteItem(id: String) {
        SystemClipboardSyncService.shared.deleteItem(id: id)
        self.items = SystemClipboardSyncService.shared.history
    }

    public func clearAll(keepFavorites: Bool = true) {
        SystemClipboardSyncService.shared.clearAll(keepFavorites: keepFavorites)
        self.items = SystemClipboardSyncService.shared.history
    }

    public func clearAll(keepPinned: Bool) {
        clearAll(keepFavorites: keepPinned)
    }
}
