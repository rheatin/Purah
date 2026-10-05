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
    public var waveformSamples: [Double] // 归一化振幅
    public var artworkData: Data?
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
        waveformSamples: [Double] = [0.2, 0.5, 0.8, 0.3, 0.9, 0.6, 0.4, 0.7, 0.5, 0.3],
        artworkData: Data? = nil,
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
        self.waveformSamples = waveformSamples
        self.artworkData = artworkData
        self.sourceApp = sourceApp
        self.sourceBundleId = sourceBundleId
    }
}
