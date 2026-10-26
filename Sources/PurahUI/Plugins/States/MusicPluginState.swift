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
        if (loadedTrack.title == "Zelda's Lullaby" || loadedTrack.title == "Midnight City") && loadedTrack.lyrics == nil && loadedTrack.syncedLyrics == nil {
            loadedTrack.lyrics = MusicTrackInfo.defaultSamplePlainLyrics
            loadedTrack.syncedLyrics = MusicTrackInfo.defaultSampleSyncedLyrics
        }
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
            if (savedTrack.title == "Zelda's Lullaby" || savedTrack.title == "Midnight City") && savedTrack.lyrics == nil && savedTrack.syncedLyrics == nil {
                savedTrack.lyrics = MusicTrackInfo.defaultSamplePlainLyrics
                savedTrack.syncedLyrics = MusicTrackInfo.defaultSampleSyncedLyrics
            }
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
            var merged = store._musicTrack
            if merged.title == self.track.title && merged.artist == self.track.artist {
                if merged.lyrics == nil { merged.lyrics = self.track.lyrics }
                if merged.syncedLyrics == nil { merged.syncedLyrics = self.track.syncedLyrics }
                if merged.artworkData == nil { merged.artworkData = self.track.artworkData }
            }
            self.track = merged
            store._musicTrack = merged
        }
        self.isWaveformAnimationEnabled = store.isMusicWaveformAnimationEnabled

        // A single observer set: `SystemMusicSyncService` already watches Apple
        // Music, Spotify and MediaRemote. This state used to add its own
        // duplicate distributed observers, so every player notification was
        // handled twice (including two artwork/lyrics fetches per track).
        SystemMusicSyncService.shared.onTrackChanged = { [weak self] newTrack in
            guard let self = self else { return }
            var merged = newTrack
            if merged.title == self.track.title && merged.artist == self.track.artist {
                if merged.lyrics == nil { merged.lyrics = self.track.lyrics }
                if merged.syncedLyrics == nil { merged.syncedLyrics = self.track.syncedLyrics }
                if merged.artworkData == nil { merged.artworkData = self.track.artworkData }
            }
            self.track = merged
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
        if self.track.lyrics == nil && self.track.syncedLyrics == nil {
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
}
