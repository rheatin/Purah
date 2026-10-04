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
                // 使用 30fps 周期采样 + Metal GPU Canvas 直推，杜绝高 CPU 占用与内存抖动
                TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { timeline in
                    Canvas { context, size in
                        let time = timeline.date.timeIntervalSinceReferenceDate
                        for idx in 0..<barCount {
                            let phase = Double(idx) * 0.45
                            let wave = (sin(time * 7.5 + phase) + cos(time * 4.2 + phase * 0.5) + 2.0) / 4.0
                            let sampleIdx = idx % max(samples.count, 1)
                            let amp = max(0.25, (samples[sampleIdx] * 0.4) + (wave * 0.6))
                            let w = max(CGFloat(amp) * 8.0, 2.5)
                            let y = CGFloat(idx) * (barHeight + spacing)

                            let rect = CGRect(x: size.width - w, y: y, width: w, height: barHeight)
                            context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(musicColor))
                        }
                    }
                    .frame(width: 8, height: totalH)
                }
            } else {
                Canvas { context, size in
                    for idx in 0..<barCount {
                        let sampleIdx = idx % max(samples.count, 1)
                        let amp = isPlaying ? samples[sampleIdx] : 0.25
                        let w = max(CGFloat(amp) * 6.0, 2.0)
                        let y = CGFloat(idx) * (barHeight + spacing)
                        let rect = CGRect(x: size.width - w, y: y, width: w, height: barHeight)
                        context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(isPlaying ? musicColor : palette.borderColor))
                    }
                }
                .frame(width: 8, height: totalH)
            }
        }
        .drawingGroup() // 开启 Metal GPU 离屏渲染加速
    }
}
