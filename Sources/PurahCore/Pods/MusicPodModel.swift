// Sources/PurahCore/Pods/MusicPodModel.swift
import Foundation

public struct MusicTrackInfo: Codable, Sendable {
    public var title: String
    public var artist: String
    public var album: String
    public var isPlaying: Bool
    public var playbackProgress: Double // 0.0 ~ 1.0
    public var currentPositionSeconds: Double
    public var durationSeconds: Double
    public var lastUpdated: Date
    public var playbackRate: Double
    public var waveformSamples: [Double] // 归一化振幅
    public var artworkData: Data?
    public var lyrics: String?
    public var sourceApp: String // "Apple Music", "Spotify", "Chrome", etc.
    public var sourceBundleId: String // "com.apple.Music", etc.

    public init(
        title: String = "Zelda's Lullaby",
        artist: String = "Purah OST",
        album: String = "Tears of the Kingdom",
        isPlaying: Bool = true,
        playbackProgress: Double = 0.42,
        currentPositionSeconds: Double = 88.0,
        durationSeconds: Double = 210.0,
        lastUpdated: Date = Date(),
        playbackRate: Double = 1.0,
        waveformSamples: [Double] = [0.2, 0.5, 0.8, 0.3, 0.9, 0.6, 0.4, 0.7, 0.5, 0.3],
        artworkData: Data? = nil,
        lyrics: String? = nil,
        sourceApp: String = "Apple Music",
        sourceBundleId: String = "com.apple.Music"
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.isPlaying = isPlaying
        self.playbackProgress = playbackProgress
        self.currentPositionSeconds = currentPositionSeconds
        self.durationSeconds = durationSeconds
        self.lastUpdated = lastUpdated
        self.playbackRate = playbackRate
        self.waveformSamples = waveformSamples
        self.artworkData = artworkData
        self.lyrics = lyrics
        self.sourceApp = sourceApp
        self.sourceBundleId = sourceBundleId
    }

    public var calculatedCurrentTime: Double {
        if isPlaying && playbackRate > 0 {
            let elapsed = Date().timeIntervalSince(lastUpdated) * playbackRate
            return min(max(currentPositionSeconds + elapsed, 0.0), durationSeconds)
        }
        return min(max(currentPositionSeconds, 0.0), durationSeconds)
    }

    public var calculatedProgress: Double {
        guard durationSeconds > 0 else { return 0.0 }
        return min(max(calculatedCurrentTime / durationSeconds, 0.0), 1.0)
    }
}
