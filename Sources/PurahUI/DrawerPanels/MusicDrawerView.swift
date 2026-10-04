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
        VStack(spacing: 8) {
            // 顶部：封面/图标 + 曲目信息 + Pin 针 (宽阔饱满)
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(musicColor.opacity(0.18))
                        .frame(width: 44, height: 44)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(musicColor.opacity(0.8), lineWidth: 1.5)
                        )
                        .modifier(OptionalGlow(color: musicColor, enabled: palette.useGlow))

                    Image(systemName: "music.note")
                        .font(.system(size: 20))
                        .foregroundColor(musicColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(store.musicTrack.title)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(palette.style == .native ? Color.primary : .white)
                        .lineLimit(1)
                    Text(store.musicTrack.artist)
                        .font(.system(size: 10, design: .rounded))
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }

                Spacer()

                // Pin 针
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.65)) {
                        store.isDrawerPinned.toggle()
                    }
                } label: {
                    Image(systemName: store.isDrawerPinned ? "pin.fill" : "pin")
                        .foregroundColor(store.isDrawerPinned ? musicColor : .gray)
                        .font(.system(size: 11))
                        .scaleEffect(store.isDrawerPinned ? 1.2 : 1.0)
                }
                .buttonStyle(.plain)
                .help(store.isDrawerPinned ? "已固定常驻" : "固定音乐卡片")
            }

            // 宽幅进度条
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

            // 底部控制按钮 (大号饱满手感)
            HStack(spacing: 40) {
                Button(action: {
                    SystemMusicSyncService.shared.previousTrack(store: store)
                }) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 16))
                        .foregroundColor(palette.style == .native ? Color.primary : .white)
                }
                .buttonStyle(.plain)

                Button {
                    SystemMusicSyncService.shared.togglePlayPause(store: store)
                } label: {
                    Image(systemName: store.musicTrack.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 34))
                        .foregroundColor(musicColor)
                        .modifier(OptionalGlow(color: musicColor, enabled: palette.useGlow))
                }
                .buttonStyle(.plain)

                Button(action: {
                    SystemMusicSyncService.shared.nextTrack(store: store)
                }) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 16))
                        .foregroundColor(palette.style == .native ? Color.primary : .white)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
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
