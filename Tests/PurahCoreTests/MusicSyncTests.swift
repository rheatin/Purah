// Tests/PurahCoreTests/MusicSyncTests.swift
import Testing
import Foundation
@testable import PurahCore

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
}
