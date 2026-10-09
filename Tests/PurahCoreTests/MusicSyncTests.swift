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
}
