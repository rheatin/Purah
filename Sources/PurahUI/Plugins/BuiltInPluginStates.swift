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
    public var dismissAlertOnHover: Bool
    public var isEventGlowAlertEnabled: Bool
    public var isEventToastAlertEnabled: Bool
    public var isUsingRealCalendar: Bool
    public var isSyncing: Bool
    public var acknowledgedAlertIds: Set<String>
    public let storage: any PurahPluginStorage

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
        self.dismissAlertOnHover = storage.bool(forKey: "dismissAlertOnHover")
        self.isEventGlowAlertEnabled = storage.codable(forKey: "isEventGlowAlertEnabled", as: Bool.self) ?? true
        self.isEventToastAlertEnabled = storage.codable(forKey: "isEventToastAlertEnabled", as: Bool.self) ?? true
        self.isUsingRealCalendar = false
        self.isSyncing = false
        self.acknowledgedAlertIds = []
        self.events = storage.codable(forKey: "events", as: [CalendarEventItem].self) ?? Self.defaultEvents()
    }

    public func load() {
        if let savedScope = storage.codable(forKey: "scope", as: CalendarTimeScope.self) {
            self.scope = savedScope
        }
        if let savedStyle = storage.codable(forKey: "alertStyle", as: PluginAlertStyle.self) {
            self.alertStyle = savedStyle
        }
        self.dismissAlertOnHover = storage.bool(forKey: "dismissAlertOnHover")
        if let glow = storage.codable(forKey: "isEventGlowAlertEnabled", as: Bool.self) {
            self.isEventGlowAlertEnabled = glow
        }
        if let toast = storage.codable(forKey: "isEventToastAlertEnabled", as: Bool.self) {
            self.isEventToastAlertEnabled = toast
        }
        if let savedEvents = storage.codable(forKey: "events", as: [CalendarEventItem].self) {
            self.events = savedEvents
        }
    }

    public func save() {
        storage.setCodable(scope, forKey: "scope")
        storage.setCodable(alertStyle, forKey: "alertStyle")
        storage.set(dismissAlertOnHover, forKey: "dismissAlertOnHover")
        storage.setCodable(isEventGlowAlertEnabled, forKey: "isEventGlowAlertEnabled")
        storage.setCodable(isEventToastAlertEnabled, forKey: "isEventToastAlertEnabled")
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

    public func syncEvents(into store: PurahWorkspaceStore? = nil) {
        if let store {
            self.boundStore = store
        }
        let targetStore = store ?? boundStore

        let status = PermissionManager.status(from: EKEventStore.authorizationStatus(for: .event))
        guard status.isGranted else {
            isUsingRealCalendar = false
            targetStore?.isUsingRealCalendar = false
            return
        }

        isSyncing = true
        let currentScope = self.scope
        let interval = currentScope.dateInterval(from: Date())

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
                }
            }
        }
        syncEvents(into: store)
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

    public static func defaultEvents() -> [CalendarEventItem] {
        let cal = Calendar.current
        let today = Date()
        let d1 = cal.date(bySettingHour: 10, minute: 0, second: 0, of: today) ?? today
        let d2 = cal.date(bySettingHour: 11, minute: 30, second: 0, of: today) ?? today
        let d3 = cal.date(bySettingHour: 14, minute: 0, second: 0, of: today) ?? today
        let d4 = cal.date(bySettingHour: 15, minute: 0, second: 0, of: today) ?? today
        return [
            CalendarEventItem(id: "default-event-1", title: "Architecture Review", location: "Central Workshop", startTime: d1, endTime: d2),
            CalendarEventItem(id: "default-event-2", title: "Environmental Monitoring", location: "Observation Station", startTime: d3, endTime: d4)
        ]
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
        self.todos = storage.codable(forKey: "todos", as: [TodoItem].self) ?? Self.defaultTodos()
    }

    public func load() {
        if let savedScope = storage.codable(forKey: "scope", as: RemindersScope.self) {
            self.scope = savedScope
        }
        if let savedTodos = storage.codable(forKey: "todos", as: [TodoItem].self) {
            self.todos = savedTodos
        }
    }

    public func save() {
        storage.setCodable(scope, forKey: "scope")
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
        self.isWaveformAnimationEnabled = storage.codable(forKey: "isWaveformAnimationEnabled", as: Bool.self) ?? true
        self.track = storage.codable(forKey: "lastTrack", as: MusicTrackInfo.self) ?? MusicTrackInfo()
    }

    public func load() {
        if let anim = storage.codable(forKey: "isWaveformAnimationEnabled", as: Bool.self) {
            self.isWaveformAnimationEnabled = anim
        }
        if let savedTrack = storage.codable(forKey: "lastTrack", as: MusicTrackInfo.self) {
            self.track = savedTrack
        }
    }

    public func save() {
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
            let nowPlaying = !track.isPlaying
            track.isPlaying = nowPlaying
            track.playbackRate = nowPlaying ? 1.0 : 0.0
            track.currentPositionSeconds = track.calculatedCurrentTime
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
                if let lyr = SystemMusicSyncService.shared.fetchLocalLyrics() {
                    await MainActor.run {
                        if self?.track.title == currentTitle {
                            self?.track.lyrics = lyr
                            self?.boundStore?._musicTrack.lyrics = lyr
                        }
                    }
                }
            }
        }
    }

    public func unmount(store: PurahWorkspaceStore) {
        stopListening()
        SystemMusicSyncService.shared.stopListening()
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
        let totalTimeMs = (userInfo["Total Time"] as? Double) ?? 180000.0
        let currentPosSec = (userInfo["Player Position"] as? Double) ?? 0.0
        let totalSec = max(totalTimeMs / 1000.0, 1.0)
        let progress = min(max(currentPosSec / totalSec, 0.0), 1.0)
        let samples: [Double] = (0..<14).map { _ in
            isPlaying ? Double.random(in: 0.25...0.95) : 0.15
        }

        // Retain existing artwork if same track, or check cache
        let isSameTrack = (self.track.title == title && self.track.artist == artist)
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

        // Fetch local lyrics from Music.app (pure local, zero network)
        if existingLyrics == nil {
            Task { [weak self] in
                if let lyr = SystemMusicSyncService.shared.fetchLocalLyrics() {
                    await MainActor.run {
                        if self?.track.title == title && self?.track.artist == artist {
                            self?.track.lyrics = lyr
                            if let store = self?.boundStore {
                                store._musicTrack.lyrics = lyr
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
        let durationSec = (userInfo["Duration"] as? Double) ?? 180.0
        let currentPosSec = (userInfo["Playback Position"] as? Double) ?? 0.0
        let progress = min(max(currentPosSec / durationSec, 0.0), 1.0)
        let samples: [Double] = (0..<14).map { _ in
            isPlaying ? Double.random(in: 0.25...0.95) : 0.15
        }

        let isSameTrack = (self.track.title == title && self.track.artist == artist)
        let existingArtwork: Data? = {
            if isSameTrack && self.track.artworkData != nil {
                return self.track.artworkData
            }
            return SystemMusicSyncService.shared.cachedArtwork(for: title, artist: artist)
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
            lyrics: nil,
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
    public let storage: any PurahPluginStorage
    @ObservationIgnored private weak var boundStore: PurahWorkspaceStore?

    public var quickNote: NoteContent {
        get { noteContent }
        set { noteContent = newValue }
    }

    public var text: String {
        get { noteContent.text }
        set { updateText(newValue) }
    }

    public init(storage: any PurahPluginStorage = ScopedPluginStorage(pluginId: "notes")) {
        self.storage = storage
        if let saved = storage.codable(forKey: "noteContent", as: NoteContent.self) {
            self.noteContent = saved
        } else if let legacyText = UserDefaults.standard.string(forKey: "purah.quickNote.text") {
            let legacyMod = (UserDefaults.standard.object(forKey: "purah.quickNote.lastModified") as? Date) ?? Date()
            self.noteContent = NoteContent(text: legacyText, lastModified: legacyMod)
        } else {
            self.noteContent = NoteContent()
        }
    }

    public func load() {
        if let saved = storage.codable(forKey: "noteContent", as: NoteContent.self) {
            self.noteContent = saved
        }
    }

    public func save() {
        storage.setCodable(noteContent, forKey: "noteContent")
    }

    public func updateText(_ newText: String) {
        noteContent.text = newText
        noteContent.lastModified = Date()
        save()
        if let boundStore {
            boundStore._quickNote = noteContent
        }
    }

    public func clear() {
        noteContent.text = ""
        noteContent.lastModified = Date()
        save()
        if let boundStore {
            boundStore._quickNote = noteContent
        }
    }

    public func mount(store: PurahWorkspaceStore) {
        self.boundStore = store
        if !store._quickNote.text.isEmpty && self.noteContent.text.isEmpty {
            self.noteContent = store._quickNote
        }
    }

    public func unmount(store: PurahWorkspaceStore) {
        save()
        if boundStore === store {
            boundStore = nil
        }
    }
}

// MARK: - Vitals Plugin State
@Observable
@MainActor
public final class VitalsPluginState: Sendable {
    public var isDecomposed: Bool
    public var enabledMetrics: [VitalsMetricType]
    public var thresholds: VitalsColorThresholds
    public var metrics: HardwareVitalsInfo
    public let storage: any PurahPluginStorage

    @ObservationIgnored private var pollingTask: Task<Void, Never>?
    @ObservationIgnored private weak var boundStore: PurahWorkspaceStore?

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
        self.isDecomposed = storage.bool(forKey: "isDecomposed")
        self.enabledMetrics = storage.codable(forKey: "enabledMetrics", as: [VitalsMetricType].self) ?? [.cpu, .ram, .power, .disk]
        self.thresholds = storage.codable(forKey: "thresholds", as: VitalsColorThresholds.self) ?? VitalsColorThresholds()
        self.metrics = HardwareVitalsService.shared.metrics
    }

    public func load() {
        self.isDecomposed = storage.bool(forKey: "isDecomposed")
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
        stopPolling()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled else { break }
                self?.refreshMetrics(includeProcesses: false)
            }
        }
    }

    public func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    public func refreshMetrics(includeProcesses: Bool = false) {
        HardwareVitalsService.shared.refreshMetrics(includeProcesses: includeProcesses)
        self.metrics = HardwareVitalsService.shared.metrics
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
        startPolling()
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
        self.isDecomposed = storage.bool(forKey: "isDecomposed")
        self.enabledActionIds = storage.codable(forKey: "enabledActionIds", as: [String].self) ?? []
        self.actions = storage.codable(forKey: "actions", as: [ScriptActionItem].self) ?? ScriptRunwayService.shared.actions
        self.lastOutput = nil
        self.isRunning = false
        self.lastExecutedActionId = nil
    }

    public func load() {
        self.isDecomposed = storage.bool(forKey: "isDecomposed")
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
