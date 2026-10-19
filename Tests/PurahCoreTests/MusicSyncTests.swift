// Tests/PurahCoreTests/MusicSyncTests.swift
import Testing
import Foundation
import SwiftUI
import AppKit
@testable import PurahCore
@testable import PurahUI

@Suite("System Music Sync Tests")
@MainActor
struct MusicSyncTests {
    @Test("Processes Music.app notification userInfo correctly")
    func testNotificationParsing() {
        let store = PurahWorkspaceStore()
        let service = SystemMusicSyncService()

        let userInfo: [String: Any] = [
            "Player State": "Playing",
            "Name": "Ballad of the Goddess",
            "Artist": "Koji Kondo",
            "Total Time": 210000.0,
            "Player Position": 105.0
        ]
        let notification = Notification(
            name: Notification.Name("com.apple.Music.playerInfo"),
            object: nil,
            userInfo: userInfo
        )

        service.handlePlayerInfo(notification: notification, store: store)

        #expect(store._musicTrack.title == "Ballad of the Goddess")
        #expect(store._musicTrack.artist == "Koji Kondo")
        #expect(store._musicTrack.isPlaying == true)
        #expect(abs(store._musicTrack.playbackProgress - 0.5) < 0.05)
    }

    @Test("Toggles play pause in-memory fallback")
    func testPlayPauseFallback() {
        let store = PurahWorkspaceStore()
        let service = SystemMusicSyncService()
        let originalState = store._musicTrack.isPlaying

        service.togglePlayPause(store: store)
        #expect(store._musicTrack.isPlaying != originalState)
    }

    @Test("MusicTrackInfo supports local lyrics property and artwork caching")
    func testMusicTrackLyricsAndArtwork() {
        var track = MusicTrackInfo(
            title: "会呼吸的痛",
            artist: "梁静茹",
            album: "崇拜",
            lyrics: "在东京铁塔 第一次眺望\n看灯火模仿 坠落的星光"
        )
        #expect(track.lyrics != nil)
        #expect(track.lyrics?.contains("东京铁塔") == true)

        let dummyData = "mock-artwork-bytes".data(using: .utf8)
        track.artworkData = dummyData
        #expect(track.artworkData == dummyData)
    }

    @Test("Time anchor model ensures linear monotonic calculation without position corruption")
    func testTimeAnchorMonotonicCalculation() {
        let initialTime = Date()
        let track = MusicTrackInfo(
            title: "Test Track",
            artist: "Artist",
            isPlaying: true,
            currentPositionSeconds: 60.0,
            durationSeconds: 180.0,
            lastUpdated: initialTime,
            playbackRate: 1.0
        )

        // currentPositionSeconds remains constant ground truth
        #expect(track.currentPositionSeconds == 60.0)
        // calculatedCurrentTime is strictly >= currentPositionSeconds
        #expect(track.calculatedCurrentTime >= 60.0)
        #expect(track.calculatedProgress >= (60.0 / 180.0))
    }

    @Test("Pausing music preserves elapsed playback position without resetting or scrambling")
    func testPlayPausePreservesElapsedTime() async throws {
        let store = PurahWorkspaceStore()
        let service = SystemMusicSyncService()

        // 1. Simulate track playing from 20 seconds ago starting at position 40.0s
        let initialAnchor = Date().addingTimeInterval(-20.0)
        store._musicTrack = MusicTrackInfo(
            title: "Song of Storms",
            artist: "Koji Kondo",
            isPlaying: true,
            playbackProgress: 0.20,
            currentPositionSeconds: 40.0,
            durationSeconds: 200.0,
            lastUpdated: initialAnchor,
            playbackRate: 1.0
        )

        #expect(store._musicTrack.calculatedCurrentTime >= 59.5)

        // 2. Pause playback
        service.togglePlayPause(store: store)

        #expect(store._musicTrack.isPlaying == false)
        #expect(store._musicTrack.playbackRate == 0.0)
        // Current position must be frozen at elapsed time (~60s), NOT reset to 40.0s or 0.0s!
        let pausedPos = store._musicTrack.currentPositionSeconds
        #expect(pausedPos >= 59.0 && pausedPos <= 65.0)
        #expect(store._musicTrack.calculatedCurrentTime == pausedPos)
        #expect(abs(store._musicTrack.playbackProgress - (pausedPos / 200.0)) < 0.01)

        // 3. Verify paused position remains strictly rock-solid over time without drift
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        #expect(store._musicTrack.calculatedCurrentTime == pausedPos)

        // 4. Resume playback
        service.togglePlayPause(store: store)
        #expect(store._musicTrack.isPlaying == true)
        #expect(store._musicTrack.playbackRate == 1.0)
        #expect(store._musicTrack.calculatedCurrentTime >= pausedPos)
    }

    @Test("Pause notification with missing or zero position does not wipe out current playback position")
    func testPauseNotificationRetainsCurrentPosition() {
        let store = PurahWorkspaceStore()
        let service = SystemMusicSyncService()

        // Simulate active track at 88 seconds
        store._musicTrack = MusicTrackInfo(
            title: "Gerudo Valley",
            artist: "Koji Kondo",
            isPlaying: true,
            currentPositionSeconds: 88.0,
            durationSeconds: 240.0,
            lastUpdated: Date(),
            playbackRate: 1.0
        )

        // Notification arrives indicating Paused, but omitting Player Position (standard macOS Apple Music behavior)
        let userInfo: [String: Any] = [
            "Player State": "Paused",
            "Name": "Gerudo Valley",
            "Artist": "Koji Kondo",
            "Total Time": 240000.0
        ]
        let notification = Notification(
            name: Notification.Name("com.apple.Music.playerInfo"),
            object: nil,
            userInfo: userInfo
        )

        service.handlePlayerInfo(notification: notification, store: store)

        #expect(store._musicTrack.isPlaying == false)
        #expect(store._musicTrack.currentPositionSeconds >= 87.5)
        #expect(store._musicTrack.playbackProgress >= (87.0 / 240.0))
    }

    @Test("extractNumericValue parses NSNumber, Double, Int, String, and nil robustly")
    func testExtractNumericValue() {
        #expect(SystemMusicSyncService.extractNumericValue(from: NSNumber(value: 42)) == 42.0)
        #expect(SystemMusicSyncService.extractNumericValue(from: Double(3.14)) == 3.14)
        #expect(SystemMusicSyncService.extractNumericValue(from: Int(100)) == 100.0)
        #expect(SystemMusicSyncService.extractNumericValue(from: "250.5") == 250.5)
        #expect(SystemMusicSyncService.extractNumericValue(from: nil) == nil)
        #expect(SystemMusicSyncService.extractNumericValue(from: "invalid") == nil)
    }

    @Test("MediaRemote bridge is dynamically available on macOS")
    func testMediaRemoteBridgeAvailability() {
        let bridge = SystemMediaRemoteBridge.shared
        #expect(bridge.isAvailable == true)
    }

    @Test("Processes MediaRemote multimedia dictionary correctly for system-wide players")
    func testProcessMediaRemoteData() {
        let store = PurahWorkspaceStore()
        let service = SystemMusicSyncService()

        let dummyArtwork = "test-art-bytes".data(using: .utf8)
        let dict: [String: Any] = [
            "kMRMediaRemoteNowPlayingInfoTitle": "Never Gonna Give You Up",
            "kMRMediaRemoteNowPlayingInfoArtist": "Rick Astley",
            "kMRMediaRemoteNowPlayingInfoAlbum": "Whenever You Need Somebody",
            "kMRMediaRemoteNowPlayingInfoDuration": 213.0,
            "kMRMediaRemoteNowPlayingInfoElapsedTime": 75.0,
            "kMRMediaRemoteNowPlayingInfoPlaybackRate": 1.0,
            "kMRMediaRemoteNowPlayingInfoArtworkData": dummyArtwork as Any,
            "kMRMediaRemoteNowPlayingInfoIsMusicApp": false
        ]

        service.processMediaRemoteData(dict: dict, pid: 0, store: store)

        #expect(store._musicTrack.title == "Never Gonna Give You Up")
        #expect(store._musicTrack.artist == "Rick Astley")
        #expect(store._musicTrack.isPlaying == true)
        #expect(store._musicTrack.currentPositionSeconds == 75.0)
        #expect(store._musicTrack.durationSeconds == 213.0)
        #expect(store._musicTrack.artworkData == dummyArtwork)
        #expect(store._musicTrack.sourceApp == "Media Player")
    }

    @Test("MusicTrackInfo sourceIconName resolves appropriate SF Symbols")
    func testMusicTrackInfoSourceIconName() {
        let spotify = MusicTrackInfo(sourceApp: "Spotify")
        #expect(spotify.sourceIconName == "waveform")

        let safari = MusicTrackInfo(sourceApp: "Safari")
        #expect(safari.sourceIconName == "globe")

        let chrome = MusicTrackInfo(sourceApp: "Google Chrome")
        #expect(chrome.sourceIconName == "globe")

        let podcast = MusicTrackInfo(sourceApp: "Podcasts")
        #expect(podcast.sourceIconName == "antenna.radiowaves.left.and.right")

        let appleMusic = MusicTrackInfo(sourceApp: "Apple Music")
        #expect(appleMusic.sourceIconName == "music.note")
    }

    @Test("Preserves lyrics and syncedLyrics across 2s heartbeat updates in MediaRemote, Apple Music, and Spotify")
    func testLyricsPreservedAcrossHeartbeatUpdates() {
        let store = PurahWorkspaceStore()
        let service = SystemMusicSyncService.shared
        let state = MusicPluginState(storage: ScopedPluginStorage(pluginId: "music_test_\(UUID().uuidString)"))
        state.mount(store: store)

        let plainText = "Line one of lyrics\nLine two of lyrics"
        let syncedLrc = "[00:10.00] Line one of lyrics\n[00:20.00] Line two of lyrics"

        store._musicTrack = MusicTrackInfo(
            title: "Starlight",
            artist: "Muse",
            album: "Black Holes and Revelations",
            isPlaying: true,
            currentPositionSeconds: 12.0,
            durationSeconds: 240.0,
            lyrics: plainText,
            syncedLyrics: syncedLrc
        )
        state.track = store._musicTrack

        // 1. Simulate 2.0s MediaRemote heartbeat update for the same track
        let mediaRemoteDict: [String: Any] = [
            "kMRMediaRemoteNowPlayingInfoTitle": "Starlight",
            "kMRMediaRemoteNowPlayingInfoArtist": "Muse",
            "kMRMediaRemoteNowPlayingInfoAlbum": "Black Holes and Revelations",
            "kMRMediaRemoteNowPlayingInfoDuration": 240.0,
            "kMRMediaRemoteNowPlayingInfoElapsedTime": 14.0,
            "kMRMediaRemoteNowPlayingInfoPlaybackRate": 1.0
        ]
        service.processMediaRemoteData(dict: mediaRemoteDict, pid: 0, store: store)

        #expect(store._musicTrack.lyrics == plainText, "processMediaRemoteData must preserve existing plain lyrics")
        #expect(store._musicTrack.syncedLyrics == syncedLrc, "processMediaRemoteData must preserve existing synced lyrics")
        #expect(state.track.lyrics == plainText, "MusicPluginState.track must preserve plain lyrics after heartbeat")
        #expect(state.track.syncedLyrics == syncedLrc, "MusicPluginState.track must preserve synced lyrics after heartbeat")

        // 2. Simulate Apple Music notification for the same track
        let appleMusicNotif = Notification(
            name: Notification.Name("com.apple.Music.playerInfo"),
            object: nil,
            userInfo: [
                "Player State": "Playing",
                "Name": "Starlight",
                "Artist": "Muse",
                "Album": "Black Holes and Revelations",
                "Total Time": 240000.0,
                "Player Position": 16.0
            ]
        )
        service.handleAppleMusicInfo(notification: appleMusicNotif, store: store)

        #expect(store._musicTrack.lyrics == plainText, "handleAppleMusicInfo must preserve existing plain lyrics")
        #expect(store._musicTrack.syncedLyrics == syncedLrc, "handleAppleMusicInfo must preserve existing synced lyrics")
        #expect(state.track.lyrics == plainText)
        #expect(state.track.syncedLyrics == syncedLrc)

        // 3. Simulate Spotify notification for the same track
        let spotifyNotif = Notification(
            name: Notification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil,
            userInfo: [
                "Player State": "Playing",
                "Name": "Starlight",
                "Artist": "Muse",
                "Album": "Black Holes and Revelations",
                "Duration": 240000.0,
                "Playback Position": 18.0
            ]
        )
        service.handleSpotifyInfo(notification: spotifyNotif, store: store)

        #expect(store._musicTrack.lyrics == plainText, "handleSpotifyInfo must preserve existing plain lyrics")
        #expect(store._musicTrack.syncedLyrics == syncedLrc, "handleSpotifyInfo must preserve existing synced lyrics")
        #expect(state.track.lyrics == plainText)
        #expect(state.track.syncedLyrics == syncedLrc)

        // 4. Verify cachedLyrics fallback when store track is recreated
        service.cacheLyrics(
            for: "Cached Song",
            artist: "Cached Artist",
            result: OnlineLyricsResult(plainLyrics: "Cached plain", syncedLyrics: "[00:05.00] Cached synced")
        )
        let cachedDict: [String: Any] = [
            "kMRMediaRemoteNowPlayingInfoTitle": "Cached Song",
            "kMRMediaRemoteNowPlayingInfoArtist": "Cached Artist",
            "kMRMediaRemoteNowPlayingInfoDuration": 180.0,
            "kMRMediaRemoteNowPlayingInfoElapsedTime": 5.0,
            "kMRMediaRemoteNowPlayingInfoPlaybackRate": 1.0
        ]
        service.processMediaRemoteData(dict: cachedDict, pid: 0, store: store)
        #expect(store._musicTrack.lyrics == "Cached plain")
        #expect(store._musicTrack.syncedLyrics == "[00:05.00] Cached synced")
    }

    @Test("Default sample tracks populate synced LRC lyrics out of the box and ultra-flat MusicDrawerView renders cleanly")
    func testDefaultSampleLyricsAndUltraFlatDrawer() {
        let defaultZelda = MusicTrackInfo()
        #expect(defaultZelda.lyrics != nil)
        #expect(defaultZelda.syncedLyrics != nil)

        let defaultMidnight = MusicTrackInfo(title: "Midnight City", artist: "M83")
        #expect(defaultMidnight.lyrics != nil)
        #expect(defaultMidnight.syncedLyrics != nil)

        let store = PurahWorkspaceStore()
        let state = MusicPluginState(storage: ScopedPluginStorage(pluginId: "music_flat_test_\(UUID().uuidString)"))
        let ultraFlatHosting = NSHostingView(
            rootView: MusicDrawerView(state: state, store: store)
                .frame(width: 320, height: 42)
        )
        ultraFlatHosting.frame = NSRect(x: 0, y: 0, width: 320, height: 42)
        ultraFlatHosting.layoutSubtreeIfNeeded()
        #expect(ultraFlatHosting.fittingSize.width > 0)
    }

    @Test("MusicPlugin.normalizedSourceDisplayName and MusicDrawerView.resolveSourceAppIcon resolve cleanly")
    func testNormalizedSourceDisplayNameAndAppIconResolution() {
        #expect(MusicPlugin.normalizedSourceDisplayName(sourceApp: "Music") == "Apple Music")
        #expect(MusicPlugin.normalizedSourceDisplayName(sourceApp: "Apple Music") == "Apple Music")
        #expect(MusicPlugin.normalizedSourceDisplayName(sourceApp: "Player", bundleId: "com.apple.Music") == "Apple Music")
        #expect(MusicPlugin.normalizedSourceDisplayName(sourceApp: "Spotify") == "Spotify")
        #expect(MusicPlugin.normalizedSourceDisplayName(sourceApp: "Google Chrome") == "Chrome")
        #expect(MusicPlugin.normalizedSourceDisplayName(sourceApp: "Safari") == "Safari")

        let appleMusicIcon = MusicDrawerView.resolveSourceAppIcon(sourceApp: "Apple Music", bundleId: "com.apple.Music")
        #expect(appleMusicIcon != nil)
    }
}
