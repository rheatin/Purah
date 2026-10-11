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
        let barW: CGFloat = 8.0
        let shouldAnimate = isPlaying && isAnimated && !reduceMotion

        TimelineView(.animation(paused: !shouldAnimate)) { timeline in
            Canvas { context, size in
                let w = size.width
                let h = size.height
                let centerX = w / 2.0
                let time = shouldAnimate ? timeline.date.timeIntervalSinceReferenceDate : 0.0
                let clampedProgress = min(max(progress, 0.0), 1.0)
                let playheadY = CGFloat(clampedProgress) * h

                // 1. Background Track Capsule
                let bgRect = CGRect(x: 0, y: 0, width: w, height: h)
                context.fill(Path(roundedRect: bgRect, cornerRadius: w / 2), with: .color(musicColor.opacity(0.12)))

                // 2. Continuous Fluid Superposition Audio Wave Ribbon
                if shouldAnimate {
                    let stepCount = max(Int(h / 3.0), 20)
                    let dy = h / CGFloat(stepCount)

                    var rightPoints: [CGPoint] = []
                    var leftPoints: [CGPoint] = []

                    for i in 0...stepCount {
                        let y = min(CGFloat(i) * dy, h)
                        let ny = Double(y / h)

                        // Superposition wave equations (w1*sin + w2*cos + w3*sin) per AGENTS.md
                        let wave1 = sin(ny * 14.0 - time * 5.0)
                        let wave2 = cos(ny * 8.0 + time * 3.6)
                        let wave3 = sin(ny * 22.0 - time * 6.5)
                        let combined = (wave1 * 0.45 + wave2 * 0.35 + wave3 * 0.20) // -1.0 .. 1.0
                        let energy = (combined + 1.0) / 2.0 // 0.0 .. 1.0

                        let sampleIdx = Int(ny * Double(samples.count)) % max(samples.count, 1)
                        let sampleVal = samples.isEmpty ? 0.5 : samples[sampleIdx]
                        let amp = (energy * 0.65) + (sampleVal * 0.35)

                        // Symmetrically undulate width: 2.8pt at troughs, 7.4pt at peaks
                        let minHalfW: CGFloat = 1.4
                        let maxHalfW: CGFloat = min((w - 0.6) / 2.0, 3.7)
                        let halfW = minHalfW + CGFloat(amp) * (maxHalfW - minHalfW)

                        rightPoints.append(CGPoint(x: centerX + halfW, y: y))
                        leftPoints.append(CGPoint(x: centerX - halfW, y: y))
                    }

                    // Build closed fluid ribbon path
                    var wavePath = Path()
                    if let firstRight = rightPoints.first {
                        wavePath.move(to: firstRight)
                        for pt in rightPoints.dropFirst() {
                            wavePath.addLine(to: pt)
                        }
                    }
                    if let lastLeft = leftPoints.last {
                        wavePath.addLine(to: lastLeft)
                        for pt in leftPoints.reversed().dropFirst() {
                            wavePath.addLine(to: pt)
                        }
                    }
                    wavePath.closeSubpath()

                    // Draw Played segment with vibrant glowing gradient, and Remaining with subtle sheen
                    context.drawLayer { ctx in
                        let playedClipRect = CGRect(x: 0, y: 0, width: w, height: max(playheadY, 4.0))
                        ctx.clip(to: Path(playedClipRect))
                        ctx.fill(
                            wavePath,
                            with: .linearGradient(
                                Gradient(colors: [musicColor, musicColor.opacity(0.85)]),
                                startPoint: CGPoint(x: centerX, y: 0),
                                endPoint: CGPoint(x: centerX, y: max(playheadY, 4.0))
                            )
                        )
                    }

                    context.drawLayer { ctx in
                        let unplayedClipRect = CGRect(x: 0, y: playheadY, width: w, height: max(h - playheadY, 0.0))
                        ctx.clip(to: Path(unplayedClipRect))
                        ctx.fill(wavePath, with: .color(musicColor.opacity(0.35)))
                    }

                    // 3. Glowing Playhead Needle
                    if playheadY > 0 && playheadY < h {
                        let needleH: CGFloat = 2.0
                        let needleW: CGFloat = w - 1.0
                        let needleRect = CGRect(x: (w - needleW) / 2.0, y: playheadY - (needleH / 2.0), width: needleW, height: needleH)
                        context.fill(Path(roundedRect: needleRect, cornerRadius: 1), with: .color(.white))
                    }
                } else {
                    // Paused state: Serene, clean, calm progress pill with zero comb lines
                    let pillW: CGFloat = max(w - 2.0, 4.0)
                    let pillX = (w - pillW) / 2.0

                    // Played portion
                    if playheadY > 2.0 {
                        let playedRect = CGRect(x: pillX, y: 0, width: pillW, height: playheadY)
                        context.fill(
                            Path(roundedRect: playedRect, cornerRadius: pillW / 2),
                            with: .color(isPlaying ? musicColor : palette.borderColor.opacity(0.7))
                        )
                    }

                    // Playhead needle
                    if playheadY > 0 && playheadY < h {
                        let needleRect = CGRect(x: 1.0, y: playheadY - 1.0, width: w - 2.0, height: 2.0)
                        context.fill(Path(roundedRect: needleRect, cornerRadius: 1), with: .color(isPlaying ? .white : palette.borderColor))
                    }
                }
            }
            .frame(width: barW, height: totalH)
            .clipShape(Capsule())
        }
        .frame(width: barW, height: totalH)
    }
}
