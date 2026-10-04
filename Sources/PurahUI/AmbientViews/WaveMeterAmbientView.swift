// Sources/PurahUI/AmbientViews/WaveMeterAmbientView.swift
import SwiftUI
import PurahCore

public struct WaveMeterAmbientView: View {
    public var samples: [Double]
    public var isPlaying: Bool
    public var isAnimated: Bool

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    private var musicColor: Color {
        palette.podColor(for: "music")
    }

    public init(samples: [Double], isPlaying: Bool, isAnimated: Bool = true) {
        self.samples = samples
        self.isPlaying = isPlaying
        self.isAnimated = isAnimated
    }

    public var body: some View {
        if isPlaying && isAnimated {
            TimelineView(.animation) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                VStack(spacing: 2.0) {
                    ForEach(samples.indices, id: \.self) { idx in
                        // 动态正弦拟合真实声谱律动跳跃
                        let wave = (sin(time * 8.0 + Double(idx) * 1.1) + 1.0) / 2.0
                        let amp = max(0.2, (samples[idx] * 0.5) + (wave * 0.5))
                        Rectangle()
                            .fill(musicColor)
                            .frame(width: max(amp * 8.0, 2.5), height: 3.0)
                    }
                }
                .modifier(OptionalGlow(color: musicColor, enabled: palette.useGlow))
            }
        } else {
            VStack(spacing: 2.0) {
                ForEach(samples.indices, id: \.self) { idx in
                    let amp = isPlaying ? samples[idx] : 0.2
                    Rectangle()
                        .fill(isPlaying ? musicColor : palette.borderColor)
                        .frame(width: max(amp * 6.0, 2.0), height: 3.0)
                }
            }
        }
    }
}
