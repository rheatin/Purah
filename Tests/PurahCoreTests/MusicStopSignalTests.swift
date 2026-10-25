// Tests/PurahCoreTests/MusicStopSignalTests.swift
import Testing
import Foundation
@testable import PurahCore

/// Dynamic.music clears its Now-Playing dictionary on pause. The sync service
/// used to swallow that empty payload, freezing the rail on "playing" forever.
@Suite @MainActor
struct MusicStopSignalTests {

    private func makePlayingTrack() -> MusicTrackInfo {
        var track = MusicTrackInfo()
        track.title = "Hyrule Ambience"
        track.artist = "Dynamic.music"
        track.isPlaying = true
        track.playbackRate = 1.0
        track.currentPositionSeconds = 42.0
        track.waveformSamples = [0.8, 0.5, 0.9]
        return track
    }

    @Test func emptyNowPlayingPayloadPausesStuckTrack() {
        let service = SystemMusicSyncService.shared
        let store = PurahWorkspaceStore()
        store._musicTrack = makePlayingTrack()

        service.processMediaRemoteData(dict: [:], pid: 0, store: store)

        #expect(!store._musicTrack.isPlaying)
        #expect(store._musicTrack.playbackRate == 0.0)
        #expect(store._musicTrack.waveformSamples.allSatisfy { $0 == 0.15 })
    }

    @Test func stopSignalPreservesTrackIdentityAndAnchor() {
        let service = SystemMusicSyncService.shared
        let store = PurahWorkspaceStore()
        store._musicTrack = makePlayingTrack()
        let anchor = store._musicTrack.currentPositionSeconds

        service.processMediaRemoteData(dict: [:], pid: 0, store: store)

        #expect(store._musicTrack.title == "Hyrule Ambience")
        #expect(store._musicTrack.artist == "Dynamic.music")
        #expect(store._musicTrack.currentPositionSeconds == anchor)
    }

    @Test func repeatedEmptyPayloadsAreIdempotent() {
        let service = SystemMusicSyncService.shared
        let store = PurahWorkspaceStore()
        store._musicTrack = makePlayingTrack()

        service.processMediaRemoteData(dict: [:], pid: 0, store: store)
        let paused = store._musicTrack

        service.processMediaRemoteData(dict: [:], pid: 0, store: store)

        #expect(!store._musicTrack.isPlaying)
        #expect(store._musicTrack.playbackRate == paused.playbackRate)
        #expect(store._musicTrack.currentPositionSeconds == paused.currentPositionSeconds)
        #expect(store._musicTrack.title == paused.title)
    }

    @Test func payloadWithNonEmptyTitleStillWins() {
        let service = SystemMusicSyncService.shared
        let store = PurahWorkspaceStore()
        store._musicTrack = makePlayingTrack()

        var dict: [String: Any] = [:]
        dict["kMRMediaRemoteNowPlayingInfoTitle"] = "Ballad of the Goddess"
        dict["kMRMediaRemoteNowPlayingInfoPlaybackRate"] = 1.0
        service.processMediaRemoteData(dict: dict, pid: 0, store: store)

        #expect(store._musicTrack.isPlaying)
        #expect(store._musicTrack.title == "Ballad of the Goddess")
    }
}
