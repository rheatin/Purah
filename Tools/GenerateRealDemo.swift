// Tools/GenerateRealDemo.swift
import SwiftUI
import AppKit
import Foundation
import PurahCore
import PurahUI

// MARK: - Mathematical Splines & Easing
struct Spline {
    static func easeInOut(_ t: Double) -> Double {
        t < 0.5 ? 4.0 * t * t * t : 1.0 - pow(-2.0 * t + 2.0, 3.0) / 2.0
    }
    
    static func spring(_ t: Double) -> Double {
        let c4 = (2.0 * Double.pi) / 3.0
        return t == 0 ? 0 : t == 1 ? 1 : pow(2, -10 * t) * sin((t * 10 - 0.75) * c4) + 1.0
    }
}

// MARK: - Master Real Canvas View
struct RealPurahDemoCanvas: View {
    let store: PurahWorkspaceStore
    let cursorPoint: CGPoint
    let isClicking: Bool
    let clickProgress: Double
    let hudText: String?
    let width: CGFloat = 960
    let height: CGFloat = 540

    var body: some View {
        ZStack(alignment: .topLeading) {
            // 1. Pristine macOS Sonoma Dark Wallpaper
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.10, blue: 0.16),
                    Color(red: 0.04, green: 0.05, blue: 0.09)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // Subtle Radial Ambient Horizon
            RadialGradient(
                colors: [
                    Color(red: 0.12, green: 0.20, blue: 0.35).opacity(0.35),
                    Color.clear
                ],
                center: .center,
                startRadius: 20,
                endRadius: 500
            )

            // 2. Realistic Centered Coding Editor Backdrop (Zero private data)
            centeredWorkstationBackdrop
                .position(x: width / 2.0, y: height / 2.0 + 8)

            // 3. Top macOS Native Menu Bar
            menuBar
                .frame(width: width, height: 24)
                .position(x: width / 2.0, y: 12)

            // 4. REAL Purah Left & Right Rails
            if !store.isRailsFrozen {
                // Real Left Rail
                AmbientRailStripView(edge: .left, store: store)
                    .frame(width: 380, height: height - 24)
                    .position(x: 190, y: (height + 24) / 2.0)

                // Real Right Rail
                AmbientRailStripView(edge: .right, store: store)
                    .frame(width: 380, height: height - 24)
                    .position(x: width - 190, y: (height + 24) / 2.0)
            }

            // 5. Real Option-Tab HUD Capsule
            if let hud = hudText {
                HStack(spacing: 8) {
                    Text(hud)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.85))
                        .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1))
                        .shadow(color: Color.black.opacity(0.4), radius: 16, y: 4)
                )
                .position(x: width / 2.0, y: height - 60)
            }

            // 6. Click Ripple Indicator
            if isClicking {
                Circle()
                    .stroke(Color.white.opacity(1.0 - clickProgress), lineWidth: 2.0)
                    .frame(width: 8 + clickProgress * 32, height: 8 + clickProgress * 32)
                    .position(cursorPoint)
            }

            // 7. Pixel-Accurate Native macOS Cursor
            cursorArrow
                .position(x: cursorPoint.x + 8, y: cursorPoint.y + 11)
        }
        .frame(width: width, height: height)
        .clipped()
    }

    var menuBar: some View {
        HStack(spacing: 14) {
            Image(systemName: "applelogo")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white.opacity(0.9))
            Text("Purah").font(.system(size: 11, weight: .bold)).foregroundColor(.white)
            Text("File").font(.system(size: 11)).foregroundColor(.white.opacity(0.7))
            Text("Edit").font(.system(size: 11)).foregroundColor(.white.opacity(0.7))
            Text("View").font(.system(size: 11)).foregroundColor(.white.opacity(0.7))
            Text("Plugins").font(.system(size: 11)).foregroundColor(.white.opacity(0.7))
            Spacer()
            Image(systemName: "circle.grid.2x1.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Color(red: 0.0, green: 0.95, blue: 0.8))
            Image(systemName: "wifi").font(.system(size: 10)).foregroundColor(.white.opacity(0.8))
            Image(systemName: "battery.100").font(.system(size: 11)).foregroundColor(.white.opacity(0.8))
            Text("Thu 10:24 AM").font(.system(size: 10, weight: .medium)).foregroundColor(.white.opacity(0.85))
        }
        .padding(.horizontal, 14)
        .background(Color(white: 0.08).opacity(0.92))
        .overlay(Rectangle().frame(height: 0.5).foregroundColor(Color.white.opacity(0.12)), alignment: .bottom)
    }

    var centeredWorkstationBackdrop: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Circle().fill(Color.red.opacity(0.8)).frame(width: 9, height: 9)
                Circle().fill(Color.yellow.opacity(0.8)).frame(width: 9, height: 9)
                Circle().fill(Color.green.opacity(0.8)).frame(width: 9, height: 9)
                Spacer()
                Text("PurahKernel.swift — Project Purah")
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundColor(.gray.opacity(0.7))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(white: 0.12))

            VStack(alignment: .leading, spacing: 4.5) {
                codeLine(num: "1", kw: "import", txt: " SwiftUI", col: "#FF7B72")
                codeLine(num: "2", kw: "import", txt: " PurahCore", col: "#79C0FF")
                codeLine(num: "3", kw: "import", txt: " PurahUI", col: "#79C0FF")
                codeLine(num: "4", kw: "//", txt: " Zero-Block Click-Through Architecture", col: "#8B949E")
                codeLine(num: "5", kw: "@main", txt: " struct PurahWorkspace: PurahKernel {", col: "#FFA657")
                codeLine(num: "6", kw: "    let", txt: " rails = MagneticEdgeRails(edge: .both)", col: "#7EE787")
                codeLine(num: "7", kw: "    let", txt: " physics = BezelExtrusionEngine()", col: "#7EE787")
                codeLine(num: "8", kw: "}", txt: "", col: "#E6EDF3")
            }
            .padding(12)
            Spacer()
        }
        .frame(width: 440, height: 260)
        .background(Color(red: 0.06, green: 0.08, blue: 0.12).opacity(0.90))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.12), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.4), radius: 20, y: 10)
    }

    func codeLine(num: String, kw: String, txt: String, col: String) -> some View {
        HStack(spacing: 8) {
            Text(num).foregroundColor(.gray.opacity(0.4)).frame(width: 14, alignment: .trailing)
            Text(kw).foregroundColor(Color(hex: col)).bold()
            Text(txt).foregroundColor(.white)
        }
        .font(.system(size: 10.5, design: .monospaced))
    }

    var cursorArrow: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 0, y: 15))
            path.addLine(to: CGPoint(x: 4.0, y: 11.5))
            path.addLine(to: CGPoint(x: 7.5, y: 18.5))
            path.addLine(to: CGPoint(x: 9.8, y: 17.3))
            path.addLine(to: CGPoint(x: 6.3, y: 10.5))
            path.addLine(to: CGPoint(x: 11.5, y: 10.5))
            path.closeSubpath()
        }
        .fill(Color.white)
        .overlay(
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 0, y: 15))
                path.addLine(to: CGPoint(x: 4.0, y: 11.5))
                path.addLine(to: CGPoint(x: 7.5, y: 18.5))
                path.addLine(to: CGPoint(x: 9.8, y: 17.3))
                path.addLine(to: CGPoint(x: 6.3, y: 10.5))
                path.addLine(to: CGPoint(x: 11.5, y: 10.5))
                path.closeSubpath()
            }
            .stroke(Color.black, lineWidth: 1.1)
        )
        .shadow(color: Color.black.opacity(0.4), radius: 3, x: 1, y: 2)
        .frame(width: 13, height: 19)
    }
}

// MARK: - Color Extension Helper
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

// MARK: - Main Renderer
@main
struct RealDemoRendererMain {
    @MainActor
    static func main() {
        let frameCount = 300 // 12.0 seconds at 25 fps
        let framesDir = URL(fileURLWithPath: "/tmp/purah_real_frames")
        try? FileManager.default.removeItem(at: framesDir)
        try? FileManager.default.createDirectory(at: framesDir, withIntermediateDirectories: true)

        let store = PurahWorkspaceStore()
        PluginRegistry.shared.bindStore(store)

        // Seed mock music track so it shows genuine artwork and waveform
        store.musicTrack.title = "Down in Sandbar"
        store.musicTrack.artist = "Lala Hsu"
        store.musicTrack.isPlaying = true
        store.musicTrack.durationSeconds = 248
        store.musicTrack.currentPositionSeconds = 88
        store.musicTrack.sourceApp = "Apple Music"

        print("🎬 Rendering \(frameCount) pixel-perfect frames of REAL Purah UI...")
        let startTime = Date()

        for frame in 0..<frameCount {
            let t = Double(frame)
            var cursorX: Double = 500
            var cursorY: Double = 300
            var isClick: Bool = false
            var clickP: Double = 0.0
            var hud: String? = nil

            // State Choreography
            if t < 35 {
                // Scene 1: Resting in center, starting move right
                store.activeDrawerPodId = nil
                store.activeDrawerItemId = nil
                let p = Spline.easeInOut(min(max((t - 10) / 25.0, 0.0), 1.0))
                cursorX = 500 + p * 455
                cursorY = 300 + p * 180
            } else if t < 95 {
                // Scene 2: Right edge touches Music drawer -> slides out
                store.activeDrawerPodId = "music"
                store.activeDrawerItemId = "music"

                if t >= 65 && t <= 75 {
                    isClick = true
                    clickP = (t - 65) / 10.0
                    store.pinnedDrawerItemIds.insert("music")
                }

                let p = Spline.easeInOut(min(max((t - 35) / 20.0, 0.0), 1.0))
                cursorX = 955 - p * 80
                cursorY = 480 - p * 30
            } else if t < 155 {
                // Scene 3: Moves up to Calendar
                store.activeDrawerPodId = "calendar"
                store.activeDrawerItemId = store.calendarEvents.first?.id

                let p = Spline.easeInOut(min(max((t - 95) / 25.0, 0.0), 1.0))
                cursorX = 875 + p * 60
                cursorY = 450 - p * 250
            } else if t < 225 {
                // Scene 4: Swoops to Left Rail -> Hardware Vitals
                store.activeDrawerPodId = "vitals"
                store.activeDrawerItemId = "vitals"

                let p = Spline.easeInOut(min(max((t - 155) / 30.0, 0.0), 1.0))
                cursorX = 935 - p * 925
                cursorY = 200 + p * 120
            } else if t < 265 {
                // Scene 5: Moves towards center
                let p = Spline.easeInOut(min(max((t - 225) / 25.0, 0.0), 1.0))
                cursorX = 10 + p * 470
                cursorY = 320 + p * 80
            } else if t < 285 {
                // Scene 6: Option+Tab Freeze Mode
                store.isRailsFrozen = true
                hud = "❄️ Rails Frozen (⌥⇥ to restore)"
                cursorX = 480
                cursorY = 400
            } else {
                // Scene 7: Option+Tab Unfreeze Restore
                store.isRailsFrozen = false
                hud = "✨ Rails Active"
                cursorX = 480
                cursorY = 400
            }

            // Real Canvas Rendering
            let canvas = RealPurahDemoCanvas(
                store: store,
                cursorPoint: CGPoint(x: cursorX, y: cursorY),
                isClicking: isClick,
                clickProgress: clickP,
                hudText: hud
            )

            let hosting = NSHostingView(rootView: canvas)
            hosting.frame = NSRect(x: 0, y: 0, width: 960, height: 540)
            hosting.layoutSubtreeIfNeeded()

            if let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
                hosting.cacheDisplay(in: hosting.bounds, to: rep)
                if let png = rep.representation(using: .png, properties: [:]) {
                    let path = framesDir.appendingPathComponent(String(format: "frame_%04d.png", frame))
                    try? png.write(to: path)
                }
            }

            if (frame + 1) % 50 == 0 || frame == frameCount - 1 {
                print("   Rendered \(frame + 1)/\(frameCount) real frames...")
            }
        }

        let elapsed = Date().timeIntervalSince(startTime)
        print("✅ Finished rendering real frames in \(String(format: "%.2f", elapsed))s!")
    }
}
