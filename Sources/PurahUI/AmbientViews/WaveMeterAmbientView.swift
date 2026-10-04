// Sources/PurahUI/AmbientViews/WaveMeterAmbientView.swift
import SwiftUI
import PurahCore

public struct WaveMeterAmbientView: View {
    public var samples: [Double]
    public var isPlaying: Bool
    public var isAnimated: Bool
    public var height: CGFloat

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    private var musicColor: Color {
        palette.podColor(for: "music")
    }

    public init(samples: [Double], isPlaying: Bool, isAnimated: Bool = true, height: CGFloat = 80.0) {
        self.samples = samples
        self.isPlaying = isPlaying
        self.isAnimated = isAnimated
        self.height = height
    }

    public var body: some View {
        let totalH = max(height, 40.0)
        let barCount = max(Int(totalH / 6.0), 12)
        let spacing: CGFloat = 2.0
        let barHeight = max((totalH - (CGFloat(barCount - 1) * spacing)) / CGFloat(barCount), 2.5)

        Group {
            if isPlaying && isAnimated {
                TimelineView(.animation) { timeline in
                    let time = timeline.date.timeIntervalSinceReferenceDate
                    VStack(spacing: spacing) {
                        ForEach(0..<barCount, id: \.self) { idx in
                            // 动态多频正弦谐波，完整铺满整条音乐槽位高度
                            let phase = Double(idx) * 0.45
                            let wave = (sin(time * 7.5 + phase) + cos(time * 4.2 + phase * 0.5) + 2.0) / 4.0
                            let sampleIdx = idx % max(samples.count, 1)
                            let amp = max(0.25, (samples[sampleIdx] * 0.4) + (wave * 0.6))

                            Rectangle()
                                .fill(musicColor)
                                .frame(width: max(amp * 8.0, 2.5), height: barHeight)
                        }
                    }
                    .modifier(OptionalGlow(color: musicColor, enabled: palette.useGlow))
                }
            } else {
                VStack(spacing: spacing) {
                    ForEach(0..<barCount, id: \.self) { idx in
                        let sampleIdx = idx % max(samples.count, 1)
                        let amp = isPlaying ? samples[sampleIdx] : 0.25
                        Rectangle()
                            .fill(isPlaying ? musicColor : palette.borderColor)
                            .frame(width: max(amp * 6.0, 2.0), height: barHeight)
                    }
                }
            }
        }
        .frame(height: totalH)
    }
}
