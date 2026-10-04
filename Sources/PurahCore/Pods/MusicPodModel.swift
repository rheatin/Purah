// Sources/PurahCore/Pods/MusicPodModel.swift
import Foundation

public struct MusicTrackInfo: Codable, Sendable {
    public var title: String
    public var artist: String
    public var isPlaying: Bool
    public var playbackProgress: Double // 0.0 ~ 1.0
    public var waveformSamples: [Double] // 10 个归一化振幅

    public init(
        title: String = "Zelda's Lullaby",
        artist: String = "Purah OST",
        isPlaying: Bool = true,
        playbackProgress: Double = 0.42,
        waveformSamples: [Double] = [0.2, 0.5, 0.8, 0.3, 0.9, 0.6, 0.4, 0.7, 0.5, 0.3]
    ) {
        self.title = title
        self.artist = artist
        self.isPlaying = isPlaying
        self.playbackProgress = playbackProgress
        self.waveformSamples = waveformSamples
    }
}
