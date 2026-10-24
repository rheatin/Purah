// Sources/PurahUI/Common/PurahFluidWaveformBarView.swift
import SwiftUI
import PurahCore

public enum PurahWaveformSubStyle: String, Codable, Sendable, CaseIterable {
    case neonVUTower
    case auroraWave
    case smoothProgress
    case minimalist
}

/// Generic, high-performance 60/120 FPS fluid waveform and audio level meter rail bar.
/// Suitable for music players, voice recorders, sound generators, and audio monitors.
public struct PurahFluidWaveformBarView: View {
    public var tintColor: Color
    public var progress: Double
    public var isPlaying: Bool
    public var isAnimated: Bool
    public var height: CGFloat
    public var barWidth: CGFloat
    public var subStyle: PurahWaveformSubStyle
    public var liveEnergy: (level: Double, bass: Double, beat: Double)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        tintColor: Color,
        progress: Double = 0.0,
        isPlaying: Bool = false,
        isAnimated: Bool = true,
        height: CGFloat = 80.0,
        barWidth: CGFloat = 8.0,
        subStyle: PurahWaveformSubStyle = .neonVUTower,
        liveEnergy: (level: Double, bass: Double, beat: Double)? = nil
    ) {
        self.tintColor = tintColor
        self.progress = min(max(progress, 0.0), 1.0)
        self.isPlaying = isPlaying
        self.isAnimated = isAnimated
        self.height = height
        self.barWidth = barWidth
        self.subStyle = subStyle
        self.liveEnergy = liveEnergy
    }

    public var body: some View {
        let totalH = max(height, 36.0)
        let barW = max(barWidth, 4.0)

        Group {
            switch subStyle {
            case .minimalist:
                Capsule()
                    .fill(isPlaying ? tintColor.opacity(0.90) : tintColor.opacity(0.45))
                    .frame(width: barW, height: totalH)

            case .smoothProgress:
                smoothProgressCanvas(totalH: totalH, barW: barW)

            case .neonVUTower:
                neonVUTowerCanvas(totalH: totalH, barW: barW)

            case .auroraWave:
                auroraWaveCanvas(totalH: totalH, barW: barW)
            }
        }
        .frame(width: barW, height: totalH)
    }

    private func smoothProgressCanvas(totalH: CGFloat, barW: CGFloat) -> some View {
        TimelineView(.animation(paused: !isPlaying || reduceMotion)) { _ in
            Canvas { context, size in
                let w = size.width
                let h = size.height
                let centerX = w / 2.0
                let playheadY = CGFloat(progress) * h

                let bgRect = CGRect(x: 0, y: 0, width: w, height: h)
                context.fill(Path(roundedRect: bgRect, cornerRadius: w / 2), with: .color(tintColor.opacity(0.15)))

                let pillW = max(w - 1.0, 3.0)
                let pillX = (w - pillW) / 2.0
                if playheadY > 1.0 {
                    let playedRect = CGRect(x: pillX, y: 0, width: pillW, height: playheadY)
                    context.fill(
                        Path(roundedRect: playedRect, cornerRadius: pillW / 2),
                        with: .linearGradient(
                            Gradient(colors: [tintColor, tintColor.opacity(0.85)]),
                            startPoint: CGPoint(x: centerX, y: 0),
                            endPoint: CGPoint(x: centerX, y: max(playheadY, 4.0))
                        )
                    )
                }

                if playheadY > 0 && playheadY < h {
                    let needleH: CGFloat = 2.5
                    let needleRect = CGRect(x: 0.5, y: playheadY - (needleH / 2.0), width: w - 1.0, height: needleH)
                    context.fill(Path(roundedRect: needleRect, cornerRadius: 1.2), with: .color(.white))
                }
            }
            .clipShape(Capsule())
        }
    }

    private func neonVUTowerCanvas(totalH: CGFloat, barW: CGFloat) -> some View {
        let shouldAnimate = isAnimated && isPlaying && !reduceMotion

        return TimelineView(.animation(paused: !shouldAnimate)) { timeline in
            Canvas { context, size in
                let w = size.width
                let h = size.height
                let stepH: CGFloat = 8.0
                let gap: CGFloat = 3.0
                let count = max(Int((h - 4.0) / (stepH + gap)), 8)
                let time = shouldAnimate ? timeline.date.timeIntervalSinceReferenceDate : 0.0

                context.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: w, height: h), cornerRadius: w / 2), with: .color(Color.white.opacity(0.06)))

                let liveLevel = liveEnergy?.level ?? (isPlaying ? (0.4 + 0.3 * sin(time * 6.0)) : 0.0)
                let liveBass = liveEnergy?.bass ?? (isPlaying ? (0.3 + 0.2 * cos(time * 4.0)) : 0.0)
                let activeBlocks = max(Int(Double(count) * min(max(liveLevel * 1.5 + liveBass * 0.5, 0.0), 1.0)), isPlaying ? 2 : 0)

                for idx in 0..<count {
                    let blockY = h - CGFloat(idx + 1) * (stepH + gap)
                    guard blockY >= 0 else { continue }
                    let blockRect = CGRect(x: 1.0, y: blockY, width: w - 2.0, height: stepH)
                    let isActive = idx < activeBlocks

                    if isActive {
                        let ratio = Double(idx) / Double(count)
                        let blockColor: Color = {
                            if ratio > 0.85 { return PurahTelemetryMetricResolver.dangerRed }
                            if ratio > 0.65 { return PurahTelemetryMetricResolver.warningYellow }
                            return tintColor
                        }()
                        context.fill(Path(roundedRect: blockRect, cornerRadius: 1.5), with: .color(blockColor.opacity(0.95)))
                    } else {
                        context.fill(Path(roundedRect: blockRect, cornerRadius: 1.5), with: .color(Color.white.opacity(0.08)))
                    }
                }
            }
            .clipShape(Capsule())
        }
    }

    private func auroraWaveCanvas(totalH: CGFloat, barW: CGFloat) -> some View {
        let shouldAnimate = isAnimated && isPlaying && !reduceMotion

        return TimelineView(.animation(paused: !shouldAnimate)) { timeline in
            Canvas { context, size in
                let w = size.width
                let h = size.height
                let time = shouldAnimate ? timeline.date.timeIntervalSinceReferenceDate : 0.0

                context.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: w, height: h), cornerRadius: w / 2), with: .color(Color.white.opacity(0.06)))

                let liveLevel = liveEnergy?.level ?? (isPlaying ? 0.5 : 0.0)
                let waveAmp = isPlaying ? (0.2 + liveLevel * 0.6) : 0.05
                let wavePoints = 16

                var path = Path()
                path.move(to: CGPoint(x: 0, y: h))

                for i in 0...wavePoints {
                    let y = h * CGFloat(i) / CGFloat(wavePoints)
                    let normY = Double(i) / Double(wavePoints)
                    let wave = sin(normY * 4.0 * .pi + time * 5.0) * cos(normY * 2.0 * .pi - time * 3.0)
                    let x = (w / 2.0) + CGFloat(wave * waveAmp) * (w / 2.0)
                    path.addLine(to: CGPoint(x: max(min(x, w), 0), y: y))
                }
                path.addLine(to: CGPoint(x: 0, y: 0))
                path.closeSubpath()

                context.fill(path, with: .linearGradient(
                    Gradient(colors: [tintColor.opacity(0.85), tintColor.opacity(0.4)]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: w, y: h)
                ))
            }
            .clipShape(Capsule())
        }
    }
}
