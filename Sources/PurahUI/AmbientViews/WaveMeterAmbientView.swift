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

        Group {
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
                case .auroraWave:
                    auroraWaveView(totalH: totalH, barW: barW)
                }
            }
        }
        .onAppear {
            if style == .dynamicWaveform {
                SystemAudioLiveMonitor.shared.start()
            }
        }
        .onChange(of: style) { _, newStyle in
            if newStyle == .dynamicWaveform {
                SystemAudioLiveMonitor.shared.start()
            }
        }
    }

    // MARK: - Common Time-Anchor Progress Calculation
    private func currentContinuousProgress(at date: Date) -> Double {
        let elapsed = isPlaying ? max(date.timeIntervalSince(track.lastUpdated), 0.0) : 0.0
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
                let continuousProgress = currentContinuousProgress(at: timeline.date)
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

    // MARK: - Sub-Style 1: Cyberpunk Neon VU Tower (Real-time Low-pass Filter & Transient Beat Punch)
    private func neonVUTowerView(totalH: CGFloat, barW: CGFloat) -> some View {
        let shouldAnimate = isAnimated && !reduceMotion

        return TimelineView(.animation(paused: !shouldAnimate)) { timeline in
            Canvas { context, size in
                let w = size.width
                let h = size.height
                let stepH: CGFloat = 8.0
                let gap: CGFloat = 3.0
                let count = max(Int((h - 4.0) / (stepH + gap)), 8)
                let time = shouldAnimate ? timeline.date.timeIntervalSinceReferenceDate : 0.0
                let continuousProgress = currentContinuousProgress(at: timeline.date)
                let playheadY = CGFloat(continuousProgress) * h

                // Dark glass track
                context.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: w, height: h), cornerRadius: w / 2), with: .color(Color.white.opacity(0.06)))

                // Live CoreAudio soundcard stream telemetry
                let livePeak = Double(SystemAudioLiveMonitor.shared.currentLevel)
                let liveBass = Double(SystemAudioLiveMonitor.shared.currentBass)
                let liveBeat = Double(SystemAudioLiveMonitor.shared.currentBeat)

                // Pure soundcard audio energy: active whenever physical sound is playing
                let hasLiveAudio = (livePeak > 0.003 || liveBass > 0.003)

                let activeBlocks: Int
                if hasLiveAudio {
                    // 1. Hardware live audio is available: 100% real acoustic soundcard drive
                    let baseLevel = max(livePeak * 0.45, liveBass * 0.55)
                    let kickPunch = liveBeat * 0.50
                    let combined = baseLevel + kickPunch
                    let activeRatio = min(max(combined, 0.08), 1.0)
                    activeBlocks = Int(round(Double(count) * activeRatio))
                } else if isPlaying {
                    // 2. Music is playing, but hardware audio tap is silent or buffering:
                    // Silky organic 120 BPM rhythmic bounce
                    let beatPeriod = 0.50
                    let beatPhase = (time.truncatingRemainder(dividingBy: beatPeriod) / beatPeriod)
                    let kick = exp(-beatPhase * 4.5)
                    let groove = sin(time * 2.4) * 0.12 + 0.32
                    let activeRatio = min(max(groove + (kick * 0.38), 0.12), 0.90)
                    activeBlocks = Int(round(Double(count) * activeRatio))
                } else {
                    // 3. Silent pause / stopped / no audio: completely dormant
                    activeBlocks = 0
                }

                for i in 0..<count {
                    let idxFromBottom = count - 1 - i
                    let y = CGFloat(idxFromBottom) * (stepH + gap) + 2.0
                    let isLit = i < activeBlocks
                    let isTopActiveBlock = (i == activeBlocks - 1) && (activeBlocks > 1)

                    let ratio = Double(i) / Double(count)
                    // High-energy Chroma ladder:
                    // Low Bass: Deep Crimson (#FF0055)
                    // Mid Range: Luminous Electric Pink (#FF375F)
                    // High Energy: Warm Amber Gold (#FF9F0A)
                    // Kick Overdrive Peak: Cyber Cyan (#00F5D4)
                    let litColor: Color = {
                        if ratio < 0.35 { return Color(hex: "#FF0055") }
                        else if ratio < 0.70 { return Color(hex: "#FF375F") }
                        else if ratio < 0.88 { return Color(hex: "#FF9F0A") }
                        else { return Color(hex: "#00F5D4") }
                    }()

                    let blockW: CGFloat = w - (isLit ? (isTopActiveBlock ? 0.4 : 0.8) : 1.6)
                    let blockX = (w - blockW) / 2.0
                    let r = CGRect(x: blockX, y: y, width: blockW, height: stepH)
                    let col = isLit ? (isTopActiveBlock ? Color.white : litColor) : litColor.opacity(0.16)
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

    // MARK: - Sub-Style 2: Aurora Wave Ribbon (Breathing Acoustic Ribbon)
    private func auroraWaveView(totalH: CGFloat, barW: CGFloat) -> some View {
        let shouldAnimate = isAnimated && !reduceMotion

        return TimelineView(.animation(paused: !shouldAnimate)) { timeline in
            Canvas { context, size in
                let w = size.width
                let h = size.height
                let centerX = w / 2.0
                let time = shouldAnimate ? timeline.date.timeIntervalSinceReferenceDate : 0.0
                let continuousProgress = currentContinuousProgress(at: timeline.date)
                let playheadY = CGFloat(continuousProgress) * h

                // Track
                context.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: w, height: h), cornerRadius: w / 2), with: .color(musicColor.opacity(0.12)))

                // Live volume dynamics directly expands ribbon
                let livePeak = Double(SystemAudioLiveMonitor.shared.currentLevel)
                let hasLiveAudio = (livePeak > 0.003) || isPlaying
                let dynamicSpread = hasLiveAudio ? (1.0 + CGFloat(livePeak) * 1.5) : 1.0

                let steps = 40
                let dy = h / CGFloat(steps)

                var path = Path()
                var leftPoints: [CGPoint] = []
                var rightPoints: [CGPoint] = []

                for i in 0...steps {
                    let y = CGFloat(i) * dy
                    let ny = Double(y / h)
                    let wave = hasLiveAudio
                        ? (sin(ny * 8.0 - time * 5.0) * 0.5 + cos(ny * 16.0 + time * 3.2) * 0.3 + 0.8)
                        : (sin(ny * 7.0) * 0.25 + 0.5)
                    let halfW = min(max(CGFloat(wave) * 1.8 * dynamicSpread, 1.2), w / 2.0 - 0.5)
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
