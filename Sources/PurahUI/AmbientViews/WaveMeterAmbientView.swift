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
        let spacing: CGFloat = 2.0
        let barHeight: CGFloat = 2.2
        let step = barHeight + spacing
        let barCount = max(Int((totalH - 4.0) / step), 10)

        ZStack {
            // Background rail capsule
            Capsule()
                .fill(Color.primary.opacity(0.06))
                .frame(width: 8, height: totalH)

            // Full-height ladder of horizontal alternating sound bars
            VStack(spacing: spacing) {
                ForEach(0..<barCount, id: \.self) { idx in
                    AlternatingRungBar(
                        index: idx,
                        isPlaying: isPlaying && isAnimated && !reduceMotion,
                        musicColor: musicColor,
                        idleColor: palette.borderColor.opacity(0.55),
                        barHeight: barHeight
                    )
                }
            }
            .frame(width: 8, height: totalH, alignment: .center)
        }
        .frame(width: 8, height: totalH)
        .clipShape(Capsule())
    }
}

// MARK: - Alternating Horizontal Rung Bar (Hardware Composited, 0 KB Heap Allocations)
private struct AlternatingRungBar: View {
    let index: Int
    let isPlaying: Bool
    let musicColor: Color
    let idleColor: Color
    let barHeight: CGFloat

    @State private var isExpanded: Bool = false

    // 3-Phase wave distribution along the column gives silky traveling wave dynamics
    private var phaseGroup: Int { index % 3 }
    private var animationDuration: Double {
        switch phaseGroup {
        case 0: return 0.55
        case 1: return 0.72
        default: return 0.62
        }
    }
    private var targetMaxWidth: CGFloat {
        switch phaseGroup {
        case 0: return 7.6
        case 1: return 6.8
        default: return 7.4
        }
    }

    var body: some View {
        let currentWidth: CGFloat = {
            if isPlaying {
                return isExpanded ? targetMaxWidth : 2.5
            } else {
                return 2.5
            }
        }()

        Capsule()
            .fill(isPlaying ? musicColor : idleColor)
            .frame(width: currentWidth, height: barHeight)
            .frame(width: 8, alignment: .center)
            .onAppear {
                if isPlaying {
                    startLoop()
                }
            }
            .onChange(of: isPlaying) { _, playing in
                if playing {
                    startLoop()
                } else {
                    withAnimation(.easeOut(duration: 0.25)) {
                        isExpanded = false
                    }
                }
            }
    }

    private func startLoop() {
        let initialExpanded = (index % 2 == 0)
        isExpanded = initialExpanded
        withAnimation(
            .easeInOut(duration: animationDuration)
                .repeatForever(autoreverses: true)
        ) {
            isExpanded = !initialExpanded
        }
    }
}
