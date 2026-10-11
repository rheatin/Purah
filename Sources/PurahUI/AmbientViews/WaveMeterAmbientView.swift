// Sources/PurahUI/AmbientViews/WaveMeterAmbientView.swift
import SwiftUI
import PurahCore

public struct WaveMeterAmbientView: View {
    public var samples: [Double]
    public var isPlaying: Bool
    public var isAnimated: Bool
    public var height: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

        VStack(spacing: spacing) {
            ForEach(0..<barCount, id: \.self) { idx in
                let sampleIdx = idx % max(samples.count, 1)
                let rawSample = samples.isEmpty ? 0.35 : samples[sampleIdx]
                let amp = isPlaying ? max(rawSample, 0.25) : 0.25
                let w = max(CGFloat(amp) * 8.0, 2.0)

                RoundedRectangle(cornerRadius: 1)
                    .fill(isPlaying ? musicColor : palette.borderColor.opacity(0.6))
                    .frame(width: w, height: barHeight)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .animation(isPlaying && isAnimated && !reduceMotion ? .easeInOut(duration: 0.35) : nil, value: w)
            }
        }
        .frame(width: 8, height: totalH)
    }
}
