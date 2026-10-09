// Sources/PurahCore/Services/SystemMusicSyncService.swift
@preconcurrency import Foundation
import AppKit
import Observation

@Observable
@MainActor
public final class SystemMusicSyncService {
    public static let shared = SystemMusicSyncService()

    @ObservationIgnored private var musicObserver: Any?
    @ObservationIgnored private var spotifyObserver: Any?
    @ObservationIgnored private var cachedArtworkKey: String?
    @ObservationIgnored private var cachedArtworkData: Data?
    @ObservationIgnored private var playbackTimer: Timer?

    public private(set) var isMusicAppConnected: Bool = false
    public private(set) var lastNotificationDate: Date?

    public init() {
        startListening()
    }

    public func stopListening() {
        let center = DistributedNotificationCenter.default()
        if let obs = musicObserver {
            center.removeObserver(obs)
            musicObserver = nil
        }
        if let obs = spotifyObserver {
            center.removeObserver(obs)
            spotifyObserver = nil
        }
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

        // 3. Query initial playback state if player is already running
        Task { [weak self, weak store] in
            await self?.pollCurrentPlayingState(store: store)
        }
    }

    public func handlePlayerInfo(notification: Notification, store: PurahWorkspaceStore?) {
        handleAppleMusicInfo(notification: notification, store: store)
    }

    public func handleAppleMusicInfo(notification: Notification, store: PurahWorkspaceStore?) {
        guard let userInfo = notification.userInfo else { return }
        lastNotificationDate = Date()
        isMusicAppConnected = true

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

        let existingArtwork = (cachedArtworkKey == "\(title)|\(artist)") ? cachedArtworkData : nil

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
                sourceApp: "Apple Music",
                sourceBundleId: "com.apple.Music"
            )
            updatePlaybackTimer(store: store, isPlaying: isPlaying)
        }

        if existingArtwork == nil {
            Task { [weak self, weak store] in
                if let art = await self?.fetchArtwork(title: title, artist: artist, album: album) {
                    await MainActor.run {
                        if store?._musicTrack.title == title {
                            store?._musicTrack.artworkData = art
                        }
                    }
                }
            }
        }
    }

    public func handleSpotifyInfo(notification: Notification, store: PurahWorkspaceStore?) {
        guard let userInfo = notification.userInfo else { return }
        lastNotificationDate = Date()
        isMusicAppConnected = true

        let playerState = userInfo["Player State"] as? String ?? ""
        let isPlaying = (playerState == "Playing" || playerState == "kPSPStatePlaying")
        let title = userInfo["Name"] as? String ?? "Unknown Track"
        let artist = userInfo["Artist"] as? String ?? "Spotify"
        let album = userInfo["Album"] as? String ?? ""

        let durationSec = (userInfo["Duration"] as? Double).map { $0 / 1000.0 } ?? 180.0
        let currentPosSec = (userInfo["Playback Position"] as? Double) ?? 0.0
        let progress = min(max(currentPosSec / max(durationSec, 1.0), 0.0), 1.0)

        let samples: [Double] = (0..<14).map { _ in
            isPlaying ? Double.random(in: 0.25...0.95) : 0.15
        }

        let existingArtwork = (cachedArtworkKey == "\(title)|\(artist)") ? cachedArtworkData : nil

        if let store = store {
            store._musicTrack = MusicTrackInfo(
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
                sourceApp: "Spotify",
                sourceBundleId: "com.spotify.client"
            )
            updatePlaybackTimer(store: store, isPlaying: isPlaying)
        }

        if existingArtwork == nil {
            Task { [weak self, weak store] in
                if let art = await self?.fetchArtwork(title: title, artist: artist, album: album) {
                    await MainActor.run {
                        if store?._musicTrack.title == title {
                            store?._musicTrack.artworkData = art
                        }
                    }
                }
            }
        }
    }

    public func pollCurrentPlayingState(store: PurahWorkspaceStore?) async {
        guard isMusicAppRunning else { return }
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

        await MainActor.run {
            guard let store = store else { return }
            store._musicTrack = MusicTrackInfo(
                title: title,
                artist: artist,
                album: album,
                isPlaying: isPlaying,
                playbackProgress: progress,
                currentPositionSeconds: pos,
                durationSeconds: dur,
                lastUpdated: Date(),
                playbackRate: isPlaying ? 1.0 : 0.0,
                sourceApp: "Apple Music",
                sourceBundleId: "com.apple.Music"
            )
            updatePlaybackTimer(store: store, isPlaying: isPlaying)
        }

        if let art = await fetchArtwork(title: title, artist: artist, album: album) {
            await MainActor.run {
                if store?._musicTrack.title == title {
                    store?._musicTrack.artworkData = art
                }
            }
        }
    }

    private func updatePlaybackTimer(store: PurahWorkspaceStore?, isPlaying: Bool) {
        playbackTimer?.invalidate()
        playbackTimer = nil

        guard isPlaying, let store = store else { return }

        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak store] _ in
            MainActor.assumeIsolated {
                guard let store = store, store._musicTrack.isPlaying else { return }
                let cur = store._musicTrack.calculatedCurrentTime
                let prog = store._musicTrack.calculatedProgress
                let samples: [Double] = (0..<14).map { _ in
                    Double.random(in: 0.25...0.95)
                }
                store._musicTrack.currentPositionSeconds = cur
                store._musicTrack.lastUpdated = Date()
                store._musicTrack.playbackProgress = prog
                store._musicTrack.waveformSamples = samples
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

    public func fetchLocalLyrics() -> String? {
        guard isMusicAppRunning else { return nil }
        let script = """
        tell application "Music"
            try
                if player state is not stopped then
                    set lyr to lyrics of current track
                    return lyr
                end if
            end try
            return ""
        end tell
        """
        guard let appleScript = NSAppleScript(source: script) else { return nil }
        var errorInfo: NSDictionary?
        let descriptor = appleScript.executeAndReturnError(&errorInfo)
        guard errorInfo == nil else { return nil }
        let str = descriptor.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let str, !str.isEmpty {
            return str
        }
        return nil
    }

    public func fetchArtwork(title: String, artist: String, album: String) async -> Data? {
        let key = "\(title)|\(artist)"
        if key == cachedArtworkKey, let cached = cachedArtworkData {
            return cached
        }

        // 1. Try local Apple Music AppleScript artwork
        if isMusicAppRunning {
            if let data = fetchAppleMusicNativeArtwork() {
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

    private func fetchAppleMusicNativeArtwork() -> Data? {
        let script = """
        tell application "Music"
            try
                if player state is not stopped then
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

    public func togglePlayPause(store: PurahWorkspaceStore?) {
        guard let store = store else { return }
        let nowPlaying = !store._musicTrack.isPlaying
        store._musicTrack.isPlaying = nowPlaying
        store._musicTrack.playbackRate = nowPlaying ? 1.0 : 0.0
        store._musicTrack.currentPositionSeconds = store._musicTrack.calculatedCurrentTime
        store._musicTrack.lastUpdated = Date()
        updatePlaybackTimer(store: store, isPlaying: nowPlaying)

        if isMusicAppRunning {
            Task.detached {
                Self.executeAppleScript("tell application \"Music\" to playpause")
            }
        } else if isSpotifyRunning {
            Task.detached {
                Self.executeAppleScript("tell application \"Spotify\" to playpause")
            }
        }
    }

    public func nextTrack(store: PurahWorkspaceStore?) {
        if isMusicAppRunning {
            Task.detached {
                Self.executeAppleScript("tell application \"Music\" to next track")
            }
        } else if isSpotifyRunning {
            Task.detached {
                Self.executeAppleScript("tell application \"Spotify\" to next track")
            }
        }
    }

    public func previousTrack(store: PurahWorkspaceStore?) {
        if isMusicAppRunning {
            Task.detached {
                Self.executeAppleScript("tell application \"Music\" to previous track")
            }
        } else if isSpotifyRunning {
            Task.detached {
                Self.executeAppleScript("tell application \"Spotify\" to previous track")
            }
        }
    }

    // MARK: - Real-time Seeking / Scrubbing
    public func seek(to progress: Double, store: PurahWorkspaceStore?) {
        guard let store = store else { return }
        let clamped = min(max(progress, 0.0), 1.0)
        let total = max(store._musicTrack.durationSeconds, 1.0)
        let targetSec = clamped * total

        store._musicTrack.currentPositionSeconds = targetSec
        store._musicTrack.lastUpdated = Date()
        store._musicTrack.playbackProgress = clamped

        if isMusicAppRunning {
            Task.detached {
                Self.executeAppleScript("tell application \"Music\" to set player position to \(targetSec)")
            }
        } else if isSpotifyRunning {
            Task.detached {
                Self.executeAppleScript("tell application \"Spotify\" to set player position to \(targetSec)")
            }
        }
    }

    @discardableResult
    nonisolated private static func executeAppleScript(_ script: String) -> Bool {
        guard let appleScript = NSAppleScript(source: script) else { return false }
        var errorInfo: NSDictionary?
        appleScript.executeAndReturnError(&errorInfo)
        return errorInfo == nil
    }
}
