// Tests/PurahCoreTests/MusicModuleSeamTests.swift
import Testing
import Foundation
@testable import PurahCore
@testable import PurahUI

@Suite("Music Playback Module Seam Tests")
struct MusicModuleSeamTests {

    @Test("LRCParser parses timestamps, skips metadata headers, sorts chronologically, and resolves active line")
    func testLRCParser() {
        let raw = """
        [ti:Demo Track]
        [ar:Purah]
        [00:12.50]Second line
        [00:05.250]First line
        [01:02.00]Third line
        """
        let lines = LRCParser.parse(raw)
        #expect(lines.count == 3)
        #expect(lines[0].text == "First line")
        #expect(abs(lines[0].time - 5.25) < 0.001)
        #expect(lines[1].text == "Second line")
        #expect(abs(lines[1].time - 12.5) < 0.001)
        #expect(lines[2].text == "Third line")
        #expect(abs(lines[2].time - 62.0) < 0.001)

        #expect(LRCParser.activeLine(in: raw, at: 5.0) == "First line")
        #expect(LRCParser.activeLine(in: raw, at: 15.0) == "Second line")
        #expect(LRCParser.activeLine(in: raw, at: 70.0) == "Third line")
    }

    @Test("AudioOutputDevice selects icon by device name in PurahCore")
    func testAudioOutputDeviceIcons() {
        #expect(AudioOutputDevice(id: 1, name: "AirPods Pro").systemIcon == "airpodspro")
        #expect(AudioOutputDevice(id: 2, name: "Studio Display Speakers").systemIcon == "display")
        #expect(AudioOutputDevice(id: 3, name: "Sony Headphones").systemIcon == "headphones")
        #expect(AudioOutputDevice(id: 4, name: "MacBook Pro Speakers").systemIcon == "speaker.wave.2.fill")
    }

    @Test("MusicPluginState.mergeTrackFields preserves lyrics, artwork, source identity, and user preferences")
    @MainActor
    func testMergeTrackFieldsPreservation() {
        var existing = MusicTrackInfo(title: "Track A", artist: "Artist B")
        existing.lyrics = "plain"
        existing.syncedLyrics = "[00:01.00]synced"
        existing.artworkData = Data([1, 2, 3])
        existing.sourceBundleId = "com.apple.Music"
        existing.sourceApp = "Music"
        existing.lyricsOffsetSeconds = -1.5
        existing.isLyricsHidden = true
        existing.selectedLyricsCandidateId = "cand-1"

        var incoming = MusicTrackInfo(title: "Track A", artist: "Artist B")
        incoming.sourceApp = "Media Player"

        let merged = MusicPluginState.mergeTrackFields(
            incoming: incoming,
            existing: existing,
            preserveLyricsPreferences: true
        )
        #expect(merged.lyrics == "plain")
        #expect(merged.syncedLyrics == "[00:01.00]synced")
        #expect(merged.artworkData == Data([1, 2, 3]))
        #expect(merged.sourceBundleId == "com.apple.Music")
        #expect(merged.sourceApp == "Music")
        #expect(merged.lyricsOffsetSeconds == -1.5)
        #expect(merged.isLyricsHidden == true)
        #expect(merged.selectedLyricsCandidateId == "cand-1")

        // Different track does not inherit stale metadata
        let nextTrack = MusicTrackInfo(title: "Track C", artist: "Artist D")
        let nextMerged = MusicPluginState.mergeTrackFields(
            incoming: nextTrack,
            existing: existing,
            preserveLyricsPreferences: true
        )
        #expect(nextMerged.lyrics == nil)
        #expect(nextMerged.artworkData == nil)
    }

    @Test("MusicPluginState binds to injected SystemMusicSyncService instead of global shared")
    @MainActor
    func testMusicPluginStateServiceInjection() {
        let suiteName = "purah.test.music.inject.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let customSync = SystemMusicSyncService()
        let state = MusicPluginState(
            storage: ScopedPluginStorage(pluginId: "music", defaults: defaults),
            syncService: customSync
        )
        #expect(state.syncService === customSync)
        #expect(state.syncService !== SystemMusicSyncService.shared)
    }
}
