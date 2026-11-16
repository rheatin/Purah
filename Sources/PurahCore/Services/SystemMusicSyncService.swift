// Sources/PurahCore/Services/SystemMusicSyncService.swift
@preconcurrency import Foundation
import AppKit
import Observation
import Darwin

// MARK: - Online Lyrics Data Structure
public struct OnlineLyricsResult: Sendable {
    public let plainLyrics: String?
    public let syncedLyrics: String?
    public let candidates: [LyricsCandidate]
    public let selectedCandidateId: String?

    public init(
        plainLyrics: String?,
        syncedLyrics: String?,
        candidates: [LyricsCandidate] = [],
        selectedCandidateId: String? = nil
    ) {
        self.plainLyrics = plainLyrics
        self.syncedLyrics = syncedLyrics
        self.candidates = candidates
        self.selectedCandidateId = selectedCandidateId
    }
}

@Observable
@MainActor
public final class SystemMusicSyncService {
    public static let shared = SystemMusicSyncService()

    @ObservationIgnored private var musicObserver: Any?
    @ObservationIgnored private var spotifyObserver: Any?
    @ObservationIgnored private var mediaRemoteObserver: Any?
    @ObservationIgnored private var mediaRemoteAppObserver: Any?
    @ObservationIgnored private var mediaRemotePlayingObserver: Any?
    @ObservationIgnored private var appTerminationObserver: Any?
    @ObservationIgnored private var cachedArtworkKey: String?
    @ObservationIgnored private var cachedArtworkData: Data?
    @ObservationIgnored private var cachedLyricsKey: String?
    @ObservationIgnored private var cachedLyricsResult: OnlineLyricsResult?
    /// Tracks whose artwork or lyrics came back empty. Only hits were cached
    /// before, so an instrumental asked LRCLIB, NetEase, the iTunes search and
    /// Music.app for lyrics again on every 2s heartbeat — for as long as it
    /// kept playing. One attempt per track per session is the honest bound.
    @ObservationIgnored private var attemptedArtworkKeys: Set<String> = []
    @ObservationIgnored private var attemptedLyricsKeys: Set<String> = []
    /// Exposed so a test can see that a repeated heartbeat schedules nothing.
    @ObservationIgnored public private(set) var lyricFetchAttempts: Int = 0
    @ObservationIgnored private var playbackTimer: Timer?
    @ObservationIgnored private var statusHeartbeatTimer: Timer?
    /// The startup AppleScript query is only a fallback. MediaRemote's first
    /// callback decides whether the AppleScript runtime has to be loaded at
    /// all; a non-empty title means it does not.
    @ObservationIgnored private var pendingStartupAppleScriptFallback = false
    @ObservationIgnored private var lastResolvedSourceApp: String = ""
    @ObservationIgnored private var lastResolvedSourceBundleId: String = ""

    public private(set) var isMusicAppConnected: Bool = false
    public private(set) var lastNotificationDate: Date?
    public var isListening: Bool { musicObserver != nil || spotifyObserver != nil || mediaRemoteObserver != nil }
    public var onTrackChanged: ((MusicTrackInfo) -> Void)?

    nonisolated public static var isTestingEnvironment: Bool {
        NSClassFromString("XCTest") != nil ||
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
        ProcessInfo.processInfo.arguments.contains(where: { $0.contains("swiftpm-testing-helper") || $0.contains("xctest") })
    }

    public init() {
        // Dormant by default: listening is started strictly on-demand when MusicPlugin mounts
    }

    public func stopListening() {
        pendingStartupAppleScriptFallback = false
        SystemAudioLiveMonitor.shared.stop()
        playbackTimer?.invalidate()
        playbackTimer = nil
        statusHeartbeatTimer?.invalidate()
        statusHeartbeatTimer = nil
        let center = DistributedNotificationCenter.default()
        if let obs = musicObserver {
            center.removeObserver(obs)
            musicObserver = nil
        }
        if let obs = spotifyObserver {
            center.removeObserver(obs)
            spotifyObserver = nil
        }
        let nc = NotificationCenter.default
        if let obs = mediaRemoteObserver {
            nc.removeObserver(obs)
            mediaRemoteObserver = nil
        }
        if let obs = mediaRemoteAppObserver {
            nc.removeObserver(obs)
            mediaRemoteAppObserver = nil
        }
        if let obs = mediaRemotePlayingObserver {
            nc.removeObserver(obs)
            mediaRemotePlayingObserver = nil
        }
        if let obs = appTerminationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            appTerminationObserver = nil
        }
        SystemMediaRemoteBridge.shared.unregisterForNotifications()
        clearArtworkCache()
    }

    public func clearArtworkCache() {
        cachedArtworkKey = nil
        cachedArtworkData = nil
        cachedLyricsKey = nil
        cachedLyricsResult = nil
        attemptedArtworkKeys.removeAll()
        attemptedLyricsKeys.removeAll()
    }

    public func startListening(into store: PurahWorkspaceStore? = nil) {
        stopListening()
        let center = DistributedNotificationCenter.default()

        // 1. Apple Music observer
        let musicName = NSNotification.Name("com.apple.Music.playerInfo")
        musicObserver = center.addObserver(
            forName: musicName,
            object: nil,
            queue: .main
        ) { [weak self, weak store] notification in
            nonisolated(unsafe) let notif = notification
            MainActor.assumeIsolated {
                self?.handleAppleMusicInfo(notification: notif, store: store)
            }
        }

        // 2. Spotify observer
        let spotifyName = NSNotification.Name("com.spotify.client.PlaybackStateChanged")
        spotifyObserver = center.addObserver(
            forName: spotifyName,
            object: nil,
            queue: .main
        ) { [weak self, weak store] notification in
            nonisolated(unsafe) let notif = notification
            MainActor.assumeIsolated {
                self?.handleSpotifyInfo(notification: notif, store: store)
            }
        }

        // 2b. App termination observer: immediately halt playback if the active source player quits
        appTerminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self, weak store] notification in
            nonisolated(unsafe) let notif = notification
            MainActor.assumeIsolated {
                guard let self, let store else { return }
                if let terminatedApp = notif.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                   let termBundle = terminatedApp.bundleIdentifier {
                    let activeBundle = Self.normalizeBundleIdentifier(store._musicTrack.sourceBundleId)
                    let termNorm = Self.normalizeBundleIdentifier(termBundle)
                    if !activeBundle.isEmpty && activeBundle.caseInsensitiveCompare(termNorm) == .orderedSame {
                        self.haltPlaybackToPaused(store: store)
                    }
                } else if !Self.isSourcePlayerRunning(for: store._musicTrack) {
                    self.haltPlaybackToPaused(store: store)
                }
            }
        }

        // 3. MediaRemote observer (System-wide media: NetEase, QQ Music, Safari, Chrome, Bilibili, YouTube, Podcasts, VLC, IINA)
        let bridge = SystemMediaRemoteBridge.shared
        if bridge.isAvailable {
            bridge.registerForNotifications(queue: .main)
            let nc = NotificationCenter.default
            mediaRemoteObserver = nc.addObserver(
                forName: NSNotification.Name("kMRMediaRemoteNowPlayingInfoDidChangeNotification"),
                object: nil,
                queue: .main
            ) { [weak self, weak store] _ in
                MainActor.assumeIsolated {
                    self?.handleMediaRemoteInfoUpdate(store: store)
                }
            }
            mediaRemoteAppObserver = nc.addObserver(
                forName: NSNotification.Name("kMRMediaRemoteNowPlayingApplicationDidChangeNotification"),
                object: nil,
                queue: .main
            ) { [weak self, weak store] _ in
                MainActor.assumeIsolated {
                    self?.handleMediaRemoteInfoUpdate(store: store)
                }
            }
            mediaRemotePlayingObserver = nc.addObserver(
                forName: NSNotification.Name("kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification"),
                object: nil,
                queue: .main
            ) { [weak self, weak store] _ in
                MainActor.assumeIsolated {
                    self?.handleMediaRemoteInfoUpdate(store: store)
                }
            }

            // Initial query. Its callback decides whether the startup
            // AppleScript fallback below is needed.
            pendingStartupAppleScriptFallback = true
            handleMediaRemoteInfoUpdate(store: store)
        } else if !Self.isTestingEnvironment {
            // 4. MediaRemote cannot answer here, so preserve the old direct
            // AppleScript startup query.
            Task { [weak self, weak store] in
                await self?.pollCurrentPlayingState(store: store)
            }
        }

        // 5. Periodic 2.0s heartbeat to guarantee continuous real-time state sync across all players
        statusHeartbeatTimer?.invalidate()
        if !Self.isTestingEnvironment {
            statusHeartbeatTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self, weak store] _ in
                MainActor.assumeIsolated {
                    guard let self = self, let store = store else { return }
                    guard !store.isRailsFrozen else { return }
                    if store._musicTrack.isPlaying && !Self.isSourcePlayerRunning(for: store._musicTrack) {
                        self.haltPlaybackToPaused(store: store)
                    }
                    if SystemMediaRemoteBridge.shared.isAvailable {
                        self.handleMediaRemoteInfoUpdate(store: store)
                    } else if self.isMusicAppRunning {
                        Task { [weak self, weak store] in
                            await self?.pollCurrentPlayingState(store: store)
                        }
                    }
                }
            }
        }
    }

    public func handlePlayerInfo(notification: Notification, store: PurahWorkspaceStore?) {
        handleAppleMusicInfo(notification: notification, store: store)
    }

    public static func extractNumericValue(from value: Any?) -> Double? {
        if let num = value as? NSNumber {
            return num.doubleValue
        } else if let d = value as? Double {
            return d
        } else if let i = value as? Int {
            return Double(i)
        } else if let s = value as? String, let d = Double(s) {
            return d
        }
        return nil
    }

    private func handleTrackNotification(
        notification: Notification,
        store: PurahWorkspaceStore?,
        sourceApp: String,
        sourceBundleId: String,
        defaultArtist: String,
        durationKey: String,
        positionKey: String,
        isPlayingCheck: (String) -> Bool
    ) {
        guard let userInfo = notification.userInfo else { return }

        let playerState = userInfo["Player State"] as? String ?? ""
        let isPlaying = isPlayingCheck(playerState)
        let title = userInfo["Name"] as? String ?? "Unknown Track"
        let artist = userInfo["Artist"] as? String ?? defaultArtist
        let album = userInfo["Album"] as? String ?? ""

        // Do not let a paused/stopped notification from a background player overwrite a different actively playing app
        if let store,
           !isPlaying,
           store._musicTrack.isPlaying,
           !store._musicTrack.sourceBundleId.isEmpty,
           store._musicTrack.sourceBundleId.lowercased() != sourceBundleId.lowercased(),
           store._musicTrack.title != title {
            return
        }

        playbackTimer?.invalidate()
        playbackTimer = nil
        lastNotificationDate = Date()
        isMusicAppConnected = true

        let totalTimeMs = Self.extractNumericValue(from: userInfo[durationKey]) ?? 180000.0
        let totalSec = max(totalTimeMs / 1000.0, 1.0)

        let isSameTrack = (store?._musicTrack.title == title && store?._musicTrack.artist == artist)
        let existingPos = store?._musicTrack.calculatedCurrentTime ?? 0.0

        let parsedPosSec = Self.extractNumericValue(from: userInfo[positionKey])
        let currentPosSec: Double = {
            if let pos = parsedPosSec {
                // If notification is Pause and pos is 0, but we were already playing this song,
                // do not wipe out to 0.0! Preserve current calculated position.
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

        let existingArtwork = (isSameTrack ? store?._musicTrack.artworkData : nil) ?? ((cachedArtworkKey == "\(title)|\(artist)") ? cachedArtworkData : nil)
        let cachedLyr = cachedLyrics(for: title, artist: artist)
        let existingLyrics = (isSameTrack ? store?._musicTrack.lyrics : nil) ?? cachedLyr?.plainLyrics
        let existingSyncedLyrics = (isSameTrack ? store?._musicTrack.syncedLyrics : nil) ?? cachedLyr?.syncedLyrics
        let existingOffset = isSameTrack ? (store?._musicTrack.lyricsOffsetSeconds ?? 0.0) : 0.0
        let existingHidden = isSameTrack ? (store?._musicTrack.isLyricsHidden ?? false) : false
        let existingSelectedCandidateId = isSameTrack ? store?._musicTrack.selectedLyricsCandidateId : cachedLyr?.selectedCandidateId
        let existingCandidates = isSameTrack ? (store?._musicTrack.lyricsCandidates ?? []) : (cachedLyr?.candidates ?? [])

        if !sourceBundleId.isEmpty {
            lastResolvedSourceBundleId = Self.normalizeBundleIdentifier(sourceBundleId)
        }
        if !sourceApp.isEmpty && sourceApp != "Media Player" {
            lastResolvedSourceApp = sourceApp
        }

        if let store = store {
            store._musicTrack = MusicTrackInfo(
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
                syncedLyrics: existingSyncedLyrics,
                sourceApp: sourceApp,
                sourceBundleId: sourceBundleId,
                lyricsOffsetSeconds: existingOffset,
                isLyricsHidden: existingHidden,
                selectedLyricsCandidateId: existingSelectedCandidateId,
                lyricsCandidates: existingCandidates
            )
            updatePlaybackTimer(store: store, isPlaying: isPlaying)
            onTrackChanged?(store._musicTrack)
        }

        let artworkKey = "\(title)|\(artist)"
        if existingArtwork == nil, !attemptedArtworkKeys.contains(artworkKey) {
            attemptedArtworkKeys.insert(artworkKey)
            Task { [weak self, weak store] in
                if let art = await self?.fetchArtwork(title: title, artist: artist, album: album) {
                    await MainActor.run {
                        if let store = store,
                           store._musicTrack.title == title,
                           store._musicTrack.artist == artist {
                            store._musicTrack.artworkData = art
                            self?.onTrackChanged?(store._musicTrack)
                        }
                    }
                }
            }
        }

        let lyricsKey = "\(title)|\(artist)"
        if existingLyrics == nil && existingSyncedLyrics == nil && !title.isEmpty && title != "Unknown Track",
           !attemptedLyricsKeys.contains(lyricsKey) {
            attemptedLyricsKeys.insert(lyricsKey)
            lyricFetchAttempts += 1
            Task { [weak self, weak store] in
                if let lyr = await self?.fetchOnlineLyrics(title: title, artist: artist, album: album, durationSeconds: totalSec) {
                    await MainActor.run {
                        if let store = store,
                           store._musicTrack.title == title,
                           store._musicTrack.artist == artist {
                            store._musicTrack.lyrics = lyr.plainLyrics
                            store._musicTrack.syncedLyrics = lyr.syncedLyrics
                            store._musicTrack.lyricsCandidates = lyr.candidates
                            store._musicTrack.selectedLyricsCandidateId = lyr.selectedCandidateId
                            self?.onTrackChanged?(store._musicTrack)
                        }
                    }
                }
            }
        }
    }

    public func handleAppleMusicInfo(notification: Notification, store: PurahWorkspaceStore?) {
        handleTrackNotification(
            notification: notification,
            store: store,
            sourceApp: "Apple Music",
            sourceBundleId: "com.apple.Music",
            defaultArtist: "Apple Music",
            durationKey: "Total Time",
            positionKey: "Player Position",
            isPlayingCheck: { $0 == "Playing" }
        )
    }

    public func handleSpotifyInfo(notification: Notification, store: PurahWorkspaceStore?) {
        handleTrackNotification(
            notification: notification,
            store: store,
            sourceApp: "Spotify",
            sourceBundleId: "com.spotify.client",
            defaultArtist: "Spotify",
            durationKey: "Duration",
            positionKey: "Playback Position",
            isPlayingCheck: { $0 == "Playing" || $0 == "kPSPStatePlaying" }
        )
    }

    // MARK: - MediaRemote System-wide Multimedia Processing
    public func handleMediaRemoteInfoUpdate(store: PurahWorkspaceStore?) {
        let bridge = SystemMediaRemoteBridge.shared
        guard bridge.isAvailable else { return }

        bridge.getNowPlayingInfo(queue: .main) { [weak self, weak store] dict in
            guard let dict else {
                MainActor.assumeIsolated {
                    self?.runStartupAppleScriptFallbackIfNeeded(store: store)
                    self?.haltPlaybackToPaused(store: store)
                }
                return
            }
            bridge.getNowPlayingPID(queue: .main) { [weak self, weak store] pid in
                MainActor.assumeIsolated {
                    self?.processMediaRemoteData(dict: dict, pid: pid, store: store)
                }
            }
        }
    }

    public func haltPlaybackToPaused(store: PurahWorkspaceStore?) {
        guard let store, store._musicTrack.isPlaying || store._musicTrack.playbackRate > 0 else { return }
        let frozenTime = store._musicTrack.calculatedCurrentTime
        let totalSec = max(store._musicTrack.durationSeconds, 1.0)
        store._musicTrack.currentPositionSeconds = frozenTime
        store._musicTrack.playbackProgress = min(max(frozenTime / totalSec, 0.0), 1.0)
        store._musicTrack.isPlaying = false
        store._musicTrack.playbackRate = 0.0
        store._musicTrack.lastUpdated = Date()
        store._musicTrack.waveformSamples = [Double](repeating: 0.15, count: max(store._musicTrack.waveformSamples.count, 5))
        updatePlaybackTimer(store: store, isPlaying: false)
        onTrackChanged?(store._musicTrack)
    }

    public func processMediaRemoteData(dict: [String: Any], pid: pid_t, store: PurahWorkspaceStore?) {
        guard let title = dict["kMRMediaRemoteNowPlayingInfoTitle"] as? String, !title.isEmpty else {
            runStartupAppleScriptFallbackIfNeeded(store: store)
            // An empty Now-Playing payload means the source app ended its media
            // session (e.g. Dynamic.music clears the dict on pause). Swallowing
            // this update froze the rail on "playing" forever — honor it as a
            // stop signal, keeping the last anchor position.
            haltPlaybackToPaused(store: store)
            return
        }

        pendingStartupAppleScriptFallback = false

        let artist = dict["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? ""
        let album = dict["kMRMediaRemoteNowPlayingInfoAlbum"] as? String ?? ""
        let duration = Self.extractNumericValue(from: dict["kMRMediaRemoteNowPlayingInfoDuration"]) ?? 180.0
        let elapsed = Self.extractNumericValue(from: dict["kMRMediaRemoteNowPlayingInfoElapsedTime"]) ?? 0.0
        let rate = Self.extractNumericValue(from: dict["kMRMediaRemoteNowPlayingInfoPlaybackRate"]) ?? 0.0
        let artworkData = dict["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data

        var appName = "Media Player"
        var bundleId = ""
        let clientBundleId = dict["kPurahMRClientBundleIdentifier"] as? String
        let clientDisplayName = dict["kPurahMRClientDisplayName"] as? String
        if (pid > 0 || (clientBundleId != nil && !clientBundleId!.isEmpty)),
           let resolved = Self.resolveHostApplication(
               for: pid,
               clientBundleId: clientBundleId,
               clientDisplayName: clientDisplayName
           ) {
            appName = resolved.name
            bundleId = resolved.bundleId
        } else if let isMusicApp = dict["kMRMediaRemoteNowPlayingInfoIsMusicApp"] as? Bool, isMusicApp {
            appName = "Apple Music"
            bundleId = "com.apple.Music"
        }

        // Preserve known source player identity when MediaRemote emits a snapshot
        // after the player process has terminated (where pid == 0 or is no longer running).
        if bundleId.isEmpty {
            if let existing = store?._musicTrack, !existing.title.isEmpty {
                let existingBundle = Self.normalizeBundleIdentifier(existing.sourceBundleId)
                let inferredBundle = Self.knownBundleId(forSourceApp: existing.sourceApp) ?? ""
                let candidateBundle = !existingBundle.isEmpty ? existingBundle : inferredBundle
                if !candidateBundle.isEmpty && (existing.title == title || !lastResolvedSourceBundleId.isEmpty) {
                    bundleId = candidateBundle
                    if !existing.sourceApp.isEmpty && existing.sourceApp != "Media Player" {
                        appName = existing.sourceApp
                    }
                }
            }
            if bundleId.isEmpty && !lastResolvedSourceBundleId.isEmpty {
                bundleId = lastResolvedSourceBundleId
                if !lastResolvedSourceApp.isEmpty {
                    appName = lastResolvedSourceApp
                }
            }
        }

        if !bundleId.isEmpty {
            lastResolvedSourceBundleId = Self.normalizeBundleIdentifier(bundleId)
            if appName.isEmpty || appName == "Media Player" {
                appName = Self.knownDisplayName(for: lastResolvedSourceBundleId)
                    ?? Self.installedAppDisplayName(forBundleIdentifier: lastResolvedSourceBundleId)
                    ?? appName
            }
            if !appName.isEmpty && appName != "Media Player" {
                lastResolvedSourceApp = appName
            }
        }

        let isPlayerRunning: Bool = {
            guard !Self.isTestingEnvironment, !bundleId.isEmpty else { return true }
            let probe = MusicTrackInfo(title: title, sourceApp: appName, sourceBundleId: bundleId)
            return Self.isSourcePlayerRunning(for: probe)
        }()
        let isPlaying = (rate > 0.0) && isPlayerRunning

        lastNotificationDate = Date()
        isMusicAppConnected = true

        let totalSec = max(duration, 1.0)
        let sampleTimestamp: Date = {
            if let date = dict["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date {
                return date
            }
            if let cfDate = dict["kMRMediaRemoteNowPlayingInfoTimestamp"] as? NSDate {
                return cfDate as Date
            }
            return Date()
        }()

        let resolvedArtist = artist.isEmpty ? appName : artist
        let isSameTrack = (store?._musicTrack.title == title && (store?._musicTrack.artist == artist || store?._musicTrack.artist == resolvedArtist))
        let existingPos = store?._musicTrack.calculatedCurrentTime ?? 0.0
        let currentPosSec: Double = {
            if !isPlaying && elapsed == 0.0 && isSameTrack && existingPos > 1.0 {
                return existingPos
            }
            return min(max(elapsed, 0.0), totalSec)
        }()
        let progress = min(max(currentPosSec / totalSec, 0.0), 1.0)

        let existingArtwork = artworkData ?? (isSameTrack ? store?._musicTrack.artworkData : nil) ?? ((cachedArtworkKey == "\(title)|\(resolvedArtist)" || cachedArtworkKey == "\(title)|\(artist)") ? cachedArtworkData : nil)
        let cachedLyr = cachedLyrics(for: title, artist: resolvedArtist) ?? cachedLyrics(for: title, artist: artist)
        let existingLyrics = (isSameTrack ? store?._musicTrack.lyrics : nil) ?? cachedLyr?.plainLyrics
        let existingSyncedLyrics = (isSameTrack ? store?._musicTrack.syncedLyrics : nil) ?? cachedLyr?.syncedLyrics
        let existingOffset = isSameTrack ? (store?._musicTrack.lyricsOffsetSeconds ?? 0.0) : 0.0
        let existingHidden = isSameTrack ? (store?._musicTrack.isLyricsHidden ?? false) : false
        let existingSelectedCandidateId = isSameTrack ? store?._musicTrack.selectedLyricsCandidateId : cachedLyr?.selectedCandidateId
        let existingCandidates = isSameTrack ? (store?._musicTrack.lyricsCandidates ?? []) : (cachedLyr?.candidates ?? [])

        if let store = store {
            let next = MusicTrackInfo(
                title: title,
                artist: resolvedArtist,
                album: album,
                isPlaying: isPlaying,
                playbackProgress: progress,
                currentPositionSeconds: currentPosSec,
                durationSeconds: totalSec,
                lastUpdated: sampleTimestamp,
                playbackRate: isPlaying ? 1.0 : 0.0,
                waveformSamples: [0.3, 0.6, 0.4, 0.7, 0.5],
                artworkData: existingArtwork,
                lyrics: existingLyrics,
                syncedLyrics: existingSyncedLyrics,
                sourceApp: appName,
                sourceBundleId: bundleId,
                lyricsOffsetSeconds: existingOffset,
                isLyricsHidden: existingHidden,
                selectedLyricsCandidateId: existingSelectedCandidateId,
                lyricsCandidates: existingCandidates
            )
            // Reassigning `_musicTrack` invalidates every view that reads it, so
            // a paused player was repainting the rail on every 2s heartbeat with
            // identical content. Nothing visible moved means nothing to repaint.
            if !next.matchesVisibleState(of: store._musicTrack) {
                store._musicTrack = next
                updatePlaybackTimer(store: store, isPlaying: isPlaying)
                onTrackChanged?(store._musicTrack)
            }
        }

        let artworkKey = "\(title)|\(resolvedArtist)"
        if existingArtwork == nil, !attemptedArtworkKeys.contains(artworkKey) {
            attemptedArtworkKeys.insert(artworkKey)
            Task { [weak self, weak store] in
                if let art = await self?.fetchArtwork(title: title, artist: resolvedArtist, album: album) {
                    await MainActor.run {
                        if let store = store,
                           store._musicTrack.title == title,
                           store._musicTrack.artist == resolvedArtist {
                            store._musicTrack.artworkData = art
                            self?.onTrackChanged?(store._musicTrack)
                        }
                    }
                }
            }
        }

        let lyricsKey = "\(title)|\(resolvedArtist)"
        if existingLyrics == nil && existingSyncedLyrics == nil && !title.isEmpty && title != "Unknown Track",
           !attemptedLyricsKeys.contains(lyricsKey) {
            attemptedLyricsKeys.insert(lyricsKey)
            lyricFetchAttempts += 1
            Task { [weak self, weak store] in
                if let lyr = await self?.fetchOnlineLyrics(title: title, artist: resolvedArtist, album: album, durationSeconds: totalSec) {
                    await MainActor.run {
                        if let store = store,
                           store._musicTrack.title == title,
                           store._musicTrack.artist == resolvedArtist {
                            store._musicTrack.lyrics = lyr.plainLyrics
                            store._musicTrack.syncedLyrics = lyr.syncedLyrics
                            store._musicTrack.lyricsCandidates = lyr.candidates
                            store._musicTrack.selectedLyricsCandidateId = lyr.selectedCandidateId
                            self?.onTrackChanged?(store._musicTrack)
                        }
                    }
                }
            }
        }
    }

    public func pollCurrentPlayingState(store: PurahWorkspaceStore?) async {
        guard !Self.isTestingEnvironment else { return }
        guard isMusicAppRunning else { return }
        let queryStartTime = Date()
        let script = """
        tell application "Music"
            try
                set pState to (player state is playing)
                set tName to name of current track
                set tArtist to artist of current track
                set tAlbum to album of current track
                set tPos to player position
                set tDur to duration of current track
                return {pState, tName, tArtist, tAlbum, tPos, tDur}
            on error
                return {}
            end try
        end tell
        """
        guard let appleScript = NSAppleScript(source: script) else { return }
        var errorInfo: NSDictionary?
        let descriptor = appleScript.executeAndReturnError(&errorInfo)
        guard errorInfo == nil, descriptor.numberOfItems >= 6 else { return }

        let isPlaying = descriptor.atIndex(1)?.booleanValue ?? false
        let title = descriptor.atIndex(2)?.stringValue ?? "Unknown Track"
        let artist = descriptor.atIndex(3)?.stringValue ?? "Apple Music"
        let album = descriptor.atIndex(4)?.stringValue ?? ""
        let pos = descriptor.atIndex(5)?.doubleValue ?? 0.0
        let dur = descriptor.atIndex(6)?.doubleValue ?? 180.0
        let progress = dur > 0 ? min(max(pos / dur, 0.0), 1.0) : 0.0

        var needsLyricsFetch = false
        var needsArtworkFetch = false

        await MainActor.run {
            guard let store = store else { return }
            // Do not overwrite an existing non-Apple-Music track with a paused Music.app track
            if !isPlaying,
               !store._musicTrack.title.isEmpty,
               !store._musicTrack.sourceBundleId.isEmpty,
               store._musicTrack.sourceBundleId != "com.apple.Music" {
                return
            }
            let isSameTrack = (store._musicTrack.title == title && store._musicTrack.artist == artist)
            let existingArtwork = (isSameTrack ? store._musicTrack.artworkData : nil) ?? cachedArtwork(for: title, artist: artist)
            let cachedLyr = cachedLyrics(for: title, artist: artist)
            let existingLyrics = (isSameTrack ? store._musicTrack.lyrics : nil) ?? cachedLyr?.plainLyrics
            let existingSyncedLyrics = (isSameTrack ? store._musicTrack.syncedLyrics : nil) ?? cachedLyr?.syncedLyrics

            needsArtworkFetch = (existingArtwork == nil)
            needsLyricsFetch = (existingLyrics == nil && existingSyncedLyrics == nil && !title.isEmpty && title != "Unknown Track")

            let existingOffset = isSameTrack ? (store._musicTrack.lyricsOffsetSeconds) : 0.0
            let existingHidden = isSameTrack ? (store._musicTrack.isLyricsHidden) : false
            let existingSelectedCandidateId = isSameTrack ? store._musicTrack.selectedLyricsCandidateId : cachedLyr?.selectedCandidateId
            let existingCandidates = isSameTrack ? store._musicTrack.lyricsCandidates : (cachedLyr?.candidates ?? [])

            lastResolvedSourceBundleId = "com.apple.Music"
            lastResolvedSourceApp = "Apple Music"
            store._musicTrack = MusicTrackInfo(
                title: title,
                artist: artist,
                album: album,
                isPlaying: isPlaying,
                playbackProgress: progress,
                currentPositionSeconds: pos,
                durationSeconds: dur,
                lastUpdated: queryStartTime,
                playbackRate: isPlaying ? 1.0 : 0.0,
                artworkData: existingArtwork,
                lyrics: existingLyrics,
                syncedLyrics: existingSyncedLyrics,
                sourceApp: "Apple Music",
                sourceBundleId: "com.apple.Music",
                lyricsOffsetSeconds: existingOffset,
                isLyricsHidden: existingHidden,
                selectedLyricsCandidateId: existingSelectedCandidateId,
                lyricsCandidates: existingCandidates
            )
            updatePlaybackTimer(store: store, isPlaying: isPlaying)
            onTrackChanged?(store._musicTrack)
        }

        if needsArtworkFetch, let art = await fetchArtwork(title: title, artist: artist, album: album) {
            await MainActor.run {
                if let store = store,
                   store._musicTrack.title == title,
                   store._musicTrack.artist == artist {
                    store._musicTrack.artworkData = art
                    onTrackChanged?(store._musicTrack)
                }
            }
        }

        if needsLyricsFetch, let lyr = await fetchOnlineLyrics(title: title, artist: artist, album: album, durationSeconds: dur) {
            await MainActor.run {
                if let store = store,
                   store._musicTrack.title == title,
                   store._musicTrack.artist == artist {
                    store._musicTrack.lyrics = lyr.plainLyrics
                    store._musicTrack.syncedLyrics = lyr.syncedLyrics
                    store._musicTrack.lyricsCandidates = lyr.candidates
                    store._musicTrack.selectedLyricsCandidateId = lyr.selectedCandidateId
                    onTrackChanged?(store._musicTrack)
                }
            }
        }
    }

    private func runStartupAppleScriptFallbackIfNeeded(store: PurahWorkspaceStore?) {
        guard pendingStartupAppleScriptFallback else { return }
        pendingStartupAppleScriptFallback = false
        guard !Self.isTestingEnvironment, isMusicAppRunning else { return }
        Task { [weak self, weak store] in
            await self?.pollCurrentPlayingState(store: store)
        }
    }

    private func updatePlaybackTimer(store: PurahWorkspaceStore?, isPlaying: Bool) {
        if isPlaying {
            SystemAudioLiveMonitor.shared.start()
        } else {
            SystemAudioLiveMonitor.shared.stop()
        }

        playbackTimer?.invalidate()
        playbackTimer = nil

        guard isPlaying, let store = store else { return }

        var tickCount = 0
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self, weak store] _ in
            MainActor.assumeIsolated {
                guard let store = store, store._musicTrack.isPlaying else { return }
                guard !store.isRailsFrozen else { return }
                guard store.pods.contains(where: { $0.id == "music" && $0.isEnabled }) else { return }

                tickCount += 1
                if tickCount % 4 == 0 {
                    // Periodic 4-second ground-truth recalibration to prevent time-anchor drift
                    if SystemMediaRemoteBridge.shared.isAvailable {
                        self?.handleMediaRemoteInfoUpdate(store: store)
                    } else if self?.isMusicAppRunning == true {
                        Task { [weak self, weak store] in
                            await self?.pollCurrentPlayingState(store: store)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Artwork Fetching Engine (Local AppleScript + iTunes Catalog Fallback)
    public func cachedArtwork(for title: String, artist: String) -> Data? {
        let key = "\(title)|\(artist)"
        if key == cachedArtworkKey {
            return cachedArtworkData
        }
        return nil
    }

    // MARK: - Online Lyrics Fetching Engine (LRCLIB + NetEase Open APIs)
    private static let placeholderArtists: Set<String> = [
        "apple music", "music", "spotify", "google chrome", "chrome", "safari",
        "arc", "firefox", "microsoft edge", "brave browser", "media player",
        "unknown artist", "unknown", "neteasemusic", "qqmusic"
    ]

    public static func isPlaceholderArtist(_ artist: String, sourceApp: String = "") -> Bool {
        let trimmed = artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty { return true }
        if placeholderArtists.contains(trimmed) { return true }
        if !sourceApp.isEmpty && trimmed == sourceApp.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            return true
        }
        return false
    }

    public static func inferArtistAndTitle(from rawTitle: String) -> (artist: String, title: String)? {
        let parts = rawTitle.components(separatedBy: " - ")
        if parts.count >= 2 {
            let artist = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let title = parts[1...].joined(separator: " - ").trimmingCharacters(in: .whitespacesAndNewlines)
            if !artist.isEmpty && !title.isEmpty {
                return (artist, title)
            }
        }
        return nil
    }

    public static func normalizeTrackTitleForSearch(_ rawTitle: String) -> String {
        var clean = rawTitle
        clean = clean.replacingOccurrences(of: #"(?i)\s*[\(\[](feat\.|ft\.)[^\)\]]+[\)\]]"#, with: "", options: .regularExpression)
        clean = clean.replacingOccurrences(of: #"(?i)\s*[-–—]\s*remaster(ed)?\b.*"#, with: "", options: .regularExpression)
        clean = clean.replacingOccurrences(of: #"(?i)\s*[\(\[]remaster(ed)?[^\)\]]*[\)\]]"#, with: "", options: .regularExpression)
        clean = clean.replacingOccurrences(of: #"(?i)\s*[\(\[](official\s+(video|audio|music\s+video)|mv|explicit)[\)\]]"#, with: "", options: .regularExpression)
        return clean.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let versionPenaltyKeywords = [
        "live", "remix", "伴奏", "instrumental", "karaoke", "翻唱", "cover", "dj版", "acoustic"
    ]

    public static func scoreLyricsCandidate(
        candidateTitle: String,
        candidateArtist: String,
        candidateDuration: Double?,
        hasSyncedLyrics: Bool,
        targetTitle: String,
        targetArtist: String,
        targetDuration: Double?
    ) -> Double {
        var score: Double = 0.0

        let normCandTitle = normalizeTrackTitleForSearch(candidateTitle).lowercased()
        let normTargTitle = normalizeTrackTitleForSearch(targetTitle).lowercased()

        let strippedCandTitle = normCandTitle.filter { $0.isLetter || $0.isNumber }
        let strippedTargTitle = normTargTitle.filter { $0.isLetter || $0.isNumber }

        // Title matching
        if normCandTitle == normTargTitle || (!strippedCandTitle.isEmpty && strippedCandTitle == strippedTargTitle) {
            score += 50.0
        } else if normCandTitle.contains(normTargTitle) || normTargTitle.contains(normCandTitle) ||
                  (!strippedCandTitle.isEmpty && !strippedTargTitle.isEmpty && (strippedCandTitle.contains(strippedTargTitle) || strippedTargTitle.contains(strippedCandTitle))) {
            score += 25.0
        } else {
            score -= 60.0
        }

        // Version keyword guard
        let candTitleLower = candidateTitle.lowercased()
        let candArtistLower = candidateArtist.lowercased()
        let targTitleLower = targetTitle.lowercased()
        for kw in versionPenaltyKeywords {
            let kwInCand = candTitleLower.contains(kw) || candArtistLower.contains(kw)
            let kwInTarg = targTitleLower.contains(kw)
            if kwInCand && !kwInTarg {
                score -= 45.0
            }
        }

        // Artist similarity (only when target artist is not a placeholder)
        if !isPlaceholderArtist(targetArtist) {
            let candArtLower = candidateArtist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let targArtLower = targetArtist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let strippedCandArt = candArtLower.filter { $0.isLetter || $0.isNumber }
            let strippedTargArt = targArtLower.filter { $0.isLetter || $0.isNumber }

            if candArtLower == targArtLower || (!strippedCandArt.isEmpty && strippedCandArt == strippedTargArt) ||
                candArtLower.contains(targArtLower) || targArtLower.contains(candArtLower) {
                score += 35.0
            } else {
                score -= 25.0
            }
        }

        // Duration proximity
        if let targetDur = targetDuration, targetDur > 15.0,
           let candDur = candidateDuration, candDur > 15.0 {
            let diff = abs(candDur - targetDur)
            if diff <= 3.0 {
                score += 30.0
            } else if diff <= 8.0 {
                score += 15.0
            } else if diff <= 15.0 {
                score += 0.0
            } else if diff <= 30.0 {
                score -= 35.0
            } else {
                score -= 75.0
            }
        }

        // Synced lyrics bonus
        if hasSyncedLyrics {
            score += 15.0
        }

        return score
    }

    public func cachedLyrics(for title: String, artist: String) -> OnlineLyricsResult? {
        let key = "\(title)|\(artist)"
        return cachedLyricsKey == key ? cachedLyricsResult : nil
    }

    public func cacheLyrics(for title: String, artist: String, result: OnlineLyricsResult) {
        cachedLyricsKey = "\(title)|\(artist)"
        cachedLyricsResult = result
    }

    public func fetchOnlineLyrics(
        title: String,
        artist: String,
        album: String = "",
        durationSeconds: Double = 0,
        forceRefresh: Bool = false
    ) async -> OnlineLyricsResult? {
        guard !title.isEmpty else { return nil }
        let key = "\(title)|\(artist)"

        if forceRefresh {
            if cachedLyricsKey == key {
                cachedLyricsKey = nil
                cachedLyricsResult = nil
            }
            attemptedLyricsKeys.remove(key)
        } else if key == cachedLyricsKey, let cached = cachedLyricsResult {
            return cached
        }

        guard !Self.isTestingEnvironment else { return nil }

        var candidates: [LyricsCandidate] = []
        var seenCandidateIds: Set<String> = []

        let isPlaceholder = Self.isPlaceholderArtist(artist)
        let cleanTitle = Self.normalizeTrackTitleForSearch(title)

        var searchArtist = isPlaceholder ? "" : artist
        var searchTitle = cleanTitle

        if isPlaceholder, let inferred = Self.inferArtistAndTitle(from: title) {
            searchArtist = inferred.artist
            searchTitle = Self.normalizeTrackTitleForSearch(inferred.title)
        }

        // 1. LRCLIB
        // 1a. /api/get (exact lookup) if we have an artist
        if !searchArtist.isEmpty {
            let encArtist = searchArtist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            let encTitle = searchTitle.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            var getUrlStr = "https://lrclib.net/api/get?artist_name=\(encArtist)&track_name=\(encTitle)"
            if !album.isEmpty, let encAlbum = album.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                getUrlStr += "&album_name=\(encAlbum)"
            }
            if durationSeconds > 15 {
                getUrlStr += "&duration=\(Int(durationSeconds))"
            }

            if let url = URL(string: getUrlStr) {
                var request = URLRequest(url: url)
                request.timeoutInterval = 4.0
                request.setValue("Purah/2.0 (macOS Ambient Rail Kernel)", forHTTPHeaderField: "User-Agent")
                if let (data, resp) = try? await URLSession.shared.data(for: request),
                   let http = resp as? HTTPURLResponse, http.statusCode == 200,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let cand = parseLRCLIBCandidate(json, targetTitle: title, targetArtist: searchArtist, targetDuration: durationSeconds) {
                        if cand.score > 0 && !seenCandidateIds.contains(cand.id) {
                            candidates.append(cand)
                            seenCandidateIds.insert(cand.id)
                        }
                    }
                }
            }
        }

        // 1b. LRCLIB /api/search if best score < 75
        let bestScoreSoFar = candidates.map(\.score).max() ?? -100.0
        if bestScoreSoFar < 75.0 {
            let query = (!searchArtist.isEmpty ? "\(searchTitle) \(searchArtist)" : searchTitle)
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            if let searchUrl = URL(string: "https://lrclib.net/api/search?q=\(query)") {
                var request = URLRequest(url: searchUrl)
                request.timeoutInterval = 4.0
                request.setValue("Purah/2.0 (macOS Ambient Rail Kernel)", forHTTPHeaderField: "User-Agent")
                if let (data, resp) = try? await URLSession.shared.data(for: request),
                   let http = resp as? HTTPURLResponse, http.statusCode == 200,
                   let jsonList = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                    for item in jsonList.prefix(5) {
                        if let cand = parseLRCLIBCandidate(item, targetTitle: title, targetArtist: searchArtist, targetDuration: durationSeconds) {
                            if cand.score > 0 && !seenCandidateIds.contains(cand.id) {
                                candidates.append(cand)
                                seenCandidateIds.insert(cand.id)
                            }
                        }
                    }
                }
            }
        }

        // 2. NetEase Fallback if candidates < 2 or best score < 70
        let currentBest = candidates.map(\.score).max() ?? -100.0
        if candidates.count < 2 || currentBest < 70.0 {
            let query = (!searchArtist.isEmpty ? "\(searchTitle) \(searchArtist)" : searchTitle)
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            if let neteaseUrl = URL(string: "https://music.163.com/api/search/get/web?s=\(query)&type=1&offset=0&total=true&limit=8") {
                var request = URLRequest(url: neteaseUrl)
                request.timeoutInterval = 4.0
                request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
                if let (data, resp) = try? await URLSession.shared.data(for: request),
                   let http = resp as? HTTPURLResponse, http.statusCode == 200,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let resultObj = json["result"] as? [String: Any],
                   let songs = resultObj["songs"] as? [[String: Any]] {

                    struct PreScoredSong {
                        let id: Int
                        let name: String
                        let artistName: String
                        let albumName: String?
                        let durationSec: Double
                        let preScore: Double
                    }

                    var scoredSongs: [PreScoredSong] = []
                    for song in songs {
                        guard let id = song["id"] as? Int,
                              let name = song["name"] as? String else { continue }

                        let artistsList = (song["artists"] as? [[String: Any]]) ?? (song["ar"] as? [[String: Any]]) ?? []
                        let artistNames = artistsList.compactMap { $0["name"] as? String }.joined(separator: ", ")
                        let albumObj = (song["album"] as? [String: Any]) ?? (song["al"] as? [String: Any])
                        let albumName = albumObj?["name"] as? String
                        let durMs = Self.extractNumericValue(from: song["duration"]) ?? Self.extractNumericValue(from: song["dt"]) ?? 0.0
                        let durSec = durMs > 0 ? (durMs / 1000.0) : 0.0

                        let preScore = Self.scoreLyricsCandidate(
                            candidateTitle: name,
                            candidateArtist: artistNames,
                            candidateDuration: durSec > 0 ? durSec : nil,
                            hasSyncedLyrics: true,
                            targetTitle: title,
                            targetArtist: searchArtist,
                            targetDuration: durationSeconds > 0 ? durationSeconds : nil
                        )

                        if preScore > 0 {
                            scoredSongs.append(PreScoredSong(
                                id: id,
                                name: name,
                                artistName: artistNames,
                                albumName: albumName,
                                durationSec: durSec,
                                preScore: preScore
                            ))
                        }
                    }

                    scoredSongs.sort { $0.preScore > $1.preScore }

                    for song in scoredSongs.prefix(3) {
                        let candId = "netease-\(song.id)"
                        if seenCandidateIds.contains(candId) { continue }
                        if let lyricUrl = URL(string: "https://music.163.com/api/song/lyric?os=osx&id=\(song.id)&lv=-1&kv=-1&tv=-1") {
                            var lrcReq = URLRequest(url: lyricUrl)
                            lrcReq.timeoutInterval = 4.0
                            if let (lrcData, lrcResp) = try? await URLSession.shared.data(for: lrcReq),
                               let lrcHttp = lrcResp as? HTTPURLResponse, lrcHttp.statusCode == 200,
                               let lrcJson = try? JSONSerialization.jsonObject(with: lrcData) as? [String: Any],
                               let lrcObj = lrcJson["lrc"] as? [String: Any],
                               let rawLrc = lrcObj["lyric"] as? String, !rawLrc.isEmpty {
                                let cleaned = cleanLrcTimestamps(rawLrc)
                                let hasSynced = rawLrc.contains("[") && rawLrc.contains("]")
                                let finalScore = Self.scoreLyricsCandidate(
                                    candidateTitle: song.name,
                                    candidateArtist: song.artistName,
                                    candidateDuration: song.durationSec > 0 ? song.durationSec : nil,
                                    hasSyncedLyrics: hasSynced,
                                    targetTitle: title,
                                    targetArtist: searchArtist,
                                    targetDuration: durationSeconds > 0 ? durationSeconds : nil
                                )

                                if finalScore > 0 {
                                    let cand = LyricsCandidate(
                                        id: candId,
                                        title: song.name,
                                        artist: song.artistName,
                                        album: song.albumName,
                                        durationSeconds: song.durationSec > 0 ? song.durationSec : nil,
                                        source: "NetEase",
                                        plainLyrics: cleaned.isEmpty ? nil : cleaned,
                                        syncedLyrics: hasSynced ? rawLrc : nil,
                                        score: finalScore
                                    )
                                    candidates.append(cand)
                                    seenCandidateIds.insert(candId)
                                }
                            }
                        }
                    }
                }
            }
        }

        candidates.sort { $0.score > $1.score }
        let topCandidates = Array(candidates.prefix(5))

        guard let best = topCandidates.first else {
            return nil
        }

        let result = OnlineLyricsResult(
            plainLyrics: best.plainLyrics,
            syncedLyrics: best.syncedLyrics,
            candidates: topCandidates,
            selectedCandidateId: best.id
        )
        cachedLyricsKey = key
        cachedLyricsResult = result
        return result
    }

    private func parseLRCLIBCandidate(
        _ json: [String: Any],
        targetTitle: String,
        targetArtist: String,
        targetDuration: Double
    ) -> LyricsCandidate? {
        guard let trackName = json["trackName"] as? String else { return nil }
        let artistName = json["artistName"] as? String ?? ""
        let albumName = json["albumName"] as? String
        let durSec = Self.extractNumericValue(from: json["duration"])
        let plain = (json["plainLyrics"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let synced = (json["syncedLyrics"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard (plain != nil && !plain!.isEmpty) || (synced != nil && !synced!.isEmpty) else {
            return nil
        }

        let idVal: String
        if let idInt = json["id"] as? Int {
            idVal = "lrclib-\(idInt)"
        } else if let idStr = json["id"] as? String {
            idVal = "lrclib-\(idStr)"
        } else {
            idVal = "lrclib-\(UUID().uuidString)"
        }

        let hasSynced = (synced != nil && !synced!.isEmpty)
        let score = Self.scoreLyricsCandidate(
            candidateTitle: trackName,
            candidateArtist: artistName,
            candidateDuration: durSec,
            hasSyncedLyrics: hasSynced,
            targetTitle: targetTitle,
            targetArtist: targetArtist,
            targetDuration: targetDuration > 0 ? targetDuration : nil
        )

        return LyricsCandidate(
            id: idVal,
            title: trackName,
            artist: artistName,
            album: albumName,
            durationSeconds: durSec,
            source: "LRCLIB",
            plainLyrics: plain,
            syncedLyrics: synced,
            score: score
        )
    }

    private func cleanLrcTimestamps(_ rawLrc: String) -> String {
        let lines = rawLrc.components(separatedBy: .newlines)
        var cleanedLines: [String] = []
        for line in lines {
            let stripped = line.replacingOccurrences(of: "\\[\\d{2}:\\d{2}\\.\\d{2,3}\\]", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            if !stripped.isEmpty && !stripped.hasPrefix("[ti:") && !stripped.hasPrefix("[ar:") && !stripped.hasPrefix("[al:") && !stripped.hasPrefix("[by:") {
                cleanedLines.append(stripped)
            }
        }
        return cleanedLines.joined(separator: "\n")
    }

    public func fetchArtwork(title: String, artist: String, album: String) async -> Data? {
        guard !Self.isTestingEnvironment else { return nil }
        let key = "\(title)|\(artist)"
        if key == cachedArtworkKey, let cached = cachedArtworkData {
            return cached
        }

        // 1. Try local Apple Music AppleScript artwork only when the current track matches
        if isMusicAppRunning {
            if let data = fetchAppleMusicNativeArtwork(matchingTitle: title) {
                cachedArtworkKey = key
                cachedArtworkData = data
                return data
            }
        }

        // 2. Fallback to iTunes Store Web Search API (like Atoll's AppleMusicCatalogArtworkResolver)
        let query = "\(title) \(artist)"
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://itunes.apple.com/search?term=\(encoded)&media=music&entity=song&limit=1") else {
            return nil
        }

        do {
            let (jsonData, _) = try await URLSession.shared.data(from: url)
            if let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
               let results = json["results"] as? [[String: Any]],
               let first = results.first,
               let art100 = first["artworkUrl100"] as? String {
                let highRes = art100.replacingOccurrences(of: "100x100", with: "600x600")
                if let imgUrl = URL(string: highRes) {
                    let (imgData, _) = try await URLSession.shared.data(from: imgUrl)
                    cachedArtworkKey = key
                    cachedArtworkData = imgData
                    return imgData
                }
            }
        } catch {
            // Ignore network errors gracefully
        }

        return nil
    }

    private func fetchAppleMusicNativeArtwork(matchingTitle: String? = nil) -> Data? {
        let escapedTitle = (matchingTitle ?? "")
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let titleGuard = escapedTitle.isEmpty ? "true" : "(name of current track is \"\(escapedTitle)\")"
        let script = """
        tell application "Music"
            try
                if player state is not stopped and \(titleGuard) then
                    set art to raw data of artwork 1 of current track
                    return art
                end if
            end try
            return ""
        end tell
        """
        guard let appleScript = NSAppleScript(source: script) else { return nil }
        var errorInfo: NSDictionary?
        let descriptor = appleScript.executeAndReturnError(&errorInfo)
        guard errorInfo == nil else { return nil }
        if let data = descriptor.data as Data?, data.count > 32 {
            return data
        }
        return nil
    }

    public var isMusicAppRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty
    }

    public var isSpotifyRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").isEmpty
    }

    public func togglePlayPause(
        store: PurahWorkspaceStore?,
        runningBundleChecker: ((String) -> Bool)? = nil
    ) {
        guard let store = store else { return }
        let nowPlaying = !store._musicTrack.isPlaying
        let isPlayerRunning = Self.isSourcePlayerRunning(
            for: store._musicTrack,
            runningBundleChecker: runningBundleChecker
        )

        // Never fake playback (progress bar moving / lyrics scrolling) when the source player app is closed
        if nowPlaying && !isPlayerRunning {
            haltPlaybackToPaused(store: store)
            return
        }

        let bundleId = store._musicTrack.sourceBundleId.lowercased()
        let isAppleMusic = bundleId.contains("apple.music") && isMusicAppRunning
        let isSpotify = bundleId.contains("spotify") && isSpotifyRunning

        if nowPlaying,
           !Self.isTestingEnvironment,
           runningBundleChecker == nil,
           !isAppleMusic,
           !isSpotify,
           !SystemMediaRemoteBridge.shared.hasActiveNowPlayingTrack {
            haltPlaybackToPaused(store: store)
            return
        }

        // 1. Freeze elapsed position BEFORE altering isPlaying or playbackRate
        let frozenTime = store._musicTrack.calculatedCurrentTime
        let totalSec = max(store._musicTrack.durationSeconds, 1.0)

        store._musicTrack.currentPositionSeconds = frozenTime
        store._musicTrack.playbackProgress = min(max(frozenTime / totalSec, 0.0), 1.0)
        store._musicTrack.isPlaying = nowPlaying
        store._musicTrack.playbackRate = nowPlaying ? 1.0 : 0.0
        store._musicTrack.lastUpdated = Date()
        updatePlaybackTimer(store: store, isPlaying: nowPlaying)
        onTrackChanged?(store._musicTrack)

        guard isPlayerRunning else { return }

        if isAppleMusic {
            Task.detached {
                Self.executeAppleScript("tell application \"Music\" to playpause")
            }
        } else if isSpotify {
            Task.detached {
                Self.executeAppleScript("tell application \"Spotify\" to playpause")
            }
        } else if SystemMediaRemoteBridge.shared.isAvailable {
            SystemMediaRemoteBridge.shared.togglePlayPause()
        }

        if !Self.isTestingEnvironment {
            schedulePostCommandVerification(store: store)
        }
    }

    private func schedulePostCommandVerification(store: PurahWorkspaceStore?) {
        for delay in [0.35, 0.9] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak store] in
                MainActor.assumeIsolated {
                    guard let self, let store else { return }
                    if !Self.isSourcePlayerRunning(for: store._musicTrack) {
                        self.haltPlaybackToPaused(store: store)
                    } else if SystemMediaRemoteBridge.shared.isAvailable {
                        self.handleMediaRemoteInfoUpdate(store: store)
                    }
                }
            }
        }
    }

    public func nextTrack(
        store: PurahWorkspaceStore?,
        runningBundleChecker: ((String) -> Bool)? = nil
    ) {
        if let store, !Self.isSourcePlayerRunning(for: store._musicTrack, runningBundleChecker: runningBundleChecker) {
            haltPlaybackToPaused(store: store)
            return
        }
        let bundleId = store?._musicTrack.sourceBundleId.lowercased() ?? ""
        if bundleId.contains("apple.music") && isMusicAppRunning {
            Task.detached {
                Self.executeAppleScript("tell application \"Music\" to next track")
            }
        } else if bundleId.contains("spotify") && isSpotifyRunning {
            Task.detached {
                Self.executeAppleScript("tell application \"Spotify\" to next track")
            }
        } else if SystemMediaRemoteBridge.shared.isAvailable {
            SystemMediaRemoteBridge.shared.nextTrack()
        }
    }

    public func previousTrack(
        store: PurahWorkspaceStore?,
        runningBundleChecker: ((String) -> Bool)? = nil
    ) {
        if let store, !Self.isSourcePlayerRunning(for: store._musicTrack, runningBundleChecker: runningBundleChecker) {
            haltPlaybackToPaused(store: store)
            return
        }
        let bundleId = store?._musicTrack.sourceBundleId.lowercased() ?? ""
        if bundleId.contains("apple.music") && isMusicAppRunning {
            Task.detached {
                Self.executeAppleScript("tell application \"Music\" to previous track")
            }
        } else if bundleId.contains("spotify") && isSpotifyRunning {
            Task.detached {
                Self.executeAppleScript("tell application \"Spotify\" to previous track")
            }
        } else if SystemMediaRemoteBridge.shared.isAvailable {
            SystemMediaRemoteBridge.shared.previousTrack()
        }
    }

    // MARK: - Real-time Seeking / Scrubbing
    public func seek(
        to progress: Double,
        store: PurahWorkspaceStore?,
        runningBundleChecker: ((String) -> Bool)? = nil
    ) {
        guard let store = store else { return }
        guard Self.isSourcePlayerRunning(for: store._musicTrack, runningBundleChecker: runningBundleChecker) else {
            haltPlaybackToPaused(store: store)
            return
        }
        let bundleId = store._musicTrack.sourceBundleId.lowercased()
        let isAppleMusic = bundleId.contains("apple.music") && isMusicAppRunning
        let isSpotify = bundleId.contains("spotify") && isSpotifyRunning
        if !Self.isTestingEnvironment,
           runningBundleChecker == nil,
           !isAppleMusic,
           !isSpotify,
           !SystemMediaRemoteBridge.shared.hasActiveNowPlayingTrack {
            haltPlaybackToPaused(store: store)
            return
        }

        let clamped = min(max(progress, 0.0), 1.0)
        let total = max(store._musicTrack.durationSeconds, 1.0)
        let targetSec = clamped * total

        store._musicTrack.currentPositionSeconds = targetSec
        store._musicTrack.lastUpdated = Date()
        store._musicTrack.playbackProgress = clamped
        onTrackChanged?(store._musicTrack)

        if isAppleMusic {
            Task.detached {
                Self.executeAppleScript("tell application \"Music\" to set player position to \(targetSec)")
            }
        } else if isSpotify {
            Task.detached {
                Self.executeAppleScript("tell application \"Spotify\" to set player position to \(targetSec)")
            }
        } else if SystemMediaRemoteBridge.shared.isAvailable {
            SystemMediaRemoteBridge.shared.seek(to: targetSec)
        }
    }

    @discardableResult
    nonisolated private static func executeAppleScript(_ script: String) -> Bool {
        guard !Self.isTestingEnvironment else { return false }
        guard let appleScript = NSAppleScript(source: script) else { return false }
        var errorInfo: NSDictionary?
        appleScript.executeAndReturnError(&errorInfo)
        return errorInfo == nil
    }

    // MARK: - Host Application & Browser Tab Resolution

    public static func normalizeBundleIdentifier(_ bundleId: String) -> String {
        var id = bundleId.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = id.range(of: ".helper", options: .caseInsensitive) {
            id = String(id[..<range.lowerBound])
        }
        return id
    }

    public static let knownMediaAppBundleIds: [String] = [
        "com.apple.Music",
        "com.spotify.client",
        "com.netease.163music",
        "com.tencent.QQMusicMac",
        "app.neiro.ui",
        "com.google.Chrome",
        "company.thebrowser.Browser", // Arc
        "com.apple.Safari",
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "org.mozilla.firefox",
        "com.colliderli.iina",
        "org.videolan.vlc"
    ]

    public static func knownDisplayName(for bundleId: String) -> String? {
        switch bundleId {
        case "com.apple.Music": return "Apple Music"
        case "com.spotify.client": return "Spotify"
        case "com.netease.163music": return "NetEase Music"
        case "com.tencent.QQMusicMac": return "QQ Music"
        case "app.neiro.ui": return "Neiro"
        case "com.google.Chrome": return "Google Chrome"
        case "company.thebrowser.Browser": return "Arc"
        case "com.apple.Safari": return "Safari"
        case "com.brave.Browser": return "Brave Browser"
        case "com.microsoft.edgemac": return "Microsoft Edge"
        case "org.mozilla.firefox": return "Firefox"
        case "com.colliderli.iina": return "IINA"
        case "org.videolan.vlc": return "VLC"
        case "com.apple.podcasts": return "Podcasts"
        default: return nil
        }
    }

    public static func knownBundleId(forSourceApp sourceApp: String) -> String? {
        let lower = sourceApp.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch lower {
        case "apple music", "music": return "com.apple.Music"
        case "spotify": return "com.spotify.client"
        case "neiro": return "app.neiro.ui"
        case "netease music", "neteasemusic", "网易云音乐": return "com.netease.163music"
        case "qq music", "qqmusic", "qq音乐": return "com.tencent.QQMusicMac"
        case "google chrome", "chrome": return "com.google.Chrome"
        case "safari": return "com.apple.Safari"
        case "arc": return "company.thebrowser.Browser"
        case "brave", "brave browser": return "com.brave.Browser"
        case "microsoft edge", "edge": return "com.microsoft.edgemac"
        case "firefox": return "org.mozilla.firefox"
        case "iina": return "com.colliderli.iina"
        case "vlc": return "org.videolan.vlc"
        case "podcasts": return "com.apple.podcasts"
        default: return nil
        }
    }

    public static func isSourcePlayerRunning(
        for track: MusicTrackInfo,
        runningBundleChecker: ((String) -> Bool)? = nil
    ) -> Bool {
        if Self.isTestingEnvironment && runningBundleChecker == nil {
            return true
        }
        guard !track.title.isEmpty, !track.isSamplePlaceholder else {
            return false
        }
        let checkRunning: (String) -> Bool = runningBundleChecker ?? { bundleId in
            !NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
                .filter { !$0.isTerminated }
                .isEmpty
        }
        let normalizedBundleId = normalizeBundleIdentifier(track.sourceBundleId)
        if !normalizedBundleId.isEmpty {
            return checkRunning(normalizedBundleId)
        }
        if let inferred = knownBundleId(forSourceApp: track.sourceApp) {
            return checkRunning(inferred)
        }
        return resolveRunningMediaAppFallback() != nil
    }

    public static func resolveRunningMediaAppFallback() -> (name: String, bundleId: String)? {
        for bundleId in knownMediaAppBundleIds {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first(where: { !$0.isTerminated }) {
                let name = app.localizedName ?? knownDisplayName(for: bundleId) ?? ""
                return (name: name.isEmpty ? "Media Player" : name, bundleId: bundleId)
            }
        }
        return nil
    }

    public static func installedAppDisplayName(forBundleIdentifier bundleId: String) -> String? {
        let normalized = normalizeBundleIdentifier(bundleId)
        guard !normalized.isEmpty,
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: normalized) else {
            return nil
        }
        if let bundle = Bundle(url: appURL) {
            if let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
               !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return displayName
            }
            if let bundleName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String,
               !bundleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return bundleName
            }
        }
        let filename = appURL.deletingPathExtension().lastPathComponent
        return filename.isEmpty ? nil : filename
    }

    public static func resolveHostApplication(
        for pid: pid_t,
        clientBundleId: String? = nil,
        clientDisplayName: String? = nil
    ) -> (name: String, bundleId: String)? {
        if let rawClientBundleId = clientBundleId {
            let normalizedClientId = normalizeBundleIdentifier(rawClientBundleId)
            if !normalizedClientId.isEmpty && !normalizedClientId.lowercased().hasPrefix("com.apple.webkit") {
                if let running = NSRunningApplication.runningApplications(withBundleIdentifier: normalizedClientId).first(where: { !$0.isTerminated }) {
                    let name = running.localizedName
                        ?? clientDisplayName
                        ?? knownDisplayName(for: normalizedClientId)
                        ?? running.bundleURL?.deletingPathExtension().lastPathComponent
                        ?? ""
                    return (name: name.isEmpty ? "Media Player" : name, bundleId: normalizedClientId)
                }
                let fallbackName = clientDisplayName
                    ?? knownDisplayName(for: normalizedClientId)
                    ?? installedAppDisplayName(forBundleIdentifier: normalizedClientId)
                    ?? ""
                return (name: fallbackName.isEmpty ? "Media Player" : fallbackName, bundleId: normalizedClientId)
            }
        }

        guard pid > 0 else { return nil }

        var curPid = pid
        var accessoryCandidate: (name: String, bundleId: String)?
        for _ in 0..<8 {
            if let app = NSRunningApplication(processIdentifier: curPid) {
                let rawBundleId = app.bundleIdentifier ?? ""
                let normalizedId = normalizeBundleIdentifier(rawBundleId)
                let name = app.localizedName
                    ?? clientDisplayName
                    ?? knownDisplayName(for: normalizedId)
                    ?? app.bundleURL?.deletingPathExtension().lastPathComponent
                    ?? ""

                if app.activationPolicy == .regular && !normalizedId.isEmpty {
                    return (name: name.isEmpty ? "Media Player" : name, bundleId: normalizedId)
                }

                if !normalizedId.isEmpty && !rawBundleId.isEmpty && normalizedId != rawBundleId {
                    if let mainApp = NSRunningApplication.runningApplications(withBundleIdentifier: normalizedId).first {
                        let mainName = mainApp.localizedName ?? name
                        return (name: mainName.isEmpty ? "Media Player" : mainName, bundleId: normalizedId)
                    }
                    return (name: name.isEmpty ? "Media Player" : name, bundleId: normalizedId)
                }

                if accessoryCandidate == nil && !normalizedId.isEmpty && !normalizedId.lowercased().hasPrefix("com.apple.webkit") {
                    accessoryCandidate = (name: name.isEmpty ? "Media Player" : name, bundleId: normalizedId)
                }
            }

            var info = proc_bsdinfo()
            let size = proc_pidinfo(
                curPid,
                PROC_PIDTBSDINFO,
                0,
                &info,
                Int32(MemoryLayout<proc_bsdinfo>.size)
            )
            guard size == Int32(MemoryLayout<proc_bsdinfo>.size) else { break }
            let parentPid = pid_t(info.pbi_ppid)
            guard parentPid > 1 && parentPid != curPid else { break }
            curPid = parentPid
        }

        if let candidate = accessoryCandidate {
            return candidate
        }

        return nil
    }

    public static func browserAppName(for bundleId: String) -> String? {
        switch bundleId {
        case "com.google.Chrome": return "Google Chrome"
        case "com.brave.Browser": return "Brave Browser"
        case "com.microsoft.edgemac": return "Microsoft Edge"
        case "company.thebrowser.Browser": return "Arc"
        case "com.apple.Safari": return "Safari"
        default:
            if bundleId.contains("Chrome") { return "Google Chrome" }
            return nil
        }
    }

    public static func buildBrowserTabActivationScript(
        appName: String,
        isSafari: Bool,
        trackTitle: String
    ) -> String {
        let escapedTitle = trackTitle
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let cleanTitle = String(escapedTitle.prefix(40))

        let urlCondition = "tabURL contains \"bilibili.com\" or tabURL contains \"youtube.com\" or tabURL contains \"music.163.com\" or tabURL contains \"y.qq.com\" or tabURL contains \"music.youtube.com\" or tabURL contains \"open.spotify.com\" or tabURL contains \"soundcloud.com\" or tabURL contains \"podcasts.apple.com\""

        if isSafari {
            let matchClause = cleanTitle.isEmpty
                ? urlCondition
                : "tabTitle contains \"\(cleanTitle)\" or \(urlCondition)"
            return """
            tell application "Safari"
                activate
                set foundTab to false
                repeat with w in (every window)
                    repeat with t in (every tab of w)
                        set tabTitle to name of t
                        set tabURL to URL of t
                        if \(matchClause) then
                            set current tab of w to t
                            set index of w to 1
                            set foundTab to true
                            exit repeat
                        end if
                    end repeat
                    if foundTab then exit repeat
                end repeat
            end tell
            """
        } else {
            let matchClause = cleanTitle.isEmpty
                ? urlCondition
                : "tabTitle contains \"\(cleanTitle)\" or \(urlCondition)"
            return """
            tell application "\(appName)"
                activate
                set foundTab to false
                repeat with w in (every window)
                    set tabIdx to 0
                    repeat with t in (every tab of w)
                        set tabIdx to tabIdx + 1
                        set tabTitle to title of t
                        set tabURL to URL of t
                        if \(matchClause) then
                            set active tab index of w to tabIdx
                            set index of w to 1
                            set foundTab to true
                            exit repeat
                        end if
                    end repeat
                    if foundTab then exit repeat
                end repeat
            end tell
            """
        }
    }

    /// Resolves the target bundle identifier and display name for jumping to the source player.
    /// Crucially, this preserves the source player's bundle ID even when that player has been quit,
    /// so clicking the album artwork relaunches the exact player that was playing rather than
    /// falling back to Apple Music or another running app.
    public static func resolveTargetPlayer(
        for track: MusicTrackInfo,
        fallbackTrack: MusicTrackInfo? = nil,
        lastResolvedBundleId: String = "",
        lastResolvedAppName: String = ""
    ) -> (bundleId: String, appName: String) {
        var bundleId = normalizeBundleIdentifier(track.sourceBundleId)
        var appName = track.sourceApp.trimmingCharacters(in: .whitespacesAndNewlines)

        if let inferred = knownBundleId(forSourceApp: appName) {
            if bundleId.isEmpty || (bundleId == "com.apple.Music" && inferred != "com.apple.Music") {
                bundleId = inferred
            }
        }

        if bundleId.isEmpty, let fb = fallbackTrack {
            let fbBundle = normalizeBundleIdentifier(fb.sourceBundleId)
            let fbApp = fb.sourceApp.trimmingCharacters(in: .whitespacesAndNewlines)
            if let inferred = knownBundleId(forSourceApp: fbApp),
               fbBundle.isEmpty || (fbBundle == "com.apple.Music" && inferred != "com.apple.Music") {
                bundleId = inferred
            } else if !fbBundle.isEmpty {
                bundleId = fbBundle
            }
            if (appName.isEmpty || appName == "Media Player") && !fbApp.isEmpty {
                appName = fbApp
            }
        }

        if bundleId.isEmpty && !lastResolvedBundleId.isEmpty {
            bundleId = normalizeBundleIdentifier(lastResolvedBundleId)
            if (appName.isEmpty || appName == "Media Player") && !lastResolvedAppName.isEmpty {
                appName = lastResolvedAppName
            }
        }

        if bundleId.isEmpty && !appName.isEmpty && appName != "Media Player" {
            let candidatePaths = [
                "/Applications/\(appName).app",
                "\(NSHomeDirectory())/Applications/\(appName).app"
            ]
            for path in candidatePaths where FileManager.default.fileExists(atPath: path) {
                if let bundle = Bundle(path: path),
                   let id = bundle.bundleIdentifier,
                   !id.isEmpty {
                    bundleId = normalizeBundleIdentifier(id)
                    break
                }
            }
        }

        if bundleId.isEmpty {
            if let running = resolveRunningMediaAppFallback() {
                bundleId = running.bundleId
                if appName.isEmpty || appName == "Media Player" {
                    appName = running.name
                }
            } else {
                bundleId = "com.apple.Music"
                if appName.isEmpty || appName == "Media Player" {
                    appName = "Apple Music"
                }
            }
        }

        if appName.isEmpty || appName == "Media Player" {
            appName = knownDisplayName(for: bundleId)
                ?? installedAppDisplayName(forBundleIdentifier: bundleId)
                ?? appName
        }

        return (bundleId: bundleId, appName: appName)
    }

    public func activateSourcePlayer(for track: MusicTrackInfo? = nil, store: PurahWorkspaceStore? = nil) {
        let activeTrack = track ?? store?._musicTrack ?? MusicTrackInfo.empty
        let resolved = Self.resolveTargetPlayer(
            for: activeTrack,
            fallbackTrack: store?._musicTrack,
            lastResolvedBundleId: lastResolvedSourceBundleId,
            lastResolvedAppName: lastResolvedSourceApp
        )
        let bundleId = resolved.bundleId
        let appName = resolved.appName

        // 1. If it's a browser, attempt AppleScript Tab activation
        if let browserName = Self.browserAppName(for: bundleId) {
            let isSafari = (bundleId == "com.apple.Safari")
            let title = activeTrack.title
            let script = Self.buildBrowserTabActivationScript(appName: browserName, isSafari: isSafari, trackTitle: title)
            Task.detached(priority: .userInitiated) {
                Self.executeAppleScript(script)
            }
        }

        // 2. System-level window & app activation (launches the app if it was quit)
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first(where: { !$0.isTerminated }) {
            _ = app.activate()
        }
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: appURL, configuration: config, completionHandler: nil)
            return
        }
        if !appName.isEmpty && appName != "Media Player" {
            let candidatePaths = [
                "/Applications/\(appName).app",
                "\(NSHomeDirectory())/Applications/\(appName).app"
            ]
            for path in candidatePaths where FileManager.default.fileExists(atPath: path) {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: config, completionHandler: nil)
                return
            }
        }
    }
}
