// Sources/PurahUI/AmbientViews/WaveMeterAmbientView.swift
import SwiftUI
import PurahCore

public struct WaveMeterAmbientView: View {
    public var style: MusicRailStyle
    public var track: MusicTrackInfo
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
        style: MusicRailStyle = .dynamicWaveform,
        track: MusicTrackInfo = MusicTrackInfo(),
        progress: Double = 0.0,
        samples: [Double] = [],
        isPlaying: Bool,
        isAnimated: Bool = true,
        height: CGFloat = 80.0
    ) {
        self.style = style
        self.track = track
        self.progress = progress
        self.samples = samples
        self.isPlaying = isPlaying
        self.isAnimated = isAnimated
        self.height = height
    }

    public init(
        progress: Double = 0.0,
        samples: [Double] = [],
        isPlaying: Bool,
        isAnimated: Bool = true,
        height: CGFloat = 80.0
    ) {
        self.init(style: .dynamicWaveform, track: MusicTrackInfo(), progress: progress, samples: samples, isPlaying: isPlaying, isAnimated: isAnimated, height: height)
    }

    public init(samples: [Double], isPlaying: Bool, isAnimated: Bool = true, height: CGFloat = 80.0) {
        self.init(style: .dynamicWaveform, track: MusicTrackInfo(), progress: 0.0, samples: samples, isPlaying: isPlaying, isAnimated: isAnimated, height: height)
    }

    public var body: some View {
        let totalH = max(height, 40.0)
        let barW: CGFloat = 8.0

        switch style {
        case .minimalist:
            Capsule()
                .fill(
                    isPlaying
                        ? musicColor.opacity(0.90)
                        : musicColor.opacity(0.45)
                )
                .frame(width: barW, height: totalH)

        case .smoothProgress:
            smoothProgressView(totalH: totalH, barW: barW)

        case .dynamicWaveform:
            dynamicWaveformView(totalH: totalH, barW: barW)
        }
    }

    // MARK: - Mode 2: 60 FPS Silky Smooth Live Progress Bar
    private func smoothProgressView(totalH: CGFloat, barW: CGFloat) -> some View {
        TimelineView(.animation(paused: !isPlaying)) { timeline in
            Canvas { context, size in
                let w = size.width
                let h = size.height
                let centerX = w / 2.0

                // Time-anchor continuous progress calculation
                let elapsed = isPlaying ? max(timeline.date.timeIntervalSince(track.lastUpdated), 0.0) : 0.0
                let effectiveRate = track.playbackRate > 0 ? track.playbackRate : (isPlaying ? 1.0 : 0.0)
                let currentPos = track.currentPositionSeconds + (elapsed * effectiveRate)
                let continuousProgress: Double
                if track.durationSeconds > 0 {
                    continuousProgress = min(max(currentPos / track.durationSeconds, 0.0), 1.0)
                } else {
                    continuousProgress = min(max(progress, 0.0), 1.0)
                }
                let playheadY = CGFloat(continuousProgress) * h

                // 1. Background Track
                let bgRect = CGRect(x: 0, y: 0, width: w, height: h)
                context.fill(Path(roundedRect: bgRect, cornerRadius: w / 2), with: .color(musicColor.opacity(0.15)))

                // 2. Played Fill with vibrant gradient
                let pillW: CGFloat = max(w - 1.0, 4.0)
                let pillX = (w - pillW) / 2.0
                if playheadY > 1.0 {
                    let playedRect = CGRect(x: pillX, y: 0, width: pillW, height: playheadY)
                    context.fill(
                        Path(roundedRect: playedRect, cornerRadius: pillW / 2),
                        with: .linearGradient(
                            Gradient(colors: [musicColor, musicColor.opacity(0.85)]),
                            startPoint: CGPoint(x: centerX, y: 0),
                            endPoint: CGPoint(x: centerX, y: max(playheadY, 4.0))
                        )
                    )
                }

                // 3. Glowing Playhead Needle
                if playheadY > 0 && playheadY < h {
                    let needleH: CGFloat = 2.5
                    let needleRect = CGRect(x: 0.5, y: playheadY - (needleH / 2.0), width: w - 1.0, height: needleH)
                    context.fill(Path(roundedRect: needleRect, cornerRadius: 1.2), with: .color(.white))
                }
            }
            .frame(width: barW, height: totalH)
            .clipShape(Capsule())
        }
        .frame(width: barW, height: totalH)
    }

    // MARK: - Mode 3: Kinetic Audio Rhythm Engine (复合节拍物理震荡引擎)
    private func dynamicWaveformView(totalH: CGFloat, barW: CGFloat) -> some View {
        let shouldAnimate = isPlaying && isAnimated && !reduceMotion

        return TimelineView(.animation(paused: !shouldAnimate)) { timeline in
            Canvas { context, size in
                let w = size.width
                let h = size.height
                let centerX = w / 2.0
                let time = shouldAnimate ? timeline.date.timeIntervalSinceReferenceDate : 0.0

                // 1. Time-anchor continuous progress calculation
                let elapsed = isPlaying ? max(timeline.date.timeIntervalSince(track.lastUpdated), 0.0) : 0.0
                let effectiveRate = track.playbackRate > 0 ? track.playbackRate : (isPlaying ? 1.0 : 0.0)
                let currentPos = track.currentPositionSeconds + (elapsed * effectiveRate)
                let continuousProgress: Double
                if track.durationSeconds > 0 {
                    continuousProgress = min(max(currentPos / track.durationSeconds, 0.0), 1.0)
                } else {
                    continuousProgress = min(max(progress, 0.0), 1.0)
                }
                let playheadY = CGFloat(continuousProgress) * h
                let primaryColor = musicColor
                let secondaryColor = Color(hex: "#FF7597")

                // 2. Pseudo-Beat Multi-Band Rhythm Physics Model (125 BPM Bass Kick + Snare + Phrase Tension)
                let beatPeriod = 0.48 // ~125 BPM
                let beatPhase = shouldAnimate ? (time.truncatingRemainder(dividingBy: beatPeriod) / beatPeriod) : 0.0
                // Sharp exponential acoustic envelope for bass kick
                let kickPunch = shouldAnimate ? exp(-beatPhase * 6.5) : 0.0

                // Snare backbeat on measure half-notes (0.96s)
                let measurePhase = shouldAnimate ? (time.truncatingRemainder(dividingBy: 0.96) / 0.96) : 0.0
                let snarePunch = (shouldAnimate && measurePhase > 0.45 && measurePhase < 0.70)
                    ? exp(-(measurePhase - 0.45) * 10.0)
                    : 0.0

                // Macro phrase tension (verse to chorus energy surge ~ 16s cycle)
                let phraseTension = shouldAnimate ? (sin(time * 0.38) * 0.5 + 0.5) : 0.3
                let dynamicEnergy = 0.45 + (kickPunch * 0.45) + (snarePunch * 0.20) + (phraseTension * 0.15)

                // 3. Dark glass track with rhythmic kick bloom
                let bgRect = CGRect(x: 0, y: 0, width: w, height: h)
                context.fill(Path(roundedRect: bgRect, cornerRadius: w / 2), with: .color(primaryColor.opacity(0.12 + kickPunch * 0.08)))

                // 4. Played background fill (rhythmically breathing ambient illumination)
                if playheadY > 1.0 {
                    let playedRect = CGRect(x: 1, y: 0, width: w - 2, height: playheadY)
                    context.fill(Path(roundedRect: playedRect, cornerRadius: (w - 2) / 2), with: .color(primaryColor.opacity(0.20 + kickPunch * 0.12)))
                }

                // 5. Dual-Beam Interwoven Harmonic Sine Waves with Kick Explosion
                var path1 = Path()
                var path2 = Path()
                var crossFlares: [CGPoint] = []

                let steps = max(Int(h / 2.5), 32)
                let dy = h / CGFloat(steps)
                let speedMult = 1.0 + (kickPunch * 0.4)

                for i in 0...steps {
                    let y = CGFloat(i) * dy
                    let ny = Double(y / h)

                    // Kinetic traveling wave equations modulated by physical energy
                    let wave1 = shouldAnimate
                        ? (sin(ny * 13.0 - time * 6.2 * speedMult) * 0.72 + cos(ny * 24.0 + time * 4.2) * 0.28)
                        : (sin(ny * 9.5) * 0.65)
                    let wave2 = shouldAnimate
                        ? (sin(ny * 13.0 - time * 6.2 * speedMult + 2.3) * 0.72 + cos(ny * 24.0 - time * 4.5) * 0.28)
                        : (cos(ny * 9.5 + 1.4) * 0.65)

                    // Amplitude aggressively widens during kick impact
                    let maxSpread = (w / 2.0 - 0.9) * CGFloat(dynamicEnergy)
                    let x1 = centerX + CGFloat(wave1) * maxSpread
                    let x2 = centerX + CGFloat(wave2) * maxSpread

                    if i == 0 {
                        path1.move(to: CGPoint(x: x1, y: y))
                        path2.move(to: CGPoint(x: x2, y: y))
                    } else {
                        path1.addLine(to: CGPoint(x: x1, y: y))
                        path2.addLine(to: CGPoint(x: x2, y: y))
                    }

                    // Detect phase clash nodes for explosive energy sparkle
                    if shouldAnimate && abs(x1 - x2) < 0.9 && i % 3 == 0 {
                        crossFlares.append(CGPoint(x: (x1 + x2) / 2.0, y: y))
                    }
                }

                // Stroke with dynamic line width and energetic glow
                let strokeW1 = 1.5 + CGFloat(kickPunch * 0.6)
                let strokeW2 = 1.3 + CGFloat(snarePunch * 0.5)
                context.stroke(path1, with: .color(primaryColor), lineWidth: strokeW1)
                context.stroke(path2, with: .color(secondaryColor), lineWidth: strokeW2)

                // 6. Cross-Phase Energy Sparks at Intersection Nodes
                for pt in crossFlares {
                    let flareSize: CGFloat = 2.0 + CGFloat(kickPunch * 1.5)
                    let flareRect = CGRect(x: pt.x - flareSize / 2, y: pt.y - flareSize / 2, width: flareSize, height: flareSize)
                    context.fill(Path(ellipseIn: flareRect), with: .color(Color.white.opacity(0.85 + kickPunch * 0.15)))
                }

                // 7. Glowing Playhead Needle with Beat Expansion
                if playheadY > 0 && playheadY < h {
                    let needleH: CGFloat = 2.0 + CGFloat(kickPunch * 1.2)
                    let needleW: CGFloat = w - 1.0
                    let needleRect = CGRect(x: (w - needleW) / 2.0, y: playheadY - (needleH / 2.0), width: needleW, height: needleH)
                    context.fill(Path(roundedRect: needleRect, cornerRadius: needleH / 2), with: .color(.white))
                }
            }
            .frame(width: barW, height: totalH)
            .clipShape(Capsule())
        }
        .frame(width: barW, height: totalH)
    }
}
