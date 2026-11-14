// Sources/PurahCore/Pods/MusicPodModel.swift
import Foundation

public struct LyricsCandidate: Identifiable, Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var artist: String
    public var album: String?
    public var durationSeconds: Double?
    public var source: String // "LRCLIB" or "NetEase"
    public var plainLyrics: String?
    public var syncedLyrics: String?
    public var score: Double

    public init(
        id: String,
        title: String,
        artist: String,
        album: String? = nil,
        durationSeconds: Double? = nil,
        source: String,
        plainLyrics: String? = nil,
        syncedLyrics: String? = nil,
        score: Double = 0.0
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.durationSeconds = durationSeconds
        self.source = source
        self.plainLyrics = plainLyrics
        self.syncedLyrics = syncedLyrics
        self.score = score
    }

    public var displayLabel: String {
        let durationStr: String
        if let dur = durationSeconds, dur > 0 {
            let m = Int(dur) / 60
            let s = Int(dur) % 60
            durationStr = String(format: " (%d:%02d)", m, s)
        } else {
            durationStr = ""
        }
        return "\(title) - \(artist)\(durationStr) · \(source)"
    }
}

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
    public var waveformSamples: [Double] // Normalized amplitudes (0.0 to 1.0)
    public var artworkData: Data?
    public var lyrics: String?
    public var syncedLyrics: String?
    public var sourceApp: String // "Apple Music", "Spotify", "Chrome", etc.
    public var sourceBundleId: String // "com.apple.Music", etc.
    public var lyricsOffsetSeconds: Double
    public var isLyricsHidden: Bool
    public var selectedLyricsCandidateId: String?
    public var lyricsCandidates: [LyricsCandidate]

    public static let defaultSampleSyncedLyrics: String = """
    [00:00.00] ♪ Ambient Sheikah Slate Resonance ♪
    [00:15.00] Across the quiet skies of Hyrule
    [00:32.00] Ancient towers hum in golden light
    [00:50.00] Watch the stars align above the clouds
    [01:10.00] Every memory echoes through the wind
    [01:28.00] Close your eyes and hear the lullaby
    [01:50.00] Guiding courage through the endless night
    [02:15.00] Dawn awakens on the distant ridge
    [02:45.00] ♪ Zelda's Lullaby — Purah Symphonic Mix ♪
    """

    public static let defaultSamplePlainLyrics: String = """
    ♪ Ambient Sheikah Slate Resonance ♪
    Across the quiet skies of Hyrule
    Ancient towers hum in golden light
    Watch the stars align above the clouds
    Every memory echoes through the wind
    Close your eyes and hear the lullaby
    Guiding courage through the endless night
    Dawn awakens on the distant ridge
    ♪ Zelda's Lullaby — Purah Symphonic Mix ♪
    """

    public static let empty = MusicTrackInfo(
        title: "",
        artist: "",
        album: "",
        isPlaying: false,
        playbackProgress: 0.0,
        currentPositionSeconds: 0.0,
        durationSeconds: 0.0,
        playbackRate: 0.0,
        waveformSamples: [],
        sourceApp: "",
        sourceBundleId: ""
    )

    public var isSamplePlaceholder: Bool {
        (title == "Zelda's Lullaby" && artist == "Purah OST")
            || (title == "Midnight City" && lyrics == Self.defaultSamplePlainLyrics)
    }

    public init(
        title: String = "Zelda's Lullaby",
        artist: String = "Purah OST",
        album: String = "Tears of the Kingdom",
        isPlaying: Bool? = nil,
        playbackProgress: Double = 0.42,
        currentPositionSeconds: Double = 88.0,
        durationSeconds: Double = 210.0,
        lastUpdated: Date = Date(),
        playbackRate: Double = 0.0,
        waveformSamples: [Double] = [0.2, 0.5, 0.8, 0.3, 0.9, 0.6, 0.4, 0.7, 0.5, 0.3],
        artworkData: Data? = nil,
        lyrics: String? = nil,
        syncedLyrics: String? = nil,
        sourceApp: String = "Apple Music",
        sourceBundleId: String = "com.apple.Music",
        lyricsOffsetSeconds: Double = 0.0,
        isLyricsHidden: Bool = false,
        selectedLyricsCandidateId: String? = nil,
        lyricsCandidates: [LyricsCandidate] = []
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        let resolvedPlaying = isPlaying ?? (playbackRate > 0)
        self.isPlaying = resolvedPlaying
        self.playbackProgress = playbackProgress
        self.currentPositionSeconds = currentPositionSeconds
        self.durationSeconds = durationSeconds
        self.lastUpdated = lastUpdated
        self.playbackRate = playbackRate != 0.0 ? playbackRate : (resolvedPlaying ? 1.0 : 0.0)
        self.waveformSamples = waveformSamples
        self.artworkData = artworkData
        if (title == "Zelda's Lullaby" || title == "Midnight City") && lyrics == nil && syncedLyrics == nil {
            self.lyrics = Self.defaultSamplePlainLyrics
            self.syncedLyrics = Self.defaultSampleSyncedLyrics
        } else {
            self.lyrics = lyrics
            self.syncedLyrics = syncedLyrics
        }
        self.sourceApp = sourceApp
        self.sourceBundleId = sourceBundleId
        self.lyricsOffsetSeconds = lyricsOffsetSeconds
        self.isLyricsHidden = isLyricsHidden
        self.selectedLyricsCandidateId = selectedLyricsCandidateId
        self.lyricsCandidates = lyricsCandidates
    }

    enum CodingKeys: String, CodingKey {
        case title, artist, album, isPlaying, playbackProgress, currentPositionSeconds
        case durationSeconds, lastUpdated, playbackRate, waveformSamples, artworkData
        case lyrics, syncedLyrics, sourceApp, sourceBundleId
        case lyricsOffsetSeconds, isLyricsHidden, selectedLyricsCandidateId, lyricsCandidates
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.title = try c.decode(String.self, forKey: .title)
        self.artist = try c.decode(String.self, forKey: .artist)
        self.album = try c.decode(String.self, forKey: .album)
        self.isPlaying = try c.decode(Bool.self, forKey: .isPlaying)
        self.playbackProgress = try c.decode(Double.self, forKey: .playbackProgress)
        self.currentPositionSeconds = try c.decode(Double.self, forKey: .currentPositionSeconds)
        self.durationSeconds = try c.decode(Double.self, forKey: .durationSeconds)
        self.lastUpdated = try c.decode(Date.self, forKey: .lastUpdated)
        self.playbackRate = try c.decode(Double.self, forKey: .playbackRate)
        self.waveformSamples = try c.decode([Double].self, forKey: .waveformSamples)
        self.artworkData = try c.decodeIfPresent(Data.self, forKey: .artworkData)
        self.lyrics = try c.decodeIfPresent(String.self, forKey: .lyrics)
        self.syncedLyrics = try c.decodeIfPresent(String.self, forKey: .syncedLyrics)
        self.sourceApp = try c.decode(String.self, forKey: .sourceApp)
        self.sourceBundleId = try c.decode(String.self, forKey: .sourceBundleId)
        self.lyricsOffsetSeconds = try c.decodeIfPresent(Double.self, forKey: .lyricsOffsetSeconds) ?? 0.0
        self.isLyricsHidden = try c.decodeIfPresent(Bool.self, forKey: .isLyricsHidden) ?? false
        self.selectedLyricsCandidateId = try c.decodeIfPresent(String.self, forKey: .selectedLyricsCandidateId)
        self.lyricsCandidates = try c.decodeIfPresent([LyricsCandidate].self, forKey: .lyricsCandidates) ?? []
    }

    /// Whether two snapshots would render the same thing.
    ///
    /// The 2s heartbeat rebuilds this struct on every poll. Assigning it back
    /// to the store invalidates every view that reads it, so a paused player
    /// was repainting the rail twice a second with identical content.
    /// `lastUpdated` is the time anchor and `waveformSamples` is visual noise,
    /// so neither counts as a change; `playbackProgress` does, which is what
    /// keeps a playing track moving.
    public func matchesVisibleState(of other: MusicTrackInfo) -> Bool {
        title == other.title
            && artist == other.artist
            && album == other.album
            && isPlaying == other.isPlaying
            && playbackRate == other.playbackRate
            && abs(currentPositionSeconds - other.currentPositionSeconds) < 0.5
            && abs(durationSeconds - other.durationSeconds) < 0.5
            && artworkData?.count == other.artworkData?.count
            && lyrics == other.lyrics
            && syncedLyrics == other.syncedLyrics
            && sourceApp == other.sourceApp
            && sourceBundleId == other.sourceBundleId
            && lyricsOffsetSeconds == other.lyricsOffsetSeconds
            && isLyricsHidden == other.isLyricsHidden
            && selectedLyricsCandidateId == other.selectedLyricsCandidateId
            && lyricsCandidates.count == other.lyricsCandidates.count
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

    public var sourceIconName: String {
        let lower = sourceApp.lowercased()
        if lower.contains("spotify") {
            return "waveform"
        } else if lower.contains("chrome") || lower.contains("safari") || lower.contains("browser") || lower.contains("edge") || lower.contains("arc") || lower.contains("firefox") {
            return "globe"
        } else if lower.contains("podcast") {
            return "antenna.radiowaves.left.and.right"
        } else {
            return "music.note"
        }
    }
}
