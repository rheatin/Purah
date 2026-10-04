// Sources/PurahUI/DrawerPanels/MusicDrawerView.swift
import SwiftUI
import PurahCore

public struct MusicDrawerView: View {
    public let store: PurahWorkspaceStore

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    private var musicColor: Color {
        palette.podColor(for: "music")
    }

    public init(store: PurahWorkspaceStore) {
        self.store = store
    }

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 8) {
                // 独立小框 1：正在播放曲目卡片 (Now Playing Card)
                VStack(spacing: 8) {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .fill(palette.background)
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Circle()
                                        .stroke(musicColor.opacity(0.8), lineWidth: 1.5)
                                )
                                .modifier(OptionalGlow(color: musicColor, enabled: palette.useGlow))

                            Image(systemName: "music.note")
                                .font(.system(size: 18))
                                .foregroundColor(musicColor)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(store.musicTrack.title)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(palette.style == .native ? Color.primary : .white)
                                .lineLimit(1)
                            Text(store.musicTrack.artist)
                                .font(.system(size: 9))
                                .foregroundColor(.gray)
                                .lineLimit(1)
                        }

                        Spacer()

                        Text(store.musicTrack.isPlaying ? "PLAYING" : "PAUSED")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(store.musicTrack.isPlaying ? musicColor.opacity(0.2) : Color.gray.opacity(0.15))
                            .foregroundColor(store.musicTrack.isPlaying ? musicColor : .gray)
                            .cornerRadius(3)
                    }

                    // 进度条
                    VStack(spacing: 3) {
                        ProgressView(value: store.musicTrack.playbackProgress)
                            .tint(musicColor)

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
                .padding(8)
                .background(palette.solidDrawerBackground)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(musicColor.opacity(0.6), lineWidth: 1)
                )

                // 独立小框 2：播放控制卡片 (Controls Card)
                HStack(spacing: 28) {
                    Button(action: {
                        SystemMusicSyncService.shared.previousTrack(store: store)
                    }) {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 13))
                            .foregroundColor(palette.style == .native ? Color.primary : .white)
                    }
                    .buttonStyle(.plain)

                    Button {
                        SystemMusicSyncService.shared.togglePlayPause(store: store)
                    } label: {
                        Image(systemName: store.musicTrack.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(musicColor)
                            .modifier(OptionalGlow(color: musicColor, enabled: palette.useGlow))
                    }
                    .buttonStyle(.plain)

                    Button(action: {
                        SystemMusicSyncService.shared.nextTrack(store: store)
                    }) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 13))
                            .foregroundColor(palette.style == .native ? Color.primary : .white)
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(palette.solidDrawerBackground)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(palette.borderColor.opacity(0.6), lineWidth: 0.8)
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
