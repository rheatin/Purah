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

        #expect(store.musicTrack.title == "Ballad of the Goddess")
        #expect(store.musicTrack.artist == "Koji Kondo")
        #expect(store.musicTrack.isPlaying == true)
        #expect(abs(store.musicTrack.playbackProgress - 0.5) < 0.05)
    }

    @Test("Toggles play pause in-memory fallback")
    func testPlayPauseFallback() {
        let store = PurahWorkspaceStore()
        let service = SystemMusicSyncService()
        let originalState = store.musicTrack.isPlaying

        service.togglePlayPause(store: store)
        #expect(store.musicTrack.isPlaying != originalState)
    }
}
