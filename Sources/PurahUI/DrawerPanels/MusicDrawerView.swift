// Sources/PurahUI/DrawerPanels/MusicDrawerView.swift
import SwiftUI
import AppKit
import PurahCore

public struct MusicDrawerView: View {
    public let state: MusicPluginState
    public let store: PurahWorkspaceStore

    @State private var isBackwardHovered: Bool = false
    @State private var isForwardHovered: Bool = false
    @State private var isPlayPauseHovered: Bool = false
    @State private var isScrubbing: Bool = false
    @State private var scrubbedProgress: Double = 0.0
    @State private var isShowingLyrics: Bool = false

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    private var musicColor: Color {
        palette.podColor(for: "music", store: store)
    }

    public init(state: MusicPluginState, store: PurahWorkspaceStore = PurahWorkspaceStore()) {
        self.state = state
        self.store = store
    }

    public init(store: PurahWorkspaceStore) {
        let pluginState = (PluginRegistry.shared.plugin(for: "music") as? MusicPlugin)?.state ?? MusicPluginState()
        self.init(state: pluginState, store: store)
    }

    public var body: some View {
        let isPlaying = state.isPlaying

        TimelineView(.periodic(from: .now, by: isPlaying ? 0.5 : 60.0)) { _ in
            let liveCurrentSec = state.track.calculatedCurrentTime
            let liveProgress = state.track.calculatedProgress

            let displayProgress = isScrubbing ? scrubbedProgress : liveProgress
            let displaySec = isScrubbing ? (scrubbedProgress * max(state.track.durationSeconds, 1.0)) : liveCurrentSec

            GeometryReader { geo in
                let h = geo.size.height

                if h < 145 {
                    // Tier 1: Compact Capsule (Consolidated 2-row layout, 0-clipping)
                    compactCapsuleView(displayProgress: displayProgress, displaySec: displaySec, isPlaying: isPlaying)
                } else if h < 265 {
                    // Tier 2: Classic Studio (Standard 3-row breathing layout)
                    classicStudioView(displayProgress: displayProgress, displaySec: displaySec, isPlaying: isPlaying)
                } else {
                    // Tier 3: Immersive Vinyl (Large artwork showcase & ambient dynamic glow)
                    immersiveVinylView(displayProgress: displayProgress, displaySec: displaySec, isPlaying: isPlaying, availableHeight: h)
                }
            }
        }
        .onAppear {
            state.mount(store: store)
        }
    }

    // MARK: - Tier 1: Compact Capsule Layout (< 155pt)
    @ViewBuilder
    private func compactCapsuleView(displayProgress: Double, displaySec: Double, isPlaying: Bool) -> some View {
        VStack(spacing: 8) {
            // Row 1: Micro Artwork + Title/Artist + Pin
            HStack(spacing: 8) {
                Button {
                    activateMusicPlayerApp()
                } label: {
                    HStack(spacing: 8) {
                        artworkThumbnail(size: 32, cornerRadius: 6)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(state.track.title)
                                .purahTitle(size: 11, weight: .bold, design: .rounded)
                                .foregroundColor(palette.style == .native ? Color.primary : .white)
                                .lineLimit(1)

                            Text(state.track.artist)
                                .purahBody(size: 9.5, weight: .medium, design: .rounded)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer(minLength: 4)
            }

            // Row 2: Inline Mini Transport Controls + Scrubber + Time
            HStack(spacing: 8) {
                // Micro transport buttons
                HStack(spacing: 4) {
                    Button {
                        state.previousTrack(store: store)
                    } label: {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(palette.style == .native ? Color.primary : .white)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)

                    Button {
                        state.togglePlayPause(store: store)
                    } label: {
                        ZStack {
                            Circle()
                                .fill(musicColor.opacity(0.20))
                                .frame(width: 26, height: 26)

                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(musicColor)
                        }
                    }
                    .buttonStyle(HeroPlayPauseButtonStyle())

                    Button {
                        state.nextTrack(store: store)
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(palette.style == .native ? Color.primary : .white)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                }

                // Compact Waveform
                FluidWaveformScrubber(
                    progress: displayProgress,
                    isPlaying: isPlaying,
                    color: musicColor,
                    samples: state.waveformSamples,
                    barCount: 22,
                    waveformHeight: 16,
                    onScrubChange: { dragging, prog in
                        isScrubbing = dragging
                        scrubbedProgress = prog
                    },
                    onSeek: { newProg in
                        isScrubbing = false
                        state.seek(to: newProg, store: store)
                    }
                )

                // Time Indicator (Compact single-label)
                Text("\(timeString(for: displaySec))/\(timeString(for: state.track.durationSeconds))")
                    .purahCaption(size: 8, weight: .medium, design: .monospaced)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    // MARK: - Tier 2: Classic Studio Layout (155pt ~ 235pt)
    @ViewBuilder
    private func classicStudioView(displayProgress: Double, displaySec: Double, isPlaying: Bool) -> some View {
        VStack(spacing: 8) {
            // Row 1: Artwork + Title/Artist + Pin
            HStack(spacing: 10) {
                Button {
                    activateMusicPlayerApp()
                } label: {
                    HStack(spacing: 10) {
                        artworkThumbnail(size: 42, cornerRadius: 8)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(state.track.title)
                                .purahTitle(size: 12.5, weight: .bold, design: .rounded)
                                .foregroundColor(palette.style == .native ? Color.primary : .white)
                                .lineLimit(1)

                            Text(state.track.artist)
                                .purahBody(size: 10, weight: .medium, design: .rounded)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer(minLength: 4)
            }

            // Row 2: Waveform + Dual Time Labels
            VStack(spacing: 3) {
                FluidWaveformScrubber(
                    progress: displayProgress,
                    isPlaying: isPlaying,
                    color: musicColor,
                    samples: state.waveformSamples,
                    barCount: 30,
                    waveformHeight: 20,
                    onScrubChange: { dragging, prog in
                        isScrubbing = dragging
                        scrubbedProgress = prog
                    },
                    onSeek: { newProg in
                        isScrubbing = false
                        state.seek(to: newProg, store: store)
                    }
                )

                HStack {
                    Text(timeString(for: displaySec))
                        .purahCaption(size: 8.5, weight: .medium, design: .monospaced)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(timeString(for: state.track.durationSeconds))
                        .purahCaption(size: 8.5, weight: .medium, design: .monospaced)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 2)

            // Row 3: Standard Transport Controls
            HStack(spacing: 26) {
                Button {
                    state.previousTrack(store: store)
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(palette.style == .native ? Color.primary : .white)
                        .frame(width: 30, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isBackwardHovered ? Color.primary.opacity(0.10) : Color.clear)
                        )
                }
                .buttonStyle(MediaNudgeButtonStyle(nudgeOffset: -4))
                .onHover { isBackwardHovered = $0 }

                Button {
                    state.togglePlayPause(store: store)
                } label: {
                    ZStack {
                        Circle()
                            .fill(musicColor.opacity(0.20))
                            .frame(width: 36, height: 36)
                            .modifier(OptionalGlow(color: musicColor, enabled: palette.useGlow))

                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(musicColor)
                    }
                    .frame(width: 36, height: 36)
                }
                .buttonStyle(HeroPlayPauseButtonStyle())

                Button {
                    state.nextTrack(store: store)
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(palette.style == .native ? Color.primary : .white)
                        .frame(width: 30, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isForwardHovered ? Color.primary.opacity(0.10) : Color.clear)
                        )
                }
                .buttonStyle(MediaNudgeButtonStyle(nudgeOffset: 4))
                .onHover { isForwardHovered = $0 }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    // MARK: - Tier 3: Immersive Vinyl Showcase Layout (>= 265pt)
    @ViewBuilder
    private func immersiveVinylView(displayProgress: Double, displaySec: Double, isPlaying: Bool, availableHeight: CGFloat) -> some View {
        let dynamicArtSize = min(max((availableHeight - 160) * 0.50, 60.0), 160.0)

        VStack(spacing: 8) {
            // Top Bar: Source Badge
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: sourceIconName(for: state.track.sourceApp))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(musicColor)
                    Text(state.track.sourceApp)
                        .purahCaption(size: 9, weight: .bold, design: .rounded)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(musicColor.opacity(0.12))
                .cornerRadius(5)

                Spacer()
            }

            Spacer(minLength: 2)

            if let lyrics = state.track.lyrics, !lyrics.isEmpty {
                // Direct Lyrics Showcase: Compact Track Bar + Flowing Lyrics Sheet
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        artworkThumbnail(size: 34, cornerRadius: 6)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(state.track.title)
                                .purahTitle(size: 11.5, weight: .bold, design: .rounded)
                                .foregroundColor(palette.style == .native ? Color.primary : .white)
                                .lineLimit(1)

                            Text(state.track.artist)
                                .purahBody(size: 9.5, weight: .medium, design: .rounded)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Image(systemName: "quote.bubble.fill")
                            .font(.system(size: 10))
                            .foregroundColor(musicColor)
                    }
                    .padding(.horizontal, 2)

                    let lyricsText = state.track.syncedLyrics ?? state.track.lyrics ?? lyrics
                    LyricsDisplayView(
                        rawLyrics: lyricsText,
                        currentTime: displaySec,
                        duration: max(state.track.durationSeconds, 1.0),
                        isPlaying: isPlaying,
                        accentColor: musicColor,
                        palette: palette,
                        maxHeight: max(availableHeight - 170, 110),
                        onSeek: { targetProg in
                            state.seek(to: targetProg, store: store)
                        }
                    )
                }
                .transition(.opacity)
            } else {
                // Center Artwork & Ambient Glow Showcase
                Button {
                    activateMusicPlayerApp()
                } label: {
                    VStack(spacing: 6) {
                        ZStack {
                            // Ambient dynamic radial glow
                            Circle()
                                .fill(musicColor.opacity(isPlaying ? 0.32 : 0.12))
                                .frame(width: dynamicArtSize + 8, height: dynamicArtSize + 8)
                                .blur(radius: 12)

                            artworkThumbnail(size: dynamicArtSize, cornerRadius: 10)
                        }

                        VStack(spacing: 2) {
                            Text(state.track.title)
                                .purahTitle(size: 13, weight: .bold, design: .rounded)
                                .foregroundColor(palette.style == .native ? Color.primary : .white)
                                .lineLimit(1)

                            Text(state.track.artist)
                                .purahBody(size: 10.5, weight: .medium, design: .rounded)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }

            Spacer(minLength: 2)

            // High-density Waveform Scrubber
            VStack(spacing: 3) {
                FluidWaveformScrubber(
                    progress: displayProgress,
                    isPlaying: isPlaying,
                    color: musicColor,
                    samples: state.waveformSamples,
                    barCount: 34,
                    waveformHeight: 22,
                    onScrubChange: { dragging, prog in
                        isScrubbing = dragging
                        scrubbedProgress = prog
                    },
                    onSeek: { newProg in
                        isScrubbing = false
                        state.seek(to: newProg, store: store)
                    }
                )

                HStack {
                    Text(timeString(for: displaySec))
                        .purahCaption(size: 8.5, weight: .medium, design: .monospaced)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(timeString(for: state.track.durationSeconds))
                        .purahCaption(size: 8.5, weight: .medium, design: .monospaced)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 2)

            // Prominent Transport Controls
            HStack(spacing: 32) {
                Button {
                    state.previousTrack(store: store)
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(palette.style == .native ? Color.primary : .white)
                        .frame(width: 32, height: 28)
                }
                .buttonStyle(MediaNudgeButtonStyle(nudgeOffset: -5))

                Button {
                    state.togglePlayPause(store: store)
                } label: {
                    ZStack {
                        Circle()
                            .fill(musicColor.opacity(0.22))
                            .frame(width: 40, height: 40)
                            .modifier(OptionalGlow(color: musicColor, enabled: palette.useGlow))

                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(musicColor)
                    }
                    .frame(width: 40, height: 40)
                }
                .buttonStyle(HeroPlayPauseButtonStyle())

                Button {
                    state.nextTrack(store: store)
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(palette.style == .native ? Color.primary : .white)
                        .frame(width: 32, height: 28)
                }
                .buttonStyle(MediaNudgeButtonStyle(nudgeOffset: 5))
            }
            .frame(maxWidth: .infinity)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    // MARK: - Reusable Artwork Thumbnail
    @ViewBuilder
    private func artworkThumbnail(size: CGFloat, cornerRadius: CGFloat) -> some View {
        ZStack(alignment: .bottomTrailing) {
            if let data = state.track.artworkData, let nsImg = NSImage(data: data) {
                Image(nsImage: nsImg)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(palette.borderColor.opacity(0.6), lineWidth: 1.0)
                    )
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(musicColor.opacity(0.15))
                        .frame(width: size, height: size)
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .stroke(musicColor.opacity(0.7), lineWidth: 1.2)
                        )
                        .modifier(OptionalGlow(color: musicColor, enabled: palette.useGlow))

                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.42, weight: .semibold))
                        .foregroundColor(musicColor)
                        .symbolEffect(.bounce, value: state.isPlaying)
                }
            }

            // Audio Source Badge
            let badgeSize: CGFloat = max(size * 0.32, 12.0)
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.85))
                    .frame(width: badgeSize, height: badgeSize)
                    .overlay(
                        Circle().stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                    )

                Image(systemName: sourceIconName(for: state.track.sourceApp))
                    .font(.system(size: badgeSize * 0.55, weight: .bold))
                    .foregroundColor(.white)
            }
            .offset(x: 2, y: 2)
        }
    }

    private func sourceIconName(for source: String) -> String {
        let lower = source.lowercased()
        if lower.contains("spotify") {
            return "waveform"
        } else if lower.contains("chrome") || lower.contains("safari") || lower.contains("browser") {
            return "globe"
        } else {
            return "music.note"
        }
    }

    private func activateMusicPlayerApp() {
        let source = state.track.sourceApp.lowercased()
        let bundleId = source.contains("spotify") ? "com.spotify.client" : "com.apple.Music"
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: appURL, configuration: config, completionHandler: nil)
        }
    }

    private func timeString(for seconds: Double) -> String {
        let total = max(Int(seconds), 0)
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - Reactive Tactile Button Styles for Media Controls
public struct MediaNudgeButtonStyle: ButtonStyle {
    public let nudgeOffset: CGFloat

    public init(nudgeOffset: CGFloat) {
        self.nudgeOffset = nudgeOffset
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .offset(x: configuration.isPressed ? nudgeOffset : 0)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.16, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

public struct HeroPlayPauseButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.16, dampingFraction: 0.60), value: configuration.isPressed)
    }
}

// MARK: - Metal GPU 60/120FPS Fluid Waveform Scrubber
public struct FluidWaveformScrubber: View {
    public let progress: Double
    public let isPlaying: Bool
    public let color: Color
    public let samples: [Double]
    public var barCount: Int = 30
    public var waveformHeight: CGFloat = 20
    public let onScrubChange: (Bool, Double) -> Void
    public let onSeek: (Double) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isScrubbing: Bool = false
    @State private var dragProgress: Double = 0.0

    private let spacing: CGFloat = 2.5
    private let minBarHeight: CGFloat = 3.0

    public init(
        progress: Double,
        isPlaying: Bool,
        color: Color,
        samples: [Double],
        barCount: Int = 30,
        waveformHeight: CGFloat = 20,
        onScrubChange: @escaping (Bool, Double) -> Void,
        onSeek: @escaping (Double) -> Void
    ) {
        self.progress = progress
        self.isPlaying = isPlaying
        self.color = color
        self.samples = samples
        self.barCount = barCount
        self.waveformHeight = waveformHeight
        self.onScrubChange = onScrubChange
        self.onSeek = onSeek
    }

    public var body: some View {
        GeometryReader { geo in
            let totalW = geo.size.width
            let totalH = geo.size.height
            let currentProg = isScrubbing ? dragProgress : progress
            let activeWidth = totalW * CGFloat(currentProg)
            let totalSpacing = CGFloat(barCount - 1) * spacing
            let barW = max((totalW - totalSpacing) / CGFloat(barCount), 2.0)

            ZStack(alignment: .leading) {
                // Metal GPU 60/120FPS Animation Canvas
                TimelineView(.animation(paused: !isPlaying || reduceMotion)) { timeline in
                    Canvas { context, size in
                        let time = timeline.date.timeIntervalSinceReferenceDate

                        for i in 0..<barCount {
                            let x = CGFloat(i) * (barW + spacing)
                            let isPlayed = (x + barW / 2.0) <= activeWidth

                            let phase = Double(i) * 0.38
                            let w1 = sin(time * 5.8 + phase)
                            let w2 = cos(time * 3.4 + phase * 0.70)
                            let w3 = sin(time * 1.6 + Double(i) * 0.15)
                            let fluidFactor = (w1 * 0.45 + w2 * 0.35 + w3 * 0.20 + 1.0) / 2.0

                            let sampleIdx = i % max(samples.count, 1)
                            let rawSample = samples.isEmpty ? 0.35 : samples[sampleIdx]

                            let amp = reduceMotion ? (rawSample * 0.50) : (isPlaying ? (rawSample * 0.25 + fluidFactor * 0.75) : (rawSample * 0.30))
                            let barH = max(minBarHeight, totalH * CGFloat(amp))
                            let y = (totalH - barH) / 2.0

                            let barRect = CGRect(x: x, y: y, width: barW, height: barH)
                            let path = Path(roundedRect: barRect, cornerRadius: barW / 2.0)

                            if isPlayed {
                                context.fill(path, with: .color(color))
                            } else {
                                context.fill(path, with: .color(Color.primary.opacity(0.12)))
                            }
                        }

                        // Luminous Scrubber Thumb while dragging
                        if isScrubbing {
                            let thumbX = min(max(activeWidth, 0), totalW)
                            let thumbRect = CGRect(x: thumbX - 1.5, y: 1, width: 3, height: totalH - 2)
                            context.fill(Path(roundedRect: thumbRect, cornerRadius: 1.5), with: .color(.white))
                        }
                    }
                    .frame(width: totalW, height: totalH)
                }
                .drawingGroup()
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isScrubbing = true
                        let prog = min(max(value.location.x / totalW, 0.0), 1.0)
                        dragProgress = prog
                        onScrubChange(true, prog)
                    }
                    .onEnded { value in
                        let final = min(max(value.location.x / totalW, 0.0), 1.0)
                        isScrubbing = false
                        onScrubChange(false, final)
                        onSeek(final)
                    }
            )
        }
        .frame(height: waveformHeight)
    }
}

// MARK: - Native Flowing Time-Synced Lyrics View (Apple Music Style Auto-Scroll)
public struct ParsedLyricLine: Identifiable, Sendable {
    public let id: Int
    public let time: TimeInterval
    public let text: String

    public init(id: Int, time: TimeInterval, text: String) {
        self.id = id
        self.time = time
        self.text = text
    }
}

public struct LyricsDisplayView: View {
    public let rawLyrics: String
    public let currentTime: Double
    public let duration: Double
    public let isPlaying: Bool
    public let accentColor: Color
    public let palette: ThemePalette
    public let maxHeight: CGFloat
    public let onSeek: (Double) -> Void

    private var parsedLines: [ParsedLyricLine] {
        Self.parseLyrics(rawLyrics)
    }

    private var activeLineIndex: Int {
        guard !parsedLines.isEmpty else { return 0 }
        var active = 0
        for (idx, line) in parsedLines.enumerated() {
            if line.time <= currentTime + 0.25 {
                active = idx
            } else {
                break
            }
        }
        return active
    }

    public init(
        rawLyrics: String,
        currentTime: Double = 0.0,
        duration: Double = 1.0,
        isPlaying: Bool = true,
        accentColor: Color,
        palette: ThemePalette,
        maxHeight: CGFloat,
        onSeek: @escaping (Double) -> Void = { _ in }
    ) {
        self.rawLyrics = rawLyrics
        self.currentTime = currentTime
        self.duration = duration
        self.isPlaying = isPlaying
        self.accentColor = accentColor
        self.palette = palette
        self.maxHeight = maxHeight
        self.onSeek = onSeek
    }

    public var body: some View {
        let lines = parsedLines

        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    // Top breathing room
                    Spacer().frame(height: 12)

                    ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                        let isCurrent = (index == activeLineIndex)

                        Button {
                            if line.time > 0 && duration > 0 {
                                onSeek(min(max(line.time / duration, 0.0), 1.0))
                            }
                        } label: {
                            Text(line.text)
                                .font(.system(size: isCurrent ? 13.5 : 11.5, weight: isCurrent ? .bold : .medium, design: .rounded))
                                .foregroundColor(isCurrent ? .white : .white.opacity(0.35))
                                .lineSpacing(2)
                                .scaleEffect(isCurrent ? 1.03 : 1.0, anchor: .leading)
                                .shadow(color: isCurrent ? accentColor.opacity(0.55) : .clear, radius: 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(line.id)
                    }

                    // Bottom breathing room
                    Spacer().frame(height: 18)
                }
                .padding(.horizontal, 6)
            }
            .frame(maxHeight: maxHeight)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .black, location: 0.12),
                        .init(color: .black, location: 0.88),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .onChange(of: activeLineIndex) { _, newIndex in
                if lines.indices.contains(newIndex) {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
                        proxy.scrollTo(lines[newIndex].id, anchor: .center)
                    }
                }
            }
            .onAppear {
                if lines.indices.contains(activeLineIndex) {
                    proxy.scrollTo(lines[activeLineIndex].id, anchor: .center)
                }
            }
        }
    }

    public static func parseLyrics(_ raw: String) -> [ParsedLyricLine] {
        let rawLines = raw.components(separatedBy: .newlines)
        var parsed: [ParsedLyricLine] = []
        let regex = try? NSRegularExpression(pattern: "\\[(\\d{2}):(\\d{2})(?:\\.(\\d{2,3}))?\\]", options: [])

        var lineId = 0
        for line in rawLines {
            let nsLine = line as NSString
            if let regex {
                let matches = regex.matches(in: line, options: [], range: NSRange(location: 0, length: nsLine.length))
                if let firstMatch = matches.first, firstMatch.numberOfRanges >= 3 {
                    let minStr = nsLine.substring(with: firstMatch.range(at: 1))
                    let secStr = nsLine.substring(with: firstMatch.range(at: 2))
                    var ms: Double = 0.0
                    if firstMatch.numberOfRanges >= 4 && firstMatch.range(at: 3).location != NSNotFound {
                        let msStr = nsLine.substring(with: firstMatch.range(at: 3))
                        let msVal = Double(msStr) ?? 0.0
                        ms = msStr.count == 2 ? (msVal / 100.0) : (msVal / 1000.0)
                    }
                    let minutes = Double(minStr) ?? 0.0
                    let seconds = Double(secStr) ?? 0.0
                    let totalTime = minutes * 60.0 + seconds + ms
                    let text = nsLine.substring(from: firstMatch.range.location + firstMatch.range.length).trimmingCharacters(in: .whitespaces)

                    if !text.isEmpty {
                        parsed.append(ParsedLyricLine(id: lineId, time: totalTime, text: text))
                        lineId += 1
                    }
                    continue
                }
            }

            // Fallback for non-timestamped lyrics lines
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty && !trimmed.hasPrefix("[ti:") && !trimmed.hasPrefix("[ar:") && !trimmed.hasPrefix("[al:") && !trimmed.hasPrefix("[by:") {
                parsed.append(ParsedLyricLine(id: lineId, time: 0, text: trimmed))
                lineId += 1
            }
        }

        return parsed.sorted(by: { $0.time < $1.time })
    }
}
