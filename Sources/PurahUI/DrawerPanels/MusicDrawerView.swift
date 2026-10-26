// Sources/PurahUI/DrawerPanels/MusicDrawerView.swift
import SwiftUI
import AppKit
import CoreAudio
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

        TimelineView(.periodic(from: .now, by: (isPlaying && !reduceMotion) ? 0.5 : (isPlaying ? 1.0 : 60.0))) { _ in
            let liveCurrentSec = state.track.calculatedCurrentTime
            let liveProgress = state.track.calculatedProgress

            let displayProgress = isScrubbing ? scrubbedProgress : liveProgress
            let displaySec = isScrubbing ? (scrubbedProgress * max(state.track.durationSeconds, 1.0)) : liveCurrentSec

            // Thresholds are content-area heights, matching the tier builders.
            // They describe how much room the player body has, not the pod slot.
            PurahAdaptiveTierDrawer(
                tiers: [
                    PurahAdaptiveTier(id: "compact", minHeight: 0),
                    PurahAdaptiveTier(id: "standard", minHeight: 145),
                    PurahAdaptiveTier(id: "immersive", minHeight: 215)
                ]
            ) { tier, h in
                AnyView(
                    tierBody(
                        tier.id,
                        displayProgress: displayProgress,
                        displaySec: displaySec,
                        isPlaying: isPlaying,
                        availableHeight: h
                    )
                )
            }
        }
        .onAppear {
            state.mount(store: store)
        }
    }

    @ViewBuilder
    private func tierBody(
        _ tierId: String,
        displayProgress: Double,
        displaySec: Double,
        isPlaying: Bool,
        availableHeight: CGFloat
    ) -> some View {
        switch tierId {
        case "compact":
            compactCapsuleView(displayProgress: displayProgress, displaySec: displaySec, isPlaying: isPlaying, availableHeight: availableHeight)
        case "immersive":
            immersiveVinylView(displayProgress: displayProgress, displaySec: displaySec, isPlaying: isPlaying, availableHeight: availableHeight)
        default:
            classicStudioView(displayProgress: displayProgress, displaySec: displaySec, isPlaying: isPlaying, availableHeight: availableHeight)
        }
    }

    // MARK: - Tier 1: Compact Capsule Layout (< 145pt)
    @ViewBuilder
    private func compactCapsuleView(displayProgress: Double, displaySec: Double, isPlaying: Bool, availableHeight: CGFloat = 100.0) -> some View {
        if availableHeight < 66.0 {
            // Ultra-Flat Single-Row Mode (26pt ~ 65pt inner height): Transport Controls ALWAYS visible on Row 1
            VStack(spacing: 3) {
                HStack(spacing: 6) {
                    Button {
                        activateMusicPlayerApp()
                    } label: {
                        HStack(spacing: 6) {
                            artworkThumbnail(size: 22, cornerRadius: 5)

                            VStack(alignment: .leading, spacing: 0) {
                                Text(state.track.title)
                                    .purahTitle(size: 10.5, weight: .bold, design: .rounded)
                                    .foregroundColor(palette.style == .native ? Color.primary : .white)
                                    .lineLimit(1)

                                if availableHeight >= 34.0 {
                                    Text(state.track.artist)
                                        .purahBody(size: 8.5, weight: .medium, design: .rounded)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 4)

                    // Inline Transport Controls right on Row 1
                    HStack(spacing: 3) {
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
                                    .frame(width: 24, height: 24)

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
                }

                if availableHeight >= 40.0 {
                    NativeMediaProgressBar(
                        progress: displayProgress,
                        color: musicColor,
                        height: 6,
                        onScrubChange: { dragging, prog in
                            isScrubbing = dragging
                            scrubbedProgress = prog
                        },
                        onSeek: { newProg in
                            isScrubbing = false
                            state.seek(to: newProg, store: store)
                        }
                    )
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            // 2-Row Compact Mode (66pt ~ 144pt inner height): Transport Controls anchored on Row 1
            VStack(spacing: 4) {
                // Row 1: Micro Artwork + Title/Artist + Inline Transport Controls
                HStack(spacing: 6) {
                    Button {
                        activateMusicPlayerApp()
                    } label: {
                        HStack(spacing: 6) {
                            artworkThumbnail(size: 28, cornerRadius: 6)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(state.track.title)
                                    .purahTitle(size: 11, weight: .bold, design: .rounded)
                                    .foregroundColor(palette.style == .native ? Color.primary : .white)
                                    .lineLimit(1)

                                Text(state.track.artist)
                                    .purahBody(size: 9.0, weight: .medium, design: .rounded)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 4)

                    // Micro transport buttons on Row 1 so they are never clipped
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
                }

                // Live 1-line Synced Lyric Preview when space permits (>= 90pt inner height)
                if availableHeight >= 90.0,
                   let rawLyrics = state.track.syncedLyrics ?? state.track.lyrics,
                   !rawLyrics.isEmpty,
                   let activeLine = LyricsDisplayView.activeLyricLine(in: rawLyrics, at: displaySec) {
                    HStack(spacing: 4) {
                        Image(systemName: "quote.opening")
                            .font(.system(size: 7.0, weight: .bold))
                            .foregroundColor(musicColor.opacity(0.85))
                        Text(activeLine)
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .foregroundColor(musicColor)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 2)
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(musicColor.opacity(0.10))
                    .cornerRadius(4)
                }

                // Row 2: Scrubber + Time
                HStack(spacing: 6) {
                    NativeMediaProgressBar(
                        progress: displayProgress,
                        color: musicColor,
                        height: 12,
                        onScrubChange: { dragging, prog in
                            isScrubbing = dragging
                            scrubbedProgress = prog
                        },
                        onSeek: { newProg in
                            isScrubbing = false
                            state.seek(to: newProg, store: store)
                        }
                    )

                    Text("\(timeString(for: displaySec))/\(timeString(for: state.track.durationSeconds))")
                        .purahCaption(size: 8, weight: .medium, design: .monospaced)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    // MARK: - Tier 2: Classic Studio Layout (145pt ~ 214pt)
    @ViewBuilder
    private func classicStudioView(displayProgress: Double, displaySec: Double, isPlaying: Bool, availableHeight: CGFloat = 180.0) -> some View {
        VStack(spacing: 6) {
            // Row 1: Artwork + Title/Artist + Pin
            HStack(spacing: 10) {
                Button {
                    activateMusicPlayerApp()
                } label: {
                    HStack(spacing: 10) {
                        artworkThumbnail(size: 38, cornerRadius: 8)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(state.track.title)
                                .purahTitle(size: 12, weight: .bold, design: .rounded)
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

            // Live 1-line Synced Lyric Bar (when lyrics are available in Standard mode)
            if let rawLyrics = state.track.syncedLyrics ?? state.track.lyrics,
               !rawLyrics.isEmpty,
               let activeLine = LyricsDisplayView.activeLyricLine(in: rawLyrics, at: displaySec) {
                HStack(spacing: 5) {
                    Image(systemName: "quote.opening")
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundColor(musicColor.opacity(0.85))
                    Text(activeLine)
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .foregroundColor(musicColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 2)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(musicColor.opacity(0.10))
                .cornerRadius(5)
                .transition(.opacity)
            }

            // Row 2: Standard Progress Bar + Dual Time Labels
            VStack(spacing: 3) {
                NativeMediaProgressBar(
                    progress: displayProgress,
                    color: musicColor,
                    height: 14,
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
                        .frame(width: 30, height: 24)
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
                            .frame(width: 32, height: 32)
                            .modifier(OptionalGlow(color: musicColor, enabled: palette.useGlow))

                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(musicColor)
                    }
                    .frame(width: 32, height: 32)
                }
                .buttonStyle(HeroPlayPauseButtonStyle())

                Button {
                    state.nextTrack(store: store)
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(palette.style == .native ? Color.primary : .white)
                        .frame(width: 30, height: 24)
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
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    // MARK: - Tier 3: Immersive Vinyl Showcase Layout (>= 215pt)
    @ViewBuilder
    private func immersiveVinylView(displayProgress: Double, displaySec: Double, isPlaying: Bool, availableHeight: CGFloat) -> some View {
        let dynamicArtSize = min(max((availableHeight - 150) * 0.50, 56.0), 160.0)

        VStack(spacing: 6) {
            if let lyrics = state.track.syncedLyrics ?? state.track.lyrics, !lyrics.isEmpty {
                // Direct Lyrics Showcase: Compact Track Bar + Flowing Lyrics Sheet
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        artworkThumbnail(size: 32, cornerRadius: 6)

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
                        maxHeight: max(availableHeight - 135, 68),
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

            // High-density Progress Bar
            VStack(spacing: 5) {
                NativeMediaProgressBar(
                    progress: displayProgress,
                    color: musicColor,
                    height: 16,
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
            let badgeSize: CGFloat = max(size * 0.34, 14.0)
            if let appIcon = Self.resolveSourceAppIcon(sourceApp: state.track.sourceApp, bundleId: state.track.sourceBundleId) {
                Image(nsImage: appIcon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: badgeSize, height: badgeSize)
                    .shadow(color: .black.opacity(0.45), radius: 2, x: 0, y: 1)
                    .offset(x: 3, y: 3)
            } else {
                ZStack {
                    Circle()
                        .fill(sourceBadgeColor(for: state.track.sourceApp, bundleId: state.track.sourceBundleId))
                        .frame(width: badgeSize, height: badgeSize)
                        .overlay(
                            Circle().stroke(Color.white.opacity(0.25), lineWidth: 0.5)
                        )
                        .shadow(color: .black.opacity(0.45), radius: 2, x: 0, y: 1)

                    Image(systemName: sourceIconName(for: state.track.sourceApp))
                        .font(.system(size: badgeSize * 0.55, weight: .bold))
                        .foregroundColor(.white)
                }
                .offset(x: 3, y: 3)
            }
        }
    }

    @MainActor
    private static var sourceAppIconCache: [String: NSImage] = [:]

    @MainActor
    public static func resolveSourceAppIcon(sourceApp: String, bundleId: String) -> NSImage? {
        let cacheKey = "\(sourceApp.lowercased())|\(bundleId)"
        if let cached = sourceAppIconCache[cacheKey] {
            return cached
        }

        var candidateBundleIds: [String] = []
        if !bundleId.isEmpty {
            candidateBundleIds.append(bundleId)
        }

        let lower = sourceApp.lowercased()
        if lower == "music" || lower == "apple music" {
            candidateBundleIds.append("com.apple.Music")
        } else if lower.contains("spotify") {
            candidateBundleIds.append("com.spotify.client")
        } else if lower.contains("chrome") || lower == "google chrome" {
            candidateBundleIds.append("com.google.Chrome")
        } else if lower.contains("safari") {
            candidateBundleIds.append("com.apple.Safari")
        } else if lower == "arc" || lower.contains("arc") {
            candidateBundleIds.append("company.thebrowser.Browser")
        } else if lower.contains("netease") {
            candidateBundleIds.append("com.netease.163music")
        } else if lower.contains("qqmusic") || lower.contains("qq music") {
            candidateBundleIds.append("com.tencent.QQMusicMac")
        }

        for targetBundleId in candidateBundleIds {
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: targetBundleId) {
                let icon = NSWorkspace.shared.icon(forFile: appURL.path)
                sourceAppIconCache[cacheKey] = icon
                return icon
            }
            if targetBundleId == "com.apple.Music",
               FileManager.default.fileExists(atPath: "/System/Applications/Music.app") {
                let icon = NSWorkspace.shared.icon(forFile: "/System/Applications/Music.app")
                sourceAppIconCache[cacheKey] = icon
                return icon
            }
            if targetBundleId == "com.apple.Safari" {
                let safariPaths = [
                    "/Applications/Safari.app",
                    "/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app",
                    "/System/Applications/Safari.app"
                ]
                for path in safariPaths where FileManager.default.fileExists(atPath: path) {
                    let icon = NSWorkspace.shared.icon(forFile: path)
                    sourceAppIconCache[cacheKey] = icon
                    return icon
                }
            }
        }

        return nil
    }

    private func sourceBadgeColor(for source: String, bundleId: String) -> Color {
        let lower = source.lowercased()
        if lower.contains("spotify") || bundleId == "com.spotify.client" {
            return Color(hex: "#1DB954")
        } else if lower.contains("chrome") || lower.contains("safari") || lower.contains("browser") || bundleId == "com.google.Chrome" || bundleId == "com.apple.Safari" {
            return Color(hex: "#4285F4")
        } else {
            return Color(hex: "#FA2D48")
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
        let bundleId = state.track.sourceBundleId
        if !bundleId.isEmpty, let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: appURL, configuration: config, completionHandler: nil)
            return
        }

        let source = state.track.sourceApp.lowercased()
        let fallbackId = source.contains("spotify") ? "com.spotify.client" : "com.apple.Music"
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: fallbackId) {
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
            .animation(PurahMotionPolicy.press, value: configuration.isPressed)
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

// MARK: - Native Tactile Media Progress Bar (Standard Clean Scrubber)
public struct NativeMediaProgressBar: View {
    public let progress: Double
    public let color: Color
    public var height: CGFloat = 16
    public let onScrubChange: (Bool, Double) -> Void
    public let onSeek: (Double) -> Void

    @State private var isHovered: Bool = false
    @State private var isScrubbing: Bool = false
    @State private var dragProgress: Double = 0.0

    public init(
        progress: Double,
        color: Color,
        height: CGFloat = 16,
        onScrubChange: @escaping (Bool, Double) -> Void,
        onSeek: @escaping (Double) -> Void
    ) {
        self.progress = progress
        self.color = color
        self.height = height
        self.onScrubChange = onScrubChange
        self.onSeek = onSeek
    }

    public var body: some View {
        GeometryReader { geo in
            let totalW = geo.size.width
            let activeProg = min(max(isScrubbing ? dragProgress : progress, 0.0), 1.0)
            let fillW = totalW * CGFloat(activeProg)
            let trackHeight: CGFloat = (isHovered || isScrubbing) ? 5.5 : 3.5
            let thumbDiameter: CGFloat = (isHovered || isScrubbing) ? 10.0 : 0.0

            ZStack(alignment: .leading) {
                // Background Track
                Capsule()
                    .fill(Color.primary.opacity(0.12))
                    .frame(width: totalW, height: trackHeight)

                // Elapsed Progress Fill
                Capsule()
                    .fill(color)
                    .frame(width: max(fillW, 0.0), height: trackHeight)

                // Playhead Thumb (Expands smoothly on hover/scrub)
                if isHovered || isScrubbing {
                    Circle()
                        .fill(Color.white)
                        .frame(width: thumbDiameter, height: thumbDiameter)
                        .shadow(color: Color.black.opacity(0.35), radius: 2, x: 0, y: 1)
                        .offset(x: min(max(fillW - thumbDiameter / 2.0, 0), max(totalW - thumbDiameter, 0)))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: totalW, height: geo.size.height, alignment: .center)
            .contentShape(Rectangle())
            .onHover { hovering in
                withAnimation(.spring(response: 0.20, dampingFraction: 0.75)) {
                    isHovered = hovering
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isScrubbing = true
                        let p = min(max(value.location.x / max(totalW, 1.0), 0.0), 1.0)
                        dragProgress = p
                        onScrubChange(true, p)
                    }
                    .onEnded { value in
                        let final = min(max(value.location.x / max(totalW, 1.0), 0.0), 1.0)
                        isScrubbing = false
                        onScrubChange(false, final)
                        onSeek(final)
                    }
            )
        }
        .frame(height: height)
    }
}

// MARK: - Backward-Compatible Scrubber Wrapper
public struct FluidWaveformScrubber: View {
    public let progress: Double
    public let isPlaying: Bool
    public let color: Color
    public let samples: [Double]
    public var barCount: Int = 30
    public var waveformHeight: CGFloat = 20
    public let onScrubChange: (Bool, Double) -> Void
    public let onSeek: (Double) -> Void

    public init(
        progress: Double,
        isPlaying: Bool,
        color: Color,
        samples: [Double] = [],
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
        NativeMediaProgressBar(
            progress: progress,
            color: color,
            height: waveformHeight,
            onScrubChange: onScrubChange,
            onSeek: onSeek
        )
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
            PurahScrollableBody {
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

    public static func activeLyricLine(in raw: String, at currentTime: Double) -> String? {
        let lines = parseLyrics(raw)
        guard !lines.isEmpty else { return nil }
        var active = 0
        for (idx, line) in lines.enumerated() {
            if line.time <= currentTime + 0.25 {
                active = idx
            } else {
                break
            }
        }
        return lines[active].text
    }
}

// MARK: - CoreAudio Output Device Quick-Switcher
public struct AudioOutputDevice: Identifiable, Equatable, Sendable {
    public let id: AudioDeviceID
    public let name: String

    public init(id: AudioDeviceID, name: String) {
        self.id = id
        self.name = name
    }

    public var systemIcon: String {
        let lower = name.lowercased()
        if lower.contains("airpods") {
            return "airpodspro"
        } else if lower.contains("headphone") || lower.contains("beats") || lower.contains("ear") {
            return "headphones"
        } else if lower.contains("display") || lower.contains("hdmi") {
            return "display"
        } else {
            return "speaker.wave.2.fill"
        }
    }
}

@MainActor
public final class AudioOutputDeviceManager: ObservableObject {
    public static let shared = AudioOutputDeviceManager()

    @Published public private(set) var outputDevices: [AudioOutputDevice] = []
    @Published public private(set) var defaultOutputDeviceId: AudioDeviceID = 0

    private init() {
        refreshDevices()
    }

    public var activeDevice: AudioOutputDevice? {
        outputDevices.first(where: { $0.id == defaultOutputDeviceId }) ?? outputDevices.first
    }

    public func refreshDevices() {
        var defaultId = AudioDeviceID(0)
        var defaultSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var defaultAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let defaultStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultAddress,
            0,
            nil,
            &defaultSize,
            &defaultId
        )
        if defaultStatus == noErr {
            self.defaultOutputDeviceId = defaultId
        }

        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddress,
            0,
            nil,
            &dataSize
        ) == noErr, dataSize > 0 else {
            return
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIds = [AudioDeviceID](repeating: 0, count: deviceCount)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddress,
            0,
            nil,
            &dataSize,
            &deviceIds
        ) == noErr else {
            return
        }

        var discovered: [AudioOutputDevice] = []
        for devId in deviceIds {
            var streamAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioObjectPropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(devId, &streamAddress, 0, nil, &streamSize) == noErr,
                  streamSize > 0 else {
                continue
            }

            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var cfName: Unmanaged<CFString>? = nil
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            let status = withUnsafeMutablePointer(to: &cfName) { ptr in
                AudioObjectGetPropertyData(devId, &nameAddress, 0, nil, &nameSize, ptr)
            }
            if status == noErr, let unwrapped = cfName?.takeUnretainedValue() as String? {
                let trimmed = unwrapped.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    discovered.append(AudioOutputDevice(id: devId, name: trimmed))
                }
            }
        }

        self.outputDevices = discovered
    }

    @discardableResult
    public func selectOutputDevice(id: AudioDeviceID) -> Bool {
        var mutableId = id
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            size,
            &mutableId
        )
        if status == noErr {
            defaultOutputDeviceId = id
            SensoryFeedbackService.shared.performControlHapticIfEnabled(.alignment)
            return true
        }
        return false
    }
}

public struct AudioOutputDevicePickerView: View {
    public let accentColor: Color
    @ObservedObject private var deviceManager = AudioOutputDeviceManager.shared

    public init(accentColor: Color) {
        self.accentColor = accentColor
    }

    public var body: some View {
        Menu {
            ForEach(deviceManager.outputDevices) { device in
                Button {
                    _ = deviceManager.selectOutputDevice(id: device.id)
                } label: {
                    HStack {
                        Image(systemName: device.systemIcon)
                        Text(device.name)
                        if device.id == deviceManager.defaultOutputDeviceId {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            Divider()
            Button {
                deviceManager.refreshDevices()
            } label: {
                Label("Refresh Audio Devices", systemImage: "arrow.clockwise")
            }
        } label: {
            let current = deviceManager.activeDevice
            HStack(spacing: 3) {
                Image(systemName: current?.systemIcon ?? "speaker.wave.2.fill")
                    .font(.system(size: 8, weight: .bold))
                Text(shortDeviceLabel(for: current?.name ?? "Output"))
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 5.5, weight: .bold))
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(Color.secondary.opacity(0.14))
            .foregroundColor(.primary.opacity(0.85))
            .cornerRadius(4)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Switch macOS Audio Output Device")
        .onAppear {
            deviceManager.refreshDevices()
        }
    }

    private func shortDeviceLabel(for name: String) -> String {
        if name.count <= 12 { return name }
        if name.lowercased().contains("airpods") { return "AirPods" }
        if name.lowercased().contains("speaker") { return "Speakers" }
        if name.lowercased().contains("headphone") { return "Headphones" }
        return String(name.prefix(10)) + "…"
    }
}
