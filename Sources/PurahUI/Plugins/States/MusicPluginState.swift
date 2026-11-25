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
    public let syncService: SystemMusicSyncService
    public let audioMonitor: SystemAudioLiveMonitor

    @ObservationIgnored private weak var boundStore: PurahWorkspaceStore?
    /// The artwork/lyrics fetches started by `mount`. They used to outlive the
    /// drawer: `unmount` never cancelled them, so a closed pod kept loading.
    @ObservationIgnored private var initialFetchTasks: [Task<Void, Never>] = []

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

    public var currentAudioLevel: Float {
        audioMonitor.currentLevel
    }

    public func syncAudioLatencyOffset(_ offsetMs: Double? = nil) {
        audioMonitor.latencyOffsetMs = offsetMs ?? rhythmOffsetMs
    }

    public init(
        storage: any PurahPluginStorage = ScopedPluginStorage(pluginId: "music"),
        syncService: SystemMusicSyncService = .shared,
        audioMonitor: SystemAudioLiveMonitor = .shared
    ) {
        self.storage = storage
        self.syncService = syncService
        self.audioMonitor = audioMonitor
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
        syncService.togglePlayPause(store: targetStore)
        self.track = targetStore._musicTrack
        self.isPlaying = targetStore._musicTrack.isPlaying
    }

    public func nextTrack(store: PurahWorkspaceStore? = nil) {
        let targetStore = store ?? boundStore
        syncService.nextTrack(store: targetStore)
    }

    public func previousTrack(store: PurahWorkspaceStore? = nil) {
        let targetStore = store ?? boundStore
        syncService.previousTrack(store: targetStore)
    }

    public func seek(to progress: Double, store: PurahWorkspaceStore? = nil) {
        guard let targetStore = store ?? boundStore else { return }
        syncService.seek(to: progress, store: targetStore)
        self.track = targetStore._musicTrack
    }

    public func activateSourcePlayer(store: PurahWorkspaceStore? = nil) {
        let targetStore = store ?? boundStore
        let activeTrack = !track.title.isEmpty ? track : (targetStore?._musicTrack ?? track)
        syncService.activateSourcePlayer(for: activeTrack, store: targetStore)
    }

    public func update(from trackInfo: MusicTrackInfo) {
        self.track = trackInfo
        self.boundStore?._musicTrack = trackInfo
    }

    /// Single track-preservation merge path shared by `mount` and live `onTrackChanged`
    /// notifications so lyrics, artwork, source identity, and user offsets never drift.
    public static func mergeTrackFields(
        incoming: MusicTrackInfo,
        existing: MusicTrackInfo,
        preserveLyricsPreferences: Bool
    ) -> MusicTrackInfo {
        var merged = incoming
        guard merged.title == existing.title && merged.artist == existing.artist else {
            return merged
        }
        if merged.lyrics == nil { merged.lyrics = existing.lyrics }
        if merged.syncedLyrics == nil { merged.syncedLyrics = existing.syncedLyrics }
        if merged.artworkData == nil { merged.artworkData = existing.artworkData }
        if merged.sourceBundleId.isEmpty { merged.sourceBundleId = existing.sourceBundleId }
        if merged.sourceApp.isEmpty || merged.sourceApp == "Media Player" {
            merged.sourceApp = existing.sourceApp
        }
        if preserveLyricsPreferences {
            merged.lyricsOffsetSeconds = existing.lyricsOffsetSeconds
            merged.isLyricsHidden = existing.isLyricsHidden
            if merged.selectedLyricsCandidateId == nil {
                merged.selectedLyricsCandidateId = existing.selectedLyricsCandidateId
            }
            if merged.lyricsCandidates.isEmpty {
                merged.lyricsCandidates = existing.lyricsCandidates
            }
        }
        return merged
    }

    public func mount(store: PurahWorkspaceStore) {
        self.boundStore = store
        if !store._musicTrack.title.isEmpty {
            let merged = Self.mergeTrackFields(
                incoming: store._musicTrack,
                existing: self.track,
                preserveLyricsPreferences: false
            )
            self.track = merged
            store._musicTrack = merged
        } else if !self.track.title.isEmpty {
            store._musicTrack = self.track
        }
        self.isWaveformAnimationEnabled = store.isMusicWaveformAnimationEnabled

        // A single observer set: `SystemMusicSyncService` already watches Apple
        // Music, Spotify and MediaRemote. This state used to add its own
        // duplicate distributed observers, so every player notification was
        // handled twice (including two artwork/lyrics fetches per track).
        syncService.onTrackChanged = { [weak self] newTrack in
            guard let self = self else { return }
            let merged = Self.mergeTrackFields(
                incoming: newTrack,
                existing: self.track,
                preserveLyricsPreferences: true
            )
            let shouldPersist = merged.title != self.track.title
                || merged.artist != self.track.artist
                || merged.sourceBundleId != self.track.sourceBundleId
                || merged.sourceApp != self.track.sourceApp
                || merged.selectedLyricsCandidateId != self.track.selectedLyricsCandidateId
                || merged.lyricsOffsetSeconds != self.track.lyricsOffsetSeconds
                || merged.isLyricsHidden != self.track.isLyricsHidden
            self.track = merged
            if shouldPersist {
                self.save()
            }
        }
        syncService.startListening(into: store)

        // Initial fetch of artwork and local lyrics if not yet cached
        let currentTitle = self.track.title
        let currentArtist = self.track.artist
        let currentAlbum = self.track.album
        initialFetchTasks.forEach { $0.cancel() }
        initialFetchTasks.removeAll()
        if !currentTitle.isEmpty {
            if self.track.artworkData == nil {
                initialFetchTasks.append(Task { [weak self] in
                    guard let self else { return }
                    if let art = await self.syncService.fetchArtwork(title: currentTitle, artist: currentArtist, album: currentAlbum) {
                        guard !Task.isCancelled else { return }
                        if self.track.title == currentTitle,
                           self.track.artist == currentArtist {
                            self.track.artworkData = art
                            self.boundStore?._musicTrack.artworkData = art
                        }
                    }
                })
            }
            if self.track.lyrics == nil && self.track.syncedLyrics == nil {
                initialFetchTasks.append(Task { [weak self] in
                    guard let self else { return }
                    if let lyrResult = await self.syncService.fetchOnlineLyrics(
                        title: currentTitle,
                        artist: currentArtist,
                        album: currentAlbum,
                        durationSeconds: self.track.durationSeconds
                    ) {
                        guard !Task.isCancelled else { return }
                        if self.track.title == currentTitle,
                           self.track.artist == currentArtist {
                            self.track.lyrics = lyrResult.plainLyrics
                            self.track.syncedLyrics = lyrResult.syncedLyrics
                            self.track.lyricsCandidates = lyrResult.candidates
                            self.track.selectedLyricsCandidateId = lyrResult.selectedCandidateId
                            self.boundStore?._musicTrack.lyrics = lyrResult.plainLyrics
                            self.boundStore?._musicTrack.syncedLyrics = lyrResult.syncedLyrics
                            self.boundStore?._musicTrack.lyricsCandidates = lyrResult.candidates
                            self.boundStore?._musicTrack.selectedLyricsCandidateId = lyrResult.selectedCandidateId
                        }
                    }
                })
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
        syncService.cacheLyrics(
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
            guard let self else { return }
            if let lyrResult = await self.syncService.fetchOnlineLyrics(
                title: currentTitle,
                artist: currentArtist,
                album: currentAlbum,
                durationSeconds: currentDur,
                forceRefresh: true
            ) {
                await MainActor.run {
                    guard self.track.title == currentTitle,
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
        initialFetchTasks.forEach { $0.cancel() }
        initialFetchTasks.removeAll()
        syncService.stopListening()
        syncService.onTrackChanged = nil
        // No `clearArtworkCache()` here: its only job here was to reset the
        // "already tried" sets, which is exactly what made every reopening of
        // the drawer retry the whole artwork and lyrics chain for a track that
        // had already failed. A forced re-fetch is an explicit action, not a
        // drawer closing.
        track.artworkData = nil
        track.lyrics = nil
        track.syncedLyrics = nil
        save()
        if boundStore === store {
            boundStore = nil
        }
    }
}
