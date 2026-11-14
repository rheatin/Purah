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
        if let loadedTrack = storage.codable(forKey: "lastTrack", as: MusicTrackInfo.self),
           !loadedTrack.isSamplePlaceholder,
           !loadedTrack.title.isEmpty {
            var track = loadedTrack
            track.isPlaying = false
            track.playbackRate = 0.0
            self.track = track
        } else {
            storage.removeObject(forKey: "lastTrack")
            self.track = .empty
        }
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
        if let savedTrack = storage.codable(forKey: "lastTrack", as: MusicTrackInfo.self) {
            if savedTrack.isSamplePlaceholder || savedTrack.title.isEmpty {
                storage.removeObject(forKey: "lastTrack")
                self.track = .empty
            } else {
                var loaded = savedTrack
                loaded.isPlaying = false
                loaded.playbackRate = 0.0
                self.track = loaded
            }
        } else {
            self.track = .empty
        }
    }

    public func save() {
        storage.setCodable(railStyle, forKey: "railStyle")
        storage.setCodable(dynamicSubStyle, forKey: "dynamicSubStyle")
        storage.set(rhythmOffsetMs, forKey: "rhythmOffsetMs")
        storage.setCodable(isWaveformAnimationEnabled, forKey: "isWaveformAnimationEnabled")
        if !track.title.isEmpty && !track.isSamplePlaceholder {
            storage.setCodable(track, forKey: "lastTrack")
        } else {
            storage.removeObject(forKey: "lastTrack")
        }
    }

    public func togglePlayPause(store: PurahWorkspaceStore? = nil) {
        // Playback is the system's, never ours. With no store there is no
        // player to ask, and a locally flipped flag would be fiction.
        guard let targetStore = store ?? boundStore else { return }
        SystemMusicSyncService.shared.togglePlayPause(store: targetStore)
        self.track = targetStore._musicTrack
        self.isPlaying = targetStore._musicTrack.isPlaying
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
                merged.lyricsOffsetSeconds = self.track.lyricsOffsetSeconds
                merged.isLyricsHidden = self.track.isLyricsHidden
                if merged.selectedLyricsCandidateId == nil { merged.selectedLyricsCandidateId = self.track.selectedLyricsCandidateId }
                if merged.lyricsCandidates.isEmpty { merged.lyricsCandidates = self.track.lyricsCandidates }
            }
            self.track = merged
        }
        SystemMusicSyncService.shared.startListening(into: store)

        // Initial fetch of artwork and local lyrics if not yet cached
        let currentTitle = self.track.title
        let currentArtist = self.track.artist
        let currentAlbum = self.track.album
        if !currentTitle.isEmpty {
            if self.track.artworkData == nil {
                Task { [weak self] in
                    if let art = await SystemMusicSyncService.shared.fetchArtwork(title: currentTitle, artist: currentArtist, album: currentAlbum) {
                        await MainActor.run {
                            if self?.track.title == currentTitle,
                               self?.track.artist == currentArtist {
                                self?.track.artworkData = art
                                self?.boundStore?._musicTrack.artworkData = art
                            }
                        }
                    }
                }
            }
            if self.track.lyrics == nil && self.track.syncedLyrics == nil {
                Task { [weak self] in
                    if let lyrResult = await SystemMusicSyncService.shared.fetchOnlineLyrics(
                        title: currentTitle,
                        artist: currentArtist,
                        album: currentAlbum,
                        durationSeconds: self?.track.durationSeconds ?? 0
                    ) {
                        await MainActor.run {
                            if self?.track.title == currentTitle,
                               self?.track.artist == currentArtist {
                                self?.track.lyrics = lyrResult.plainLyrics
                                self?.track.syncedLyrics = lyrResult.syncedLyrics
                                self?.track.lyricsCandidates = lyrResult.candidates
                                self?.track.selectedLyricsCandidateId = lyrResult.selectedCandidateId
                                self?.boundStore?._musicTrack.lyrics = lyrResult.plainLyrics
                                self?.boundStore?._musicTrack.syncedLyrics = lyrResult.syncedLyrics
                                self?.boundStore?._musicTrack.lyricsCandidates = lyrResult.candidates
                                self?.boundStore?._musicTrack.selectedLyricsCandidateId = lyrResult.selectedCandidateId
                            }
                        }
                    }
                }
            }
        }
    }

    public func selectLyricsCandidate(_ candidate: LyricsCandidate, store: PurahWorkspaceStore? = nil) {
        track.selectedLyricsCandidateId = candidate.id
        track.lyrics = candidate.plainLyrics
        track.syncedLyrics = candidate.syncedLyrics
        let targetStore = store ?? boundStore
        targetStore?._musicTrack.selectedLyricsCandidateId = candidate.id
        targetStore?._musicTrack.lyrics = candidate.plainLyrics
        targetStore?._musicTrack.syncedLyrics = candidate.syncedLyrics
        SystemMusicSyncService.shared.cacheLyrics(
            for: track.title,
            artist: track.artist,
            result: OnlineLyricsResult(
                plainLyrics: candidate.plainLyrics,
                syncedLyrics: candidate.syncedLyrics,
                candidates: track.lyricsCandidates,
                selectedCandidateId: candidate.id
            )
        )
    }

    public func adjustLyricsOffset(by delta: Double, store: PurahWorkspaceStore? = nil) {
        let newOffset = min(max(track.lyricsOffsetSeconds + delta, -10.0), 10.0)
        track.lyricsOffsetSeconds = (newOffset * 10).rounded() / 10
        let targetStore = store ?? boundStore
        targetStore?._musicTrack.lyricsOffsetSeconds = track.lyricsOffsetSeconds
    }

    public func resetLyricsOffset(store: PurahWorkspaceStore? = nil) {
        track.lyricsOffsetSeconds = 0.0
        let targetStore = store ?? boundStore
        targetStore?._musicTrack.lyricsOffsetSeconds = 0.0
    }

    public func setLyricsHidden(_ hidden: Bool, store: PurahWorkspaceStore? = nil) {
        track.isLyricsHidden = hidden
        let targetStore = store ?? boundStore
        targetStore?._musicTrack.isLyricsHidden = hidden
    }

    public func reloadLyrics(store: PurahWorkspaceStore? = nil) {
        let currentTitle = track.title
        let currentArtist = track.artist
        let currentAlbum = track.album
        let currentDur = track.durationSeconds
        guard !currentTitle.isEmpty else { return }

        Task { [weak self] in
            if let lyrResult = await SystemMusicSyncService.shared.fetchOnlineLyrics(
                title: currentTitle,
                artist: currentArtist,
                album: currentAlbum,
                durationSeconds: currentDur,
                forceRefresh: true
            ) {
                await MainActor.run {
                    guard let self = self,
                          self.track.title == currentTitle,
                          self.track.artist == currentArtist else { return }
                    self.track.lyrics = lyrResult.plainLyrics
                    self.track.syncedLyrics = lyrResult.syncedLyrics
                    self.track.lyricsCandidates = lyrResult.candidates
                    self.track.selectedLyricsCandidateId = lyrResult.selectedCandidateId
                    self.track.isLyricsHidden = false
                    let targetStore = store ?? self.boundStore
                    targetStore?._musicTrack.lyrics = lyrResult.plainLyrics
                    targetStore?._musicTrack.syncedLyrics = lyrResult.syncedLyrics
                    targetStore?._musicTrack.lyricsCandidates = lyrResult.candidates
                    targetStore?._musicTrack.selectedLyricsCandidateId = lyrResult.selectedCandidateId
                    targetStore?._musicTrack.isLyricsHidden = false
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
