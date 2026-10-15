// Sources/PurahUI/Plugins/States/MusicPluginState.swift
import SwiftUI
import AppKit
import Foundation
import Observation
import PurahCore

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
