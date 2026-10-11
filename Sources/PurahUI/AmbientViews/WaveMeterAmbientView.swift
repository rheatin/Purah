// Sources/PurahUI/AmbientViews/WaveMeterAmbientView.swift
import SwiftUI
import PurahCore

public struct WaveMeterAmbientView: View {
    public var style: MusicRailStyle
    public var subStyle: DynamicWaveformSubStyle
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
        subStyle: DynamicWaveformSubStyle = .neonVUTower,
        track: MusicTrackInfo = MusicTrackInfo(),
        progress: Double = 0.0,
        samples: [Double] = [],
        isPlaying: Bool,
        isAnimated: Bool = true,
        height: CGFloat = 80.0
    ) {
        self.style = style
        self.subStyle = subStyle
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
        self.init(style: .dynamicWaveform, subStyle: .neonVUTower, track: MusicTrackInfo(), progress: progress, samples: samples, isPlaying: isPlaying, isAnimated: isAnimated, height: height)
    }

    public init(samples: [Double], isPlaying: Bool, isAnimated: Bool = true, height: CGFloat = 80.0) {
        self.init(style: .dynamicWaveform, subStyle: .neonVUTower, track: MusicTrackInfo(), progress: 0.0, samples: samples, isPlaying: isPlaying, isAnimated: isAnimated, height: height)
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
            switch subStyle {
            case .neonVUTower:
                neonVUTowerView(totalH: totalH, barW: barW)
            case .moltenPlasma:
                moltenPlasmaView(totalH: totalH, barW: barW)
            case .appleSpringEQ:
                appleSpringEQView(totalH: totalH, barW: barW)
            case .auroraWave:
                auroraWaveView(totalH: totalH, barW: barW)
            }
        }
    }

    // MARK: - Common Time-Anchor Progress Calculation
    private func currentContinuousProgress(timeline: TimelineViewDefaultContext) -> Double {
        let elapsed = isPlaying ? max(timeline.date.timeIntervalSince(track.lastUpdated), 0.0) : 0.0
        let effectiveRate = track.playbackRate > 0 ? track.playbackRate : (isPlaying ? 1.0 : 0.0)
        let currentPos = track.currentPositionSeconds + (elapsed * effectiveRate)
        if track.durationSeconds > 0 {
            return min(max(currentPos / track.durationSeconds, 0.0), 1.0)
        } else {
            return min(max(progress, 0.0), 1.0)
        }
    }

    // MARK: - Mode 2: 60 FPS Silky Smooth Live Progress Bar
    private func smoothProgressView(totalH: CGFloat, barW: CGFloat) -> some View {
        TimelineView(.animation(paused: !isPlaying)) { timeline in
            Canvas { context, size in
                let w = size.width
                let h = size.height
                let centerX = w / 2.0
                let continuousProgress = currentContinuousProgress(timeline: timeline)
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

    // MARK: - Sub-Style 1: Cyberpunk Neon VU Tower (赛博霓虹电平塔)
    private func neonVUTowerView(totalH: CGFloat, barW: CGFloat) -> some View {
        let shouldAnimate = isPlaying && isAnimated && !reduceMotion

        return TimelineView(.animation(paused: !shouldAnimate)) { timeline in
            Canvas { context, size in
                let w = size.width
                let h = size.height
                let time = shouldAnimate ? timeline.date.timeIntervalSinceReferenceDate : 0.0
                let stepH: CGFloat = 8.0
                let gap: CGFloat = 3.0
                let count = max(Int((h - 4.0) / (stepH + gap)), 8)
                let continuousProgress = currentContinuousProgress(timeline: timeline)
                let playheadY = CGFloat(continuousProgress) * h

                // Dark glass track
                context.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: w, height: h), cornerRadius: w / 2), with: .color(Color.white.opacity(0.06)))

                // Beat physics calculation (125 BPM Kick Drum + Snare Pulse)
                let beatPeriod = 0.48
                let beatPhase = shouldAnimate ? (time.truncatingRemainder(dividingBy: beatPeriod) / beatPeriod) : 0.0
                let kickPunch = shouldAnimate ? exp(-beatPhase * 6.0) : 0.0
                let phraseTension = shouldAnimate ? (sin(time * 0.4) * 0.5 + 0.5) : 0.0
                let activeRatio = shouldAnimate ? min(max(0.35 + (kickPunch * 0.45) + (phraseTension * 0.20), 0.2), 1.0) : 0.25
                let activeBlocks = Int(Double(count) * activeRatio)

                for i in 0..<count {
                    let idxFromBottom = count - 1 - i
                    let y = CGFloat(idxFromBottom) * (stepH + gap) + 2.0
                    let isLit = i < activeBlocks

                    let ratio = Double(i) / Double(count)
                    // High-energy Chroma ladder: Crimson -> Electric Pink -> Amber Gold -> Cyber Cyan Peak
                    let litColor: Color = {
                        if ratio < 0.35 { return Color(hex: "#FF0055") }
                        else if ratio < 0.70 { return Color(hex: "#FF375F") }
                        else if ratio < 0.88 { return Color(hex: "#FF9F0A") }
                        else { return Color(hex: "#00F5D4") }
                    }()

                    let blockW: CGFloat = w - (isLit ? 0.8 : 1.6)
                    let blockX = (w - blockW) / 2.0
                    let r = CGRect(x: blockX, y: y, width: blockW, height: stepH)
                    let col = isLit ? litColor : litColor.opacity(0.18)
                    context.fill(Path(roundedRect: r, cornerRadius: 2.5), with: .color(col))
                }

                // Playhead needle
                if playheadY > 0 && playheadY < h {
                    let needleRect = CGRect(x: 0, y: playheadY - 1.0, width: w, height: 2.0)
                    context.fill(Path(roundedRect: needleRect, cornerRadius: 1), with: .color(.white))
                }
            }
            .frame(width: barW, height: totalH)
            .clipShape(Capsule())
        }
        .frame(width: barW, height: totalH)
    }

    // MARK: - Sub-Style 2: Molten Liquid Plasma Surge (熔融等离子光流)
    private func moltenPlasmaView(totalH: CGFloat, barW: CGFloat) -> some View {
        let shouldAnimate = isPlaying && isAnimated && !reduceMotion

        return TimelineView(.animation(paused: !shouldAnimate)) { timeline in
            Canvas { context, size in
                let w = size.width
                let h = size.height
                let centerX = w / 2.0
                let time = shouldAnimate ? timeline.date.timeIntervalSinceReferenceDate : 0.0
                let continuousProgress = currentContinuousProgress(timeline: timeline)
                let playheadY = CGFloat(continuousProgress) * h

                // Moving Multi-stop Spectral Gradient
                let offset = (time * 0.55).truncatingRemainder(dividingBy: 1.0)
                let p1 = CGPoint(x: centerX, y: -h * 0.5 + CGFloat(offset) * h)
                let p2 = CGPoint(x: centerX, y: h * 1.5 + CGFloat(offset) * h)

                let colors: [Color] = [
                    Color(hex: "#FF007A"),
                    Color(hex: "#7928CA"),
                    Color(hex: "#0070F3"),
                    Color(hex: "#00DFD8"),
                    Color(hex: "#FF007A")
                ]

                let rect = CGRect(x: 0, y: 0, width: w, height: h)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: w / 2),
                    with: .linearGradient(Gradient(colors: colors), startPoint: p1, endPoint: p2)
                )

                // Traveling pulse wave on beat kicks
                let pulsePeriod = 0.52
                let pulsePhase = shouldAnimate ? (time.truncatingRemainder(dividingBy: pulsePeriod) / pulsePeriod) : 0.0
                let pulseY = CGFloat(pulsePhase) * h
                let pulseRect = CGRect(x: 0, y: pulseY - 14.0, width: w, height: 28.0)
                context.fill(Path(ellipseIn: pulseRect), with: .color(Color.white.opacity(shouldAnimate ? 0.40 : 0.0)))

                // Playhead needle
                if playheadY > 0 && playheadY < h {
                    let needleRect = CGRect(x: 0, y: playheadY - 1.2, width: w, height: 2.4)
                    context.fill(Path(roundedRect: needleRect, cornerRadius: 1.2), with: .color(.white))
                }
            }
            .frame(width: barW, height: totalH)
            .clipShape(Capsule())
        }
        .frame(width: barW, height: totalH)
    }

    // MARK: - Sub-Style 3: Apple Spring EQ (苹果高弹跳动均衡柱)
    private func appleSpringEQView(totalH: CGFloat, barW: CGFloat) -> some View {
        let shouldAnimate = isPlaying && isAnimated && !reduceMotion

        return TimelineView(.animation(paused: !shouldAnimate)) { timeline in
            Canvas { context, size in
                let w = size.width
                let h = size.height
                let time = shouldAnimate ? timeline.date.timeIntervalSinceReferenceDate : 0.0
                let continuousProgress = currentContinuousProgress(timeline: timeline)
                let playheadY = CGFloat(continuousProgress) * h

                // Track background
                context.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: w, height: h), cornerRadius: w / 2), with: .color(musicColor.opacity(0.12)))

                // Played track background
                if playheadY > 1.0 {
                    context.fill(Path(roundedRect: CGRect(x: 0.5, y: 0, width: w - 1.0, height: playheadY), cornerRadius: (w - 1.0) / 2), with: .color(musicColor.opacity(0.28)))
                }

                // 3 Apple-style spring bouncing bars centered in the rail
                let centerY = h / 2.0
                let eqBarW: CGFloat = 1.5
                let eqGap: CGFloat = 1.2
                let totalEqW = eqBarW * 3.0 + eqGap * 2.0
                let startX = (w - totalEqW) / 2.0

                let phases = [0.0, 1.8, 3.2]
                let freqs = [6.2, 8.5, 5.0]
                let maxH: [CGFloat] = [48.0, 72.0, 42.0]

                for b in 0..<3 {
                    let e = shouldAnimate
                        ? ((sin(time * freqs[b] + phases[b]) * 0.65 + cos(time * 3.5 + phases[b] * 0.7) * 0.35 + 1.0) / 2.0)
                        : 0.15
                    let bH = 8.0 + CGFloat(e) * (maxH[b] - 8.0)
                    let bX = startX + CGFloat(b) * (eqBarW + eqGap)
                    let bY = centerY - (bH / 2.0)
                    let r = CGRect(x: bX, y: bY, width: eqBarW, height: bH)
                    context.fill(Path(roundedRect: r, cornerRadius: eqBarW / 2), with: .color(musicColor))
                }

                // Playhead needle
                if playheadY > 0 && playheadY < h {
                    let needleRect = CGRect(x: 0, y: playheadY - 1.0, width: w, height: 2.0)
                    context.fill(Path(roundedRect: needleRect, cornerRadius: 1), with: .color(.white))
                }
            }
            .frame(width: barW, height: totalH)
            .clipShape(Capsule())
        }
        .frame(width: barW, height: totalH)
    }

    // MARK: - Sub-Style 4: Aurora Wave Ribbon (极光呼吸声波带)
    private func auroraWaveView(totalH: CGFloat, barW: CGFloat) -> some View {
        let shouldAnimate = isPlaying && isAnimated && !reduceMotion

        return TimelineView(.animation(paused: !shouldAnimate)) { timeline in
            Canvas { context, size in
                let w = size.width
                let h = size.height
                let centerX = w / 2.0
                let time = shouldAnimate ? timeline.date.timeIntervalSinceReferenceDate : 0.0
                let continuousProgress = currentContinuousProgress(timeline: timeline)
                let playheadY = CGFloat(continuousProgress) * h

                // Track
                context.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: w, height: h), cornerRadius: w / 2), with: .color(musicColor.opacity(0.12)))

                // Smooth organic undulating ribbon without any harsh lines
                let steps = 40
                let dy = h / CGFloat(steps)

                var path = Path()
                var leftPoints: [CGPoint] = []
                var rightPoints: [CGPoint] = []

                for i in 0...steps {
                    let y = CGFloat(i) * dy
                    let ny = Double(y / h)
                    let wave = shouldAnimate
                        ? (sin(ny * 8.0 - time * 5.0) * 0.5 + cos(ny * 16.0 + time * 3.2) * 0.3 + 0.8)
                        : (sin(ny * 7.0) * 0.4 + 0.7)
                    let halfW = min(max(CGFloat(wave) * 2.2, 1.2), w / 2.0 - 0.5)
                    rightPoints.append(CGPoint(x: centerX + halfW, y: y))
                    leftPoints.append(CGPoint(x: centerX - halfW, y: y))
                }

                if let first = rightPoints.first {
                    path.move(to: first)
                    for pt in rightPoints.dropFirst() { path.addLine(to: pt) }
                    for pt in leftPoints.reversed() { path.addLine(to: pt) }
                    path.closeSubpath()
                }

                // Fill with glowing chromatic gradient
                context.fill(
                    path,
                    with: .linearGradient(
                        Gradient(colors: [Color(hex: "#FF007A"), Color(hex: "#FF4E50"), Color(hex: "#F9D423")]),
                        startPoint: CGPoint(x: centerX, y: 0),
                        endPoint: CGPoint(x: centerX, y: h)
                    )
                )

                // Playhead needle
                if playheadY > 0 && playheadY < h {
                    let needleRect = CGRect(x: 0, y: playheadY - 1.0, width: w, height: 2.0)
                    context.fill(Path(roundedRect: needleRect, cornerRadius: 1), with: .color(.white))
                }
            }
            .frame(width: barW, height: totalH)
            .clipShape(Capsule())
        }
        .frame(width: barW, height: totalH)
    }
}
