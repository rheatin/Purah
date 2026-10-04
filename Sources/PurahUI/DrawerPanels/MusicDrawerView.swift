// Sources/PurahUI/DrawerPanels/MusicDrawerView.swift
import SwiftUI
import PurahCore

public struct MusicDrawerView: View {
    public let store: PurahWorkspaceStore

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    public init(store: PurahWorkspaceStore) {
        self.store = store
    }

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 10) {
                // 独立小框 1：正在播放曲目卡片 (Now Playing Card)
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(palette.background)
                                .frame(width: 50, height: 50)
                                .overlay(
                                    Circle()
                                        .stroke(palette.primaryAccent.opacity(0.8), lineWidth: 1.5)
                                )
                                .modifier(OptionalGlow(color: palette.primaryAccent, enabled: palette.useGlow))

                            Image(systemName: "music.note")
                                .font(.system(size: 22))
                                .foregroundColor(palette.primaryAccent)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(store.musicTrack.title)
                                .font(palette.fontTitle)
                                .foregroundColor(palette.style == .native ? Color.primary : .white)
                                .lineLimit(1)
                            Text(store.musicTrack.artist)
                                .font(.caption)
                                .foregroundColor(.gray)
                                .lineLimit(1)
                        }

                        Spacer()

                        Text(store.musicTrack.isPlaying ? "PLAYING" : "PAUSED")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(store.musicTrack.isPlaying ? palette.primaryAccent.opacity(0.15) : Color.gray.opacity(0.15))
                            .foregroundColor(store.musicTrack.isPlaying ? palette.primaryAccent : .gray)
                            .cornerRadius(4)
                    }

                    // 进度条
                    VStack(spacing: 4) {
                        ProgressView(value: store.musicTrack.playbackProgress)
                            .tint(palette.primaryAccent)

                        HStack {
                            Text(timeString(for: store.musicTrack.playbackProgress * 210))
                                .font(palette.fontMono)
                                .foregroundColor(.gray)
                            Spacer()
                            Text("03:30")
                                .font(palette.fontMono)
                                .foregroundColor(.gray)
                        }
                    }
                }
                .padding(12)
                .background(palette.surfaceBackground)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(palette.borderColor.opacity(0.5), lineWidth: 1)
                )

                // 独立小框 2：播放控制卡片 (Controls Card)
                HStack(spacing: 36) {
                    Button(action: {
                        SystemMusicSyncService.shared.previousTrack(store: store)
                    }) {
                        Image(systemName: "backward.fill")
                            .font(.title3)
                            .foregroundColor(palette.style == .native ? Color.primary : .white)
                    }
                    .buttonStyle(.plain)

                    Button {
                        SystemMusicSyncService.shared.togglePlayPause(store: store)
                    } label: {
                        Image(systemName: store.musicTrack.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 38))
                            .foregroundColor(palette.primaryAccent)
                            .modifier(OptionalGlow(color: palette.primaryAccent, enabled: palette.useGlow))
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        SystemMusicSyncService.shared.nextTrack(store: store)
                    }) {
                        Image(systemName: "forward.fill")
                            .font(.title3)
                            .foregroundColor(palette.style == .native ? Color.primary : .white)
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(palette.surfaceBackground)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(palette.borderColor.opacity(0.5), lineWidth: 1)
                )
            }
        }
        .onAppear {
            SystemMusicSyncService.shared.startListening(into: store)
        }
    }

    private func timeString(for seconds: Double) -> String {
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }
}
