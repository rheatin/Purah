// Tools/RenderVideoShotcraftCuts.swift
import SwiftUI
import AppKit
import Foundation

// MARK: - Easing & Splines from video-shotcraft
struct Motion {
    static func easeOutCubic(_ t: Double) -> Double {
        let f = t - 1.0
        return f * f * f + 1.0
    }
    
    static func easeInCubic(_ t: Double) -> Double {
        t * t * t
    }
    
    static func spring(_ t: Double, damping: Double = 12, stiffness: Double = 110) -> Double {
        guard t > 0 else { return 0 }
        guard t < 1 else { return 1 }
        let c4 = (2.0 * Double.pi) / 3.0
        return pow(2, -10 * t) * sin((t * 10 - 0.75) * c4) + 1.0
    }
}

// MARK: - Cut 1: Stroke-Segment-Build + Brand-Frame-Snap (0.0s - 4.5s, 135 frames @ 30fps)
struct Cut1StrokeSegmentBuild: View {
    let frame: Int
    let totalFrames: Int = 135
    
    var body: some View {
        let t = Double(frame)
        let settleFrame = 85.0
        let isSettled = t >= settleFrame
        let settlePulse = isSettled ? max(1.0 + (1.0 - min((t - settleFrame) / 12.0, 1.0)) * 0.08, 1.0) : 1.0
        let frameThickness = min(t / 24.0, 1.0) * 16.0
        
        ZStack {
            Color(red: 0.04, green: 0.05, blue: 0.08)
            
            // 1. brand-frame-snap: 4 perimeter border bands growing around display edges
            VStack {
                Rectangle().fill(Color(hex: "#FF5A60")).frame(height: frameThickness)
                Spacer()
                Rectangle().fill(Color(hex: "#00F5D4")).frame(height: frameThickness)
            }
            HStack {
                Rectangle().fill(Color(hex: "#00E5A3")).frame(width: frameThickness)
                Spacer()
                Rectangle().fill(Color(hex: "#38BDF8")).frame(width: frameThickness)
            }
            
            // Ambient Radial Center Glow
            RadialGradient(
                colors: [Color.cyan.opacity(0.18), Color.clear],
                center: .center,
                startRadius: 20,
                endRadius: 600
            )
            
            // 2. stroke-segment-build: PURAH letters assembled from discrete glowing strokes
            VStack(spacing: 20) {
                HStack(spacing: 16) {
                    letterP(t: t)
                    letterU(t: t)
                    letterR(t: t)
                    letterA(t: t)
                    letterH(t: t)
                }
                .scaleEffect(settlePulse)
                
                if isSettled {
                    Text("The Edge of Your Display.")
                        .font(.system(size: 26, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(min((t - settleFrame) / 20.0, 0.85)))
                        .offset(y: (1.0 - min((t - settleFrame) / 20.0, 1.0)) * 14)
                }
            }
        }
        .frame(width: 1920, height: 1080)
    }
    
    // Segmented Strokes for P-U-R-A-H
    func strokeSegment(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, color: String, delay: Double, t: Double) -> some View {
        let active = t >= delay
        let p = active ? Motion.easeOutCubic(min((t - delay) / 8.0, 1.0)) : 0.0
        return RoundedRectangle(cornerRadius: min(w, h) / 2)
            .fill(Color(hex: color))
            .frame(width: w, height: h)
            .opacity(p)
            .shadow(color: Color(hex: color).opacity(0.6 * p), radius: 8)
            .offset(x: x, y: y + (1.0 - p) * 12)
    }
    
    func letterP(t: Double) -> some View {
        ZStack {
            strokeSegment(x: -20, y: 0, w: 12, h: 90, color: "#FF5A60", delay: 10, t: t)
            strokeSegment(x: 10, y: -36, w: 50, h: 12, color: "#FF5A60", delay: 28, t: t)
            strokeSegment(x: 35, y: -18, w: 12, h: 36, color: "#FF5A60", delay: 45, t: t)
            strokeSegment(x: 10, y: 0, w: 50, h: 12, color: "#FF5A60", delay: 82, t: t) // Key stroke
        }
        .frame(width: 80, height: 90)
    }
    
    func letterU(t: Double) -> some View {
        ZStack {
            strokeSegment(x: -25, y: -10, w: 12, h: 70, color: "#00E5A3", delay: 18, t: t)
            strokeSegment(x: 0, y: 35, w: 55, h: 12, color: "#00E5A3", delay: 84, t: t) // Key stroke
            strokeSegment(x: 25, y: -10, w: 12, h: 70, color: "#00E5A3", delay: 35, t: t)
        }
        .frame(width: 80, height: 90)
    }
    
    func letterR(t: Double) -> some View {
        ZStack {
            strokeSegment(x: -20, y: 0, w: 12, h: 90, color: "#38BDF8", delay: 12, t: t)
            strokeSegment(x: 10, y: -36, w: 48, h: 12, color: "#38BDF8", delay: 40, t: t)
            strokeSegment(x: 34, y: -20, w: 12, h: 32, color: "#38BDF8", delay: 52, t: t)
            strokeSegment(x: 10, y: -4, w: 48, h: 12, color: "#38BDF8", delay: 70, t: t)
            strokeSegment(x: 22, y: 26, w: 14, h: 42, color: "#38BDF8", delay: 85, t: t) // Key stroke
        }
        .frame(width: 80, height: 90)
    }
    
    func letterA(t: Double) -> some View {
        ZStack {
            strokeSegment(x: -20, y: 0, w: 12, h: 90, color: "#F59E0B", delay: 22, t: t)
            strokeSegment(x: 0, y: -38, w: 48, h: 12, color: "#F59E0B", delay: 32, t: t)
            strokeSegment(x: 20, y: 0, w: 12, h: 90, color: "#F59E0B", delay: 58, t: t)
            strokeSegment(x: 0, y: 4, w: 42, h: 12, color: "#F59E0B", delay: 83, t: t) // Key stroke
        }
        .frame(width: 80, height: 90)
    }
    
    func letterH(t: Double) -> some View {
        ZStack {
            strokeSegment(x: -24, y: 0, w: 12, h: 90, color: "#00F5D4", delay: 15, t: t)
            strokeSegment(x: 24, y: 0, w: 12, h: 90, color: "#00F5D4", delay: 48, t: t)
            strokeSegment(x: 0, y: 0, w: 46, h: 12, color: "#00F5D4", delay: 85, t: t) // Key stroke
        }
        .frame(width: 80, height: 90)
    }
}

// MARK: - Cut 4: Pill-Slot-Cycle (15.5s - 21.0s, 165 frames @ 30fps)
struct Cut4PillSlotCycle: View {
    let frame: Int
    let totalFrames: Int = 165
    
    let words = [
        ("Terminal", "#00F5D4", "apple.terminal.fill"),
        ("Calendar", "#FF5A60", "calendar"),
        ("Audio", "#38BDF8", "waveform"),
        ("Hardware", "#00E5A3", "waveform.path.ecg"),
        ("Tasks", "#F59E0B", "checklist")
    ]
    
    var body: some View {
        let t = Double(frame)
        let beatDur = 26.0 // frames per beat
        let activeIdx = min(Int(t / beatDur), words.count - 1)
        let beatPhase = (t - Double(activeIdx) * beatDur) / beatDur
        let current = words[activeIdx]
        
        let isFinalLock = t >= (Double(words.count - 1) * beatDur + 18.0)
        
        ZStack {
            Color(red: 0.05, green: 0.06, blue: 0.09)
            
            // Horizon ambient mesh
            RadialGradient(
                colors: [Color(hex: current.1).opacity(0.16), Color.clear],
                center: .center,
                startRadius: 10,
                endRadius: 550
            )
            
            VStack(spacing: 24) {
                HStack(spacing: 16) {
                    Text("Purah puts your")
                        .font(.system(size: 68, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    // The Slot Machine Pill
                    HStack(spacing: 12) {
                        Image(systemName: current.2)
                            .font(.system(size: 38, weight: .bold))
                            .foregroundColor(Color(hex: current.1))
                        
                        Text(current.0)
                            .font(.system(size: 52, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                    .background(
                        Capsule()
                            .fill(Color(hex: current.1).opacity(0.18))
                            .overlay(Capsule().stroke(Color(hex: current.1).opacity(0.85), lineWidth: 2))
                            .shadow(color: Color(hex: current.1).opacity(0.4), radius: 16)
                    )
                    .offset(y: (1.0 - Motion.easeOutCubic(min(beatPhase * 2.2, 1.0))) * 60)
                    .opacity(Motion.easeOutCubic(min(beatPhase * 2.5, 1.0)))
                }
                
                Text(isFinalLock ? "within a single flick." : "at the physical edge of your screen.")
                    .font(.system(size: 34, weight: .medium, design: .rounded))
                    .foregroundColor(isFinalLock ? Color(hex: "#00F5D4") : .gray.opacity(0.8))
                    .animation(.easeInOut(duration: 0.3), value: isFinalLock)
            }
        }
        .frame(width: 1920, height: 1080)
    }
}

// MARK: - Cut 6: UI-to-Brand-Morph / Icon-Flip-Bloom (25.5s - 30.0s, 135 frames @ 30fps)
struct Cut6IconFlipBloom: View {
    let frame: Int
    let totalFrames: Int = 135
    
    var body: some View {
        let t = Double(frame)
        let flipEnd = 38.0
        let isFlipped = t >= flipEnd
        let bloomP = isFlipped ? Motion.spring(min((t - flipEnd) / 25.0, 1.0)) : 0.0
        
        ZStack {
            Color(red: 0.03, green: 0.04, blue: 0.07)
            
            // Bloom radial background
            RadialGradient(
                colors: [Color(hex: "#00E5A3").opacity(0.20 * bloomP), Color.clear],
                center: .center,
                startRadius: 20,
                endRadius: 650
            )
            
            VStack(spacing: 32) {
                // The Brand App Icon Blooming
                ZStack {
                    if !isFlipped {
                        // Pre-flip: Status bar two-dot icon
                        HStack(spacing: 6) {
                            Circle().fill(Color(hex: "#00F5D4")).frame(width: 14, height: 14)
                            Circle().fill(Color(hex: "#00E5A3")).frame(width: 14, height: 14)
                        }
                        .scaleEffect(x: max(1.0 - (t / flipEnd), 0.04), y: 1.0)
                    } else {
                        // Post-flip: Official Purah App Icon blooming out
                        Image(nsImage: NSImage(contentsOfFile: "assets/Purah-icon-macOS-1024.png") ?? NSImage())
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 180, height: 180)
                            .scaleEffect(bloomP)
                            .shadow(color: Color(hex: "#00E5A3").opacity(0.4 * bloomP), radius: 28)
                    }
                }
                .frame(height: 180)
                
                if isFlipped {
                    VStack(spacing: 12) {
                        Text("Purah")
                            .font(.system(size: 64, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                            .opacity(min((t - flipEnd) / 15.0, 1.0))
                        
                        Text("macOS Magnetic Edge Rails · Ambient Ergonomic Kernel")
                            .font(.system(size: 24, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.7))
                        
                        HStack(spacing: 8) {
                            Image(systemName: "link")
                                .font(.system(size: 16))
                            Text("github.com/rheatin/Purah")
                                .font(.system(size: 20, weight: .bold, design: .monospaced))
                        }
                        .foregroundColor(Color(hex: "#00F5D4"))
                        .padding(.top, 8)
                        .opacity(min((t - flipEnd - 12.0) / 18.0, 1.0))
                    }
                }
            }
        }
        .frame(width: 1920, height: 1080)
    }
}

// MARK: - Color Hex Extension
extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted))
        var hexNumber: UInt64 = 0
        if scanner.scanHexInt64(&hexNumber) {
            let r = Double((hexNumber & 0xff0000) >> 16) / 255
            let g = Double((hexNumber & 0x00ff00) >> 8) / 255
            let b = Double(hexNumber & 0x0000ff) / 255
            self.init(red: r, green: g, blue: b)
            return
        }
        self.init(.white)
    }
}

// MARK: - Main Runner
@main
struct RenderShotcraftMain {
    @MainActor
    static func main() {
        let cutsDir = URL(fileURLWithPath: "/tmp/video_shotcraft_frames")
        try? FileManager.default.removeItem(at: cutsDir)
        try? FileManager.default.createDirectory(at: cutsDir, withIntermediateDirectories: true)
        
        // 1. Render Cut 1 (135 frames @ 30fps)
        print("🎬 [1/3] Rendering Cut 1: Stroke-Segment-Build (135 frames)...")
        renderScene(frameCount: 135, prefix: "cut1") { Cut1StrokeSegmentBuild(frame: $0) }
        
        // 2. Render Cut 4 (165 frames @ 30fps)
        print("🎬 [2/3] Rendering Cut 4: Pill-Slot-Cycle (165 frames)...")
        renderScene(frameCount: 165, prefix: "cut4") { Cut4PillSlotCycle(frame: $0) }
        
        // 3. Render Cut 6 (135 frames @ 30fps)
        print("🎬 [3/3] Rendering Cut 6: UI-to-Brand-Morph / Icon-Flip-Bloom (135 frames)...")
        renderScene(frameCount: 135, prefix: "cut6") { Cut6IconFlipBloom(frame: $0) }
        
        print("✅ Finished rendering all typographic & brand scene frames!")
    }
    
    @MainActor
    static func renderScene<V: View>(frameCount: Int, prefix: String, viewBuilder: (Int) -> V) {
        let outDir = URL(fileURLWithPath: "/tmp/video_shotcraft_frames/\(prefix)")
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        
        for f in 0..<frameCount {
            let view = viewBuilder(f)
            let hosting = NSHostingView(rootView: view)
            hosting.frame = NSRect(x: 0, y: 0, width: 1920, height: 1080)
            hosting.layoutSubtreeIfNeeded()
            
            if let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
                hosting.cacheDisplay(in: hosting.bounds, to: rep)
                if let png = rep.representation(using: .png, properties: [:]) {
                    let file = outDir.appendingPathComponent(String(format: "frame_%04d.png", f))
                    try? png.write(to: file)
                }
            }
        }
    }
}
