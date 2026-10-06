// Sources/PurahUI/DrawerPanels/MusicDrawerView.swift
import SwiftUI
import AppKit
import PurahCore

public struct MusicDrawerView: View {
    public let store: PurahWorkspaceStore

    @State private var isBackwardHovered: Bool = false
    @State private var isForwardHovered: Bool = false
    @State private var isPlayPauseHovered: Bool = false
    @State private var isScrubbing: Bool = false
    @State private var scrubbedProgress: Double = 0.0

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    private var musicColor: Color {
        palette.podColor(for: "music", store: store)
    }

    public init(store: PurahWorkspaceStore) {
        self.store = store
    }

    public var body: some View {
        let isPlaying = store.musicTrack.isPlaying

        TimelineView(.periodic(from: .now, by: isPlaying ? 0.5 : 60.0)) { _ in
            let liveCurrentSec = store.musicTrack.calculatedCurrentTime
            let liveProgress = store.musicTrack.calculatedProgress

            let displayProgress = isScrubbing ? scrubbedProgress : liveProgress
            let displaySec = isScrubbing ? (scrubbedProgress * max(store.musicTrack.durationSeconds, 1.0)) : liveCurrentSec

            VStack(spacing: 10) {
                // MARK: - Header: Album Art & Audio Source Badge & Track Info & Pin
                HStack(spacing: 10) {
                    // Album Art with Atoll-style Source Badge (Click to open player)
                    Button {
                        activateMusicPlayerApp()
                    } label: {
                        HStack(spacing: 10) {
                            albumArtWithSourceBadge

                            VStack(alignment: .leading, spacing: 2) {
                                Text(store.musicTrack.title)
                                    .purahTitle(size: 12, weight: .bold, design: .rounded)
                                    .foregroundColor(palette.style == .native ? Color.primary : .white)
                                    .lineLimit(1)

                                Text(store.musicTrack.artist)
                                    .purahBody(size: 10, weight: .medium, design: .rounded)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Open \(store.musicTrack.sourceApp)")

                    Spacer(minLength: 4)

                    // Pin Button
                    Button {
                        withAnimation(.spring(response: 0.26, dampingFraction: 0.55)) {
                            store.togglePinItem(id: "music")
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(store.isItemPinned(id: "music") ? musicColor.opacity(0.18) : Color.primary.opacity(0.06))
                                .frame(width: 24, height: 24)

                            Image(systemName: store.isItemPinned(id: "music") ? "pin.fill" : "pin")
                                .foregroundColor(store.isItemPinned(id: "music") ? musicColor : .secondary)
                                .font(.system(size: 11, weight: .semibold))
                                .rotationEffect(.degrees(store.isItemPinned(id: "music") ? -25 : 0))
                                .scaleEffect(store.isItemPinned(id: "music") ? 1.15 : 1.0)
                                .animation(.spring(response: 0.26, dampingFraction: 0.55), value: store.isItemPinned(id: "music"))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.tactile)
                    .help(store.isItemPinned(id: "music") ? "Pinned" : "Pin music drawer")
                }

                // MARK: - Metal GPU 60/120FPS Fluid Waveform Scrubber
                VStack(spacing: 4) {
                    FluidWaveformScrubber(
                        progress: displayProgress,
                        isPlaying: isPlaying,
                        color: musicColor,
                        samples: store.musicTrack.waveformSamples,
                        onScrubChange: { dragging, prog in
                            isScrubbing = dragging
                            scrubbedProgress = prog
                        },
                        onSeek: { newProg in
                            isScrubbing = false
                            SystemMusicSyncService.shared.seek(to: newProg, store: store)
                        }
                    )

                    // Time Labels
                    HStack {
                        Text(timeString(for: displaySec))
                            .purahCaption(size: 8, weight: .medium, design: .monospaced)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(timeString(for: store.musicTrack.durationSeconds))
                            .purahCaption(size: 8, weight: .medium, design: .monospaced)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 4)

                // MARK: - Floating Media Buttons with Reactive Spring Nudges
                HStack(spacing: 28) {
                    // Backward Button
                    Button {
                        SystemMusicSyncService.shared.previousTrack(store: store)
                    } label: {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(palette.style == .native ? Color.primary : .white)
                            .frame(width: 32, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(isBackwardHovered ? Color.primary.opacity(0.10) : Color.clear)
                            )
                    }
                    .buttonStyle(MediaNudgeButtonStyle(nudgeOffset: -5))
                    .onHover { isBackwardHovered = $0 }

                    // Play / Pause Hero Button
                    Button {
                        SystemMusicSyncService.shared.togglePlayPause(store: store)
                    } label: {
                        ZStack {
                            Circle()
                                .fill(musicColor.opacity(0.18))
                                .frame(width: 38, height: 38)
                                .modifier(OptionalGlow(color: musicColor, enabled: palette.useGlow))

                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(musicColor)
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .frame(width: 38, height: 38)
                        .background(
                            Circle()
                                .fill(isPlayPauseHovered ? musicColor.opacity(0.12) : Color.clear)
                        )
                    }
                    .buttonStyle(HeroPlayPauseButtonStyle())
                    .onHover { isPlayPauseHovered = $0 }

                    // Forward Button
                    Button {
                        SystemMusicSyncService.shared.nextTrack(store: store)
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(palette.style == .native ? Color.primary : .white)
                            .frame(width: 32, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(isForwardHovered ? Color.primary.opacity(0.10) : Color.clear)
                            )
                    }
                    .buttonStyle(MediaNudgeButtonStyle(nudgeOffset: 5))
                    .onHover { isForwardHovered = $0 }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(8)
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            SystemMusicSyncService.shared.startListening(into: store)
        }
    }

    // MARK: - Album Art View with Source Badge
    @ViewBuilder
    private var albumArtWithSourceBadge: some View {
        ZStack(alignment: .bottomTrailing) {
            if let data = store.musicTrack.artworkData, let nsImg = NSImage(data: data) {
                Image(nsImage: nsImg)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(palette.borderColor.opacity(0.6), lineWidth: 1.0)
                    )
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(musicColor.opacity(0.15))
                        .frame(width: 44, height: 44)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(musicColor.opacity(0.7), lineWidth: 1.2)
                        )
                        .modifier(OptionalGlow(color: musicColor, enabled: palette.useGlow))

                    Image(systemName: "music.note")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(musicColor)
                        .symbolEffect(.bounce, value: store.musicTrack.isPlaying)
                }
            }

            // Atoll-style Audio Source Badge at bottom-right corner
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.85))
                    .frame(width: 15, height: 15)
                    .overlay(
                        Circle().stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                    )

                Image(systemName: sourceIconName(for: store.musicTrack.sourceApp))
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white)
            }
            .offset(x: 3, y: 3)
        }
    }

    private func sourceIconName(for source: String) -> String {
        let lower = source.lowercased()
        if lower.contains("spotify") {
            return "waveform"
        } else if lower.contains("chrome") || lower.contains("safari") || lower.contains("browser") {
            return "globe"
        } else {
            return "apple.logo"
        }
    }

    private func activateMusicPlayerApp() {
        let source = store.musicTrack.sourceApp.lowercased()
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
    public let onScrubChange: (Bool, Double) -> Void
    public let onSeek: (Double) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isScrubbing: Bool = false
    @State private var dragProgress: Double = 0.0

    private let barCount = 30
    private let spacing: CGFloat = 2.5
    private let minBarHeight: CGFloat = 4.0

    public init(
        progress: Double,
        isPlaying: Bool,
        color: Color,
        samples: [Double],
        onScrubChange: @escaping (Bool, Double) -> Void,
        onSeek: @escaping (Double) -> Void
    ) {
        self.progress = progress
        self.isPlaying = isPlaying
        self.color = color
        self.samples = samples
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
            let barW = max((totalW - totalSpacing) / CGFloat(barCount), 2.5)

            ZStack(alignment: .leading) {
                // Metal GPU 60/120FPS Animation Canvas
                TimelineView(.animation(paused: !isPlaying || reduceMotion)) { timeline in
                    Canvas { context, size in
                        let time = timeline.date.timeIntervalSinceReferenceDate

                        for i in 0..<barCount {
                            let x = CGFloat(i) * (barW + spacing)
                            let isPlayed = (x + barW / 2.0) <= activeWidth

                            // Continuous fluid traveling wave equation:
                            // Superposition of fundamental wave + harmonic + traveling spatial phase
                            let phase = Double(i) * 0.38
                            let w1 = sin(time * 5.8 + phase)
                            let w2 = cos(time * 3.4 + phase * 0.70)
                            let w3 = sin(time * 1.6 + Double(i) * 0.15)
                            let fluidFactor = (w1 * 0.45 + w2 * 0.35 + w3 * 0.20 + 1.0) / 2.0 // 0.0 .. 1.0

                            let sampleIdx = i % max(samples.count, 1)
                            let rawSample = samples.isEmpty ? 0.35 : samples[sampleIdx]

                            // Dynamic amplitude: resting breathing state when paused, alive fluid flow when playing
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
                .drawingGroup() // Metal GPU hardware accelerated
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
        .frame(height: 24)
    }
}
