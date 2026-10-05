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
        let progress = store.musicTrack.playbackProgress

        VStack(spacing: 10) {
            // MARK: - Header: Album Art & Track Info & Pin
            HStack(spacing: 10) {
                // Album Art Capsule
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(musicColor.opacity(0.15))
                        .frame(width: 42, height: 42)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(musicColor.opacity(0.7), lineWidth: 1.2)
                        )
                        .modifier(OptionalGlow(color: musicColor, enabled: palette.useGlow))

                    Image(systemName: "music.note")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(musicColor)
                        .symbolEffect(.bounce, value: isPlaying)
                }

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
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.65)) {
                        store.togglePinItem(id: "music")
                    }
                } label: {
                    Image(systemName: store.isItemPinned(id: "music") ? "pin.fill" : "pin")
                        .foregroundColor(store.isItemPinned(id: "music") ? musicColor : .gray)
                        .font(.system(size: 11))
                        .scaleEffect(store.isItemPinned(id: "music") ? 1.15 : 1.0)
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
                            let sampleIdx = idx % store.musicTrack.waveformSamples.count
                            let sampleVal = store.musicTrack.waveformSamples[sampleIdx]
                            let minH: CGFloat = 4.0
                            let maxH: CGFloat = geo.size.height
                            let barH = max(minH, maxH * CGFloat(sampleVal))

                            Capsule(style: .continuous)
                                .fill(isPlayed ? musicColor : Color.primary.opacity(0.12))
                                .frame(width: barWidth, height: barH)
                                .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isPlaying)
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let newProgress = min(max(value.location.x / geo.size.width, 0.0), 1.0)
                                store.musicTrack.playbackProgress = newProgress
                            }
                    )
                }
                .frame(height: 22)

                // Time Labels
                HStack {
                    Text(timeString(for: progress * 210))
                        .font(palette.fontMono)
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("03:30")
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
        .onAppear {
            SystemMusicSyncService.shared.startListening(into: store)
        }
    }

    private func triggerBackwardNudge() {
        withAnimation(.spring(response: 0.16, dampingFraction: 0.65)) {
            backwardOffset = -5
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.75)) {
                backwardOffset = 0
            }
        }
    }

    private func triggerForwardNudge() {
        withAnimation(.spring(response: 0.16, dampingFraction: 0.65)) {
            forwardOffset = 5
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.75)) {
                forwardOffset = 0
            }
        }
    }

    private func triggerPlayPauseBounce() {
        withAnimation(.spring(response: 0.14, dampingFraction: 0.5)) {
            playPauseScale = 0.88
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.65)) {
                playPauseScale = 1.0
            }
        }
    }

    private func timeString(for seconds: Double) -> String {
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }
}
