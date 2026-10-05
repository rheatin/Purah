// Sources/PurahUI/DrawerPanels/MusicDrawerView.swift
import SwiftUI
import AppKit
import PurahCore

public struct MusicDrawerView: View {
    public let store: PurahWorkspaceStore

    @State private var backwardOffset: CGFloat = 0
    @State private var forwardOffset: CGFloat = 0
    @State private var playPauseScale: CGFloat = 1.0
    @State private var isBackwardHovered: Bool = false
    @State private var isForwardHovered: Bool = false
    @State private var isPlayPauseHovered: Bool = false

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
            let currentSec = store.musicTrack.calculatedCurrentTime
            let progress = store.musicTrack.calculatedProgress

            VStack(spacing: 10) {
                // MARK: - Header: Album Art & Audio Source Badge & Track Info & Pin
                HStack(spacing: 10) {
                    // Album Art with Atoll-style Source Badge
                    albumArtWithSourceBadge

                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.musicTrack.title)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(palette.style == .native ? Color.primary : .white)
                            .lineLimit(1)

                        Text(store.musicTrack.artist)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                // Pin Button
                Button {
                    withAnimation(.spring(response: 0.26, dampingFraction: 0.55)) {
                        store.togglePinItem(id: "music")
                    }
                } label: {
                    Image(systemName: store.isItemPinned(id: "music") ? "pin.fill" : "pin")
                        .foregroundColor(store.isItemPinned(id: "music") ? musicColor : .gray)
                        .font(.system(size: 11))
                        .rotationEffect(.degrees(store.isItemPinned(id: "music") ? -25 : 0))
                        .scaleEffect(store.isItemPinned(id: "music") ? 1.18 : 1.0)
                        .animation(.spring(response: 0.26, dampingFraction: 0.55), value: store.isItemPinned(id: "music"))
                }
                .buttonStyle(.plain)
                .help(store.isItemPinned(id: "music") ? "Pinned" : "Pin music drawer")
                }

                // MARK: - Atoll-inspired Real-time Waveform Scrubber
                VStack(spacing: 4) {
                    GeometryReader { geo in
                        let barCount = 28
                        let totalSpacing = CGFloat(barCount - 1) * 2.0
                        let barWidth = max((geo.size.width - totalSpacing) / CGFloat(barCount), 2.0)
                        let currentProgressIdx = Int(progress * Double(barCount))

                        HStack(spacing: 2) {
                            ForEach(0..<barCount, id: \.self) { idx in
                                let isPlayed = idx <= currentProgressIdx
                                let t = Date().timeIntervalSinceReferenceDate
                                let wave1 = sin(t * 3.4 + Double(idx) * 0.44)
                                let wave2 = cos(t * 2.2 + Double(idx) * 0.31)
                                let waveFactor = 0.5 + 0.5 * ((wave1 + wave2) / 2.0)

                                let sampleIdx = idx % max(store.musicTrack.waveformSamples.count, 1)
                                let baseSample = store.musicTrack.waveformSamples.isEmpty ? 0.35 : store.musicTrack.waveformSamples[sampleIdx]
                                let dynamicVal = isPlaying ? (baseSample * 0.35 + waveFactor * 0.65) : (baseSample * 0.30)
                                let minH: CGFloat = 4.0
                                let maxH: CGFloat = geo.size.height
                                let barH = max(minH, maxH * CGFloat(dynamicVal))

                                Capsule(style: .continuous)
                                    .fill(isPlayed ? musicColor : Color.primary.opacity(0.12))
                                    .frame(width: barWidth, height: barH)
                                    .animation(.spring(response: 0.22, dampingFraction: 0.70), value: dynamicVal)
                            }
                        }
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let newProgress = min(max(value.location.x / geo.size.width, 0.0), 1.0)
                                    SystemMusicSyncService.shared.seek(to: newProgress, store: store)
                                }
                        )
                    }
                    .frame(height: 22)

                    // Time Labels
                    HStack {
                        Text(timeString(for: currentSec))
                            .font(palette.fontMono)
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(timeString(for: store.musicTrack.durationSeconds))
                            .font(palette.fontMono)
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 4)

                // MARK: - Floating Media Buttons with Atoll-style Spring Nudges
                HStack(spacing: 28) {
                    // Backward Button
                    Button {
                        triggerBackwardNudge()
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
                    .buttonStyle(.plain)
                    .offset(x: backwardOffset)
                    .onHover { isBackwardHovered = $0 }

                    // Play / Pause Hero Button
                    Button {
                        triggerPlayPauseBounce()
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
                        .scaleEffect(playPauseScale)
                        .background(
                            Circle()
                                .fill(isPlayPauseHovered ? musicColor.opacity(0.12) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                    .onHover { isPlayPauseHovered = $0 }

                    // Forward Button
                    Button {
                        triggerForwardNudge()
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
                    .buttonStyle(.plain)
                    .offset(x: forwardOffset)
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

    private func triggerBackwardNudge() {
        withAnimation(.spring(response: 0.14, dampingFraction: 0.55)) {
            backwardOffset = -6
        }
        withAnimation(.spring(response: 0.24, dampingFraction: 0.65).delay(0.08)) {
            backwardOffset = 0
        }
    }

    private func triggerForwardNudge() {
        withAnimation(.spring(response: 0.14, dampingFraction: 0.55)) {
            forwardOffset = 6
        }
        withAnimation(.spring(response: 0.24, dampingFraction: 0.65).delay(0.08)) {
            forwardOffset = 0
        }
    }

    private func triggerPlayPauseBounce() {
        withAnimation(.spring(response: 0.14, dampingFraction: 0.45)) {
            playPauseScale = 0.85
        }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.60).delay(0.08)) {
            playPauseScale = 1.0
        }
    }

    private func timeString(for seconds: Double) -> String {
        let total = max(Int(seconds), 0)
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }
}
