// Sources/PurahUI/AmbientViews/WaveMeterAmbientView.swift
import SwiftUI
import PurahCore

public struct WaveMeterAmbientView: View {
    public var progress: Double
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

    public init(
        progress: Double = 0.0,
        samples: [Double] = [],
        isPlaying: Bool,
        isAnimated: Bool = true,
        height: CGFloat = 80.0
    ) {
        self.progress = progress
        self.samples = samples
        self.isPlaying = isPlaying
        self.isAnimated = isAnimated
        self.height = height
    }

    public init(samples: [Double], isPlaying: Bool, isAnimated: Bool = true, height: CGFloat = 80.0) {
        self.init(progress: 0.0, samples: samples, isPlaying: isPlaying, isAnimated: isAnimated, height: height)
    }

    public var body: some View {
        let totalH = max(height, 40.0)
        let clampedProgress = min(max(progress, 0.0), 1.0)
        let fillHeight = totalH * CGFloat(clampedProgress)

        ZStack(alignment: .top) {
            // Layer 1: Background Rail Capsule
            Capsule()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 8, height: totalH)

            // Layer 2: Vertical Playback Progress Fill (Top to Bottom)
            Capsule()
                .fill(musicColor.opacity(isPlaying ? 0.32 : 0.16))
                .frame(width: 8, height: max(fillHeight, 0))
                .animation(.easeInOut(duration: 0.6), value: clampedProgress)

            // Layer 3: Centered Micro Equalizer Bars (Zero Memory, Hardware Composited)
            VStack {
                Spacer()
                HStack(spacing: 0.8) {
                    MicroEqualizerBar(
                        minH: 3.0,
                        maxH: 12.0,
                        duration: 0.55,
                        isPlaying: isPlaying && isAnimated && !reduceMotion,
                        staticH: isPlaying ? 8.0 : 2.5,
                        color: isPlaying ? musicColor : palette.borderColor.opacity(0.6)
                    )

                    MicroEqualizerBar(
                        minH: 4.0,
                        maxH: 18.0,
                        duration: 0.75,
                        isPlaying: isPlaying && isAnimated && !reduceMotion,
                        staticH: isPlaying ? 14.0 : 2.5,
                        color: isPlaying ? musicColor : palette.borderColor.opacity(0.6)
                    )

                    MicroEqualizerBar(
                        minH: 3.0,
                        maxH: 10.0,
                        duration: 0.62,
                        isPlaying: isPlaying && isAnimated && !reduceMotion,
                        staticH: isPlaying ? 6.0 : 2.5,
                        color: isPlaying ? musicColor : palette.borderColor.opacity(0.6)
                    )
                }
                .frame(width: 8)
                Spacer()
            }
        }
        .frame(width: 8, height: totalH)
        .clipShape(Capsule())
    }
}

// MARK: - Micro Equalizer Bar (Hardware Accelerated, 0 KB Heap Allocations)
private struct MicroEqualizerBar: View {
    let minH: CGFloat
    let maxH: CGFloat
    let duration: Double
    let isPlaying: Bool
    let staticH: CGFloat
    let color: Color

    @State private var isScaled: Bool = false

    var body: some View {
        RoundedRectangle(cornerRadius: 0.8)
            .fill(color)
            .frame(width: 1.6, height: isPlaying ? (isScaled ? maxH : minH) : staticH)
            .onAppear {
                if isPlaying {
                    withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: true)) {
                        isScaled = true
                    }
                }
            }
            .onChange(of: isPlaying) { _, playing in
                if playing {
                    withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: true)) {
                        isScaled = true
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.2)) {
                        isScaled = false
                    }
                }
            }
    }
}
