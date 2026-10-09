// Tools/DemoRecorder.swift
import SwiftUI
import AppKit
import Foundation

// MARK: - Mathematical Easing Functions
struct Ease {
    static func inOutQuad(_ t: Double) -> Double {
        t < 0.5 ? 2.0 * t * t : -1.0 + (4.0 - 2.0 * t) * t
    }
    
    static func outCubic(_ t: Double) -> Double {
        let f = t - 1.0
        return f * f * f + 1.0
    }
    
    static func outSpring(_ t: Double) -> Double {
        let c4 = (2.0 * Double.pi) / 3.0
        return t == 0 ? 0 : t == 1 ? 1 : pow(2, -10 * t) * sin((t * 10 - 0.75) * c4) + 1.0
    }
}

// MARK: - Simulated Cursor Position
struct CursorState {
    let x: Double
    let y: Double
    let isClicking: Bool
    let clickProgress: Double
}

// MARK: - Demo Stage Calculator
struct DemoTimeline {
    let totalFrames: Int = 300 // 12 seconds at 25 fps
    
    func cursor(for frame: Int) -> CursorState {
        let t = Double(frame)
        
        if t < 35 {
            // Scene 1: Rest in center, start gliding right
            let p = Ease.inOutQuad(min(max((t - 10) / 25.0, 0.0), 1.0))
            return CursorState(x: 520 + p * 410, y: 320 + p * 110, isClicking: false, clickProgress: 0)
        } else if t < 65 {
            // Scene 2: Touch right edge, trigger Music drawer, move to Play/Pause
            let p = Ease.outCubic(min(max((t - 35) / 25.0, 0.0), 1.0))
            let isClick = (t >= 55 && t <= 62)
            let clickP = isClick ? (t - 55) / 7.0 : 0.0
            return CursorState(x: 930 - p * 160, y: 430 - p * 30, isClicking: isClick, clickProgress: clickP)
        } else if t < 105 {
            // Scene 2b: Move to Pin button, click Pin
            let p = Ease.inOutQuad(min(max((t - 65) / 25.0, 0.0), 1.0))
            let isClick = (t >= 95 && t <= 102)
            let clickP = isClick ? (t - 95) / 7.0 : 0.0
            return CursorState(x: 770 + p * 140, y: 400 - p * 50, isClicking: isClick, clickProgress: clickP)
        } else if t < 145 {
            // Scene 3: Glide up to Calendar
            let p = Ease.inOutQuad(min(max((t - 105) / 28.0, 0.0), 1.0))
            return CursorState(x: 910 + p * 20, y: 350 - p * 200, isClicking: false, clickProgress: 0)
        } else if t < 185 {
            // Scene 3b: Hover Calendar Join, move across towards left
            let p = Ease.inOutQuad(min(max((t - 145) / 35.0, 0.0), 1.0))
            return CursorState(x: 930 - p * 400, y: 150 + p * 100, isClicking: false, clickProgress: 0)
        } else if t < 225 {
            // Scene 4: Swoop to Left Edge -> Terminal pops out
            let p = Ease.inOutQuad(min(max((t - 185) / 28.0, 0.0), 1.0))
            return CursorState(x: 530 - p * 515, y: 250 + p * 40, isClicking: false, clickProgress: 0)
        } else if t < 265 {
            // Scene 4b: Hover Terminal, typing commands, then move to center
            let p = Ease.inOutQuad(min(max((t - 240) / 22.0, 0.0), 1.0))
            return CursorState(x: 15 + p * 465, y: 290 + p * 60, isClicking: false, clickProgress: 0)
        } else {
            // Scene 5: Rest in center, Option-Tab Freeze trigger
            return CursorState(x: 480, y: 350, isClicking: false, clickProgress: 0)
        }
    }
}

// MARK: - SwiftUI Frame Composition View
struct DemoCanvasView: View {
    let frame: Int
    let totalFrames: Int = 300
    let timeline = DemoTimeline()
    
    var body: some View {
        let cursor = timeline.cursor(for: frame)
        let t = Double(frame)
        
        // Drawer states
        let musicActive = t >= 35 && t <= 270
        let musicProgress = musicActive ? Ease.outSpring(min((t - 35) / 20.0, 1.0)) : 0.0
        let isMusicPinned = t >= 98
        
        let calendarActive = t >= 115 && t <= 175
        let calendarProgress = calendarActive ? Ease.outSpring(min((t - 115) / 18.0, 1.0)) : 0.0
        
        let terminalActive = t >= 200 && t <= 270
        let terminalProgress = terminalActive ? Ease.outSpring(min((t - 200) / 22.0, 1.0)) : 0.0
        
        // Terminal typing animation
        let fullCmd = "purah status --health"
        let typeProgress = min(max((t - 215) / 25.0, 0.0), 1.0)
        let charCount = Int(typeProgress * Double(fullCmd.count))
        let typedCommand = String(fullCmd.prefix(charCount))
        let showTerminalOutput = t >= 242
        
        // Freeze Mode HUD
        let freezeActive = t >= 268 && t <= 298
        let isRestoring = t >= 288
        
        ZStack(alignment: .topLeading) {
            // 1. Wallpaper Background (Deep macOS Studio Space Gradient)
            LinearGradient(
                colors: [
                    Color(red: 0.07, green: 0.09, blue: 0.15),
                    Color(red: 0.03, green: 0.04, blue: 0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // Subtle Radial Ambient Glow
            RadialGradient(
                colors: [Color.cyan.opacity(0.08), Color.clear],
                center: .center,
                startRadius: 10,
                endRadius: 400
            )
            
            // 2. Realistic Code Editor Window Backdrop (Contextual Desktop)
            codeEditorBackdrop
                .position(x: 480, y: 285)
            
            // 3. Top macOS Menu Bar
            menuBarView
            
            // 4. Edge Rails (Left & Right 5pt flush ambient strips)
            if !freezeActive || isRestoring {
                leftRailBars
                rightRailBars
            }
            
            // 5. Active Drawers
            // Left Drawer: SwiftTerm Terminal
            if terminalProgress > 0 && (!freezeActive || isRestoring) {
                terminalDrawerView(typedCommand: typedCommand, showOutput: showTerminalOutput)
                    .offset(x: -360 * (1.0 - terminalProgress))
                    .position(x: 180, y: 285)
            }
            
            // Right Drawer: Calendar
            if calendarProgress > 0 && (!freezeActive || isRestoring) {
                calendarDrawerView
                    .offset(x: 290 * (1.0 - calendarProgress))
                    .position(x: 960 - 145, y: 155)
            }
            
            // Right Drawer: Music Waveform
            if musicProgress > 0 && (!freezeActive || isRestoring) {
                musicDrawerView(frame: frame, isPinned: isMusicPinned)
                    .offset(x: 280 * (1.0 - musicProgress))
                    .position(x: 960 - 140, y: 425)
            }
            
            // 6. Option-Tab (`⌥⇥`) Freeze Mode HUD
            if freezeActive {
                hudCapsuleView(isRestoring: isRestoring)
                    .position(x: 480, y: 460)
            }
            
            // 7. Click Ripple Feedback
            if cursor.isClicking {
                Circle()
                    .stroke(Color.white.opacity(1.0 - cursor.clickProgress), lineWidth: 2.0)
                    .frame(width: 8 + cursor.clickProgress * 30, height: 8 + cursor.clickProgress * 30)
                    .position(x: cursor.x, y: cursor.y)
            }
            
            // 8. Pixel-Accurate macOS Arrow Pointer Cursor
            cursorView
                .position(x: cursor.x + 8, y: cursor.y + 11)
        }
        .frame(width: 960, height: 540)
        .clipped()
    }
    
    // MARK: - Code Editor Backdrop
    var codeEditorBackdrop: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Window Header
            HStack(spacing: 7) {
                Circle().fill(Color.red.opacity(0.8)).frame(width: 10, height: 10)
                Circle().fill(Color.yellow.opacity(0.8)).frame(width: 10, height: 10)
                Circle().fill(Color.green.opacity(0.8)).frame(width: 10, height: 10)
                Spacer()
                Text("AppKernel.swift — Purah Workspace")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.gray.opacity(0.7))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(white: 0.12))
            
            // Code lines
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text("1").foregroundColor(.gray.opacity(0.4))
                    Text("import").foregroundColor(Color(hex: "#FF7B72")).bold()
                    Text("SwiftUI").foregroundColor(.white)
                }
                HStack(spacing: 8) {
                    Text("2").foregroundColor(.gray.opacity(0.4))
                    Text("import").foregroundColor(Color(hex: "#FF7B72")).bold()
                    Text("PurahCore").foregroundColor(Color(hex: "#79C0FF"))
                }
                HStack(spacing: 8) {
                    Text("3").foregroundColor(.gray.opacity(0.4))
                    Text("// Zero-block click-through with ergonomic edge rails").foregroundColor(Color.gray.opacity(0.6))
                }
                HStack(spacing: 8) {
                    Text("4").foregroundColor(.gray.opacity(0.4))
                    Text("@main").foregroundColor(Color(hex: "#FFA657"))
                }
                HStack(spacing: 8) {
                    Text("5").foregroundColor(.gray.opacity(0.4))
                    Text("struct").foregroundColor(Color(hex: "#FF7B72")).bold()
                    Text("AmbientKernel:").foregroundColor(.white)
                    Text("PurahPodPlugin").foregroundColor(Color(hex: "#7EE787"))
                    Text("{")
                }
                HStack(spacing: 8) {
                    Text("6").foregroundColor(.gray.opacity(0.4))
                    Text("    let rails = MagneticEdgeRails(edge: .right)")
                        .foregroundColor(Color(hex: "#A5D6FF"))
                }
                HStack(spacing: 8) {
                    Text("7").foregroundColor(.gray.opacity(0.4))
                    Text("    let terminal = SwiftTermInteractivePlugin()")
                        .foregroundColor(Color(hex: "#A5D6FF"))
                }
                HStack(spacing: 8) {
                    Text("8").foregroundColor(.gray.opacity(0.4))
                    Text("}")
                }
            }
            .font(.system(size: 11, design: .monospaced))
            .padding(14)
            Spacer()
        }
        .frame(width: 480, height: 280)
        .background(Color(hex: "#0D1117").opacity(0.92))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.12), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.45), radius: 24, y: 12)
    }
    
    // MARK: - Top Menu Bar
    var menuBarView: some View {
        HStack(spacing: 14) {
            Image(systemName: "applelogo")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white.opacity(0.9))
            Text("Purah").font(.system(size: 11, weight: .bold))
            Text("File").font(.system(size: 11)).foregroundColor(.white.opacity(0.8))
            Text("Edit").font(.system(size: 11)).foregroundColor(.white.opacity(0.8))
            Text("View").font(.system(size: 11)).foregroundColor(.white.opacity(0.8))
            Text("Plugins").font(.system(size: 11)).foregroundColor(.white.opacity(0.8))
            Spacer()
            Image(systemName: "circle.grid.2x1.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Color(hex: "#00F5D4"))
            Image(systemName: "wifi")
                .font(.system(size: 10))
            Image(systemName: "battery.100")
                .font(.system(size: 11))
            Text("Thu 10:24 AM")
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundColor(.white.opacity(0.85))
        .padding(.horizontal, 14)
        .frame(width: 960, height: 22)
        .background(Color(white: 0.08).opacity(0.88))
        .overlay(Rectangle().frame(height: 0.5).foregroundColor(Color.white.opacity(0.1)), alignment: .bottom)
    }
    
    // MARK: - Ambient Edge Rails
    var leftRailBars: some View {
        VStack(spacing: 8) {
            // Hardware Vitals
            Capsule().fill(Color(hex: "#00E5A3")).frame(width: 5, height: 85)
            // Terminal
            Capsule().fill(Color(hex: "#00F5D4")).frame(width: 5, height: 110)
            // Scripts
            Capsule().fill(Color(hex: "#A78BFA")).frame(width: 5, height: 75)
            // Notes
            Capsule().fill(Color(hex: "#FACC15")).frame(width: 5, height: 60)
            Spacer()
        }
        .padding(.top, 40)
        .frame(width: 5, height: 540)
        .position(x: 2.5, y: 270)
    }
    
    var rightRailBars: some View {
        VStack(spacing: 8) {
            Spacer()
            // Calendar
            Capsule().fill(Color(hex: "#FF5A60")).frame(width: 5, height: 100)
            // Todo
            Capsule().fill(Color(hex: "#F59E0B")).frame(width: 5, height: 80)
            // Music
            Capsule().fill(Color(hex: "#38BDF8")).frame(width: 5, height: 115)
        }
        .padding(.bottom, 25)
        .frame(width: 5, height: 540)
        .position(x: 957.5, y: 270)
    }
    
    // MARK: - Drawers
    func musicDrawerView(frame: Int, isPinned: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    // Album art
                    RoundedRectangle(cornerRadius: 6)
                        .fill(LinearGradient(colors: [Color.purple, Color.blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 38, height: 38)
                        .overlay(Image(systemName: "music.note").font(.system(size: 16)).foregroundColor(.white))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Kaepora - Ambient Reverie")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text("Purah Pad Soundtrack")
                            .font(.system(size: 9))
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                    
                    // Pin Button
                    ZStack {
                        Circle()
                            .fill(isPinned ? Color(hex: "#38BDF8").opacity(0.2) : Color.white.opacity(0.08))
                            .frame(width: 20, height: 20)
                        Image(systemName: isPinned ? "pin.fill" : "pin")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(isPinned ? Color(hex: "#38BDF8") : .gray)
                            .rotationEffect(.degrees(isPinned ? -25 : 0))
                    }
                }
                
                // Animated Multi-Sine Waveform
                HStack(alignment: .bottom, spacing: 2.5) {
                    ForEach(0..<28) { i in
                        let wave = sin(Double(i) * 0.35 + Double(frame) * 0.18) * 0.5 + 0.5
                        let h = 4.0 + wave * 22.0
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(LinearGradient(colors: [Color(hex: "#38BDF8"), Color(hex: "#818CF8")], startPoint: .bottom, endPoint: .top))
                            .frame(width: 5, height: h)
                    }
                }
                .frame(height: 28)
                
                // Scrub line & time
                HStack {
                    Text("1:24").font(.system(size: 8, design: .monospaced)).foregroundColor(.gray)
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.12)).frame(height: 3)
                            Capsule().fill(Color(hex: "#38BDF8")).frame(width: g.size.width * 0.42, height: 3)
                        }
                    }
                    .frame(height: 3)
                    Text("3:45").font(.system(size: 8, design: .monospaced)).foregroundColor(.gray)
                }
            }
            .padding(12)
        }
        .frame(width: 270, height: 115)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(hex: "#101626").opacity(0.92))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: "#38BDF8").opacity(0.55), lineWidth: 1.2))
                .shadow(color: Color(hex: "#38BDF8").opacity(0.18), radius: 12)
        )
    }
    
    var calendarDrawerView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(Color(hex: "#FF5A60")).frame(width: 7, height: 7)
                Text("Architecture Review")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                HStack(spacing: 3) {
                    Circle().fill(Color.white).frame(width: 3.5, height: 3.5)
                    Text("NOW").font(.system(size: 8, weight: .heavy)).foregroundColor(.white)
                }
                .padding(.horizontal, 4).padding(.vertical, 1.5)
                .background(Capsule().fill(Color(hex: "#FF5A60")))
                
                Spacer()
                
                // Join Zoom Pill Button
                HStack(spacing: 3) {
                    Image(systemName: "video.fill").font(.system(size: 8))
                    Text("Join Zoom").font(.system(size: 8, weight: .bold))
                }
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Capsule().fill(Color(hex: "#FF5A60").opacity(0.25)))
                .foregroundColor(Color(hex: "#FF5A60"))
            }
            
            Text("10:00 AM – 11:30 AM · Central Workshop")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.gray)
            
            Divider().background(Color.white.opacity(0.1))
            
            HStack(spacing: 6) {
                Circle().fill(Color.gray.opacity(0.6)).frame(width: 5, height: 5)
                Text("Environmental Monitoring").font(.system(size: 10)).foregroundColor(.gray)
                Spacer()
                Text("2:00 PM").font(.system(size: 8, design: .monospaced)).foregroundColor(.gray)
            }
        }
        .padding(12)
        .frame(width: 280, height: 95)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(hex: "#1A141A").opacity(0.92))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: "#FF5A60").opacity(0.55), lineWidth: 1.2))
                .shadow(color: Color(hex: "#FF5A60").opacity(0.16), radius: 12)
        )
    }
    
    func terminalDrawerView(typedCommand: String, showOutput: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header bar
            HStack(spacing: 6) {
                Image(systemName: "apple.terminal.fill")
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "#00F5D4"))
                Text("Terminal — SwiftTerm PTY")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                Spacer()
                Text("zsh 5.9").font(.system(size: 8, design: .monospaced)).foregroundColor(.gray)
            }
            
            // Console text area
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text("purah").foregroundColor(Color(hex: "#00F5D4")).bold()
                    Text("on").foregroundColor(.gray)
                    Text(" main").foregroundColor(Color(hex: "#FACC15")).bold()
                    Text("via 🏎️ v2.0").foregroundColor(Color(hex: "#A78BFA"))
                }
                
                HStack(spacing: 2) {
                    Text("$ \(typedCommand)").foregroundColor(.white)
                    Rectangle().fill(Color(hex: "#00F5D4")).frame(width: 6, height: 11)
                }
                
                if showOutput {
                    Text("✔ Edge Rails: Active (2 rails mounted)")
                        .foregroundColor(Color(hex: "#00E5A3"))
                    Text("✔ Zero-Block Click-Through: 100% Pass")
                        .foregroundColor(Color(hex: "#38BDF8"))
                    Text("✔ Metal GPU Waveform: 120 FPS")
                        .foregroundColor(Color(hex: "#FACC15"))
                }
            }
            .font(.system(size: 9.5, design: .monospaced))
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.45))
            .cornerRadius(6)
        }
        .padding(12)
        .frame(width: 350, height: 140)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(hex: "#0B151A").opacity(0.94))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: "#00F5D4").opacity(0.55), lineWidth: 1.2))
                .shadow(color: Color(hex: "#00F5D4").opacity(0.18), radius: 14)
        )
    }
    
    func hudCapsuleView(isRestoring: Bool) -> some View {
        HStack(spacing: 8) {
            Text(isRestoring ? "✨ Rails Active" : "❄️ Rails Frozen (⌥⇥ to restore)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.88))
                .overlay(Capsule().stroke(Color.white.opacity(0.22), lineWidth: 1))
                .shadow(color: Color.black.opacity(0.45), radius: 14, y: 4)
        )
    }
    
    // Pixel-accurate macOS pointer arrow
    var cursorView: some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 0, y: 16))
            path.addLine(to: CGPoint(x: 4.2, y: 12.2))
            path.addLine(to: CGPoint(x: 7.8, y: 19.4))
            path.addLine(to: CGPoint(x: 10.2, y: 18.2))
            path.addLine(to: CGPoint(x: 6.6, y: 11.2))
            path.addLine(to: CGPoint(x: 12, y: 11.2))
            path.closeSubpath()
        }
        .fill(Color.white)
        .overlay(
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 0, y: 16))
                path.addLine(to: CGPoint(x: 4.2, y: 12.2))
                path.addLine(to: CGPoint(x: 7.8, y: 19.4))
                path.addLine(to: CGPoint(x: 10.2, y: 18.2))
                path.addLine(to: CGPoint(x: 6.6, y: 11.2))
                path.addLine(to: CGPoint(x: 12, y: 11.2))
                path.closeSubpath()
            }
            .stroke(Color.black, lineWidth: 1.2)
        )
        .shadow(color: Color.black.opacity(0.4), radius: 3, x: 1, y: 2)
        .frame(width: 14, height: 21)
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

// MARK: - Main Execution Loop
@main
struct DemoRecorderMain {
    @MainActor
    static func main() {
        let frameCount = 300 // 12 seconds at 25 fps
        let outputDir = URL(fileURLWithPath: "/tmp/purah_demo_frames")
        try? FileManager.default.removeItem(at: outputDir)
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        
        print("🎬 Starting high-fidelity rendering of \(frameCount) frames at 960x540...")
        let startTime = Date()
        
        for i in 0..<frameCount {
            let view = DemoCanvasView(frame: i)
            let hosting = NSHostingView(rootView: view)
            hosting.frame = NSRect(x: 0, y: 0, width: 960, height: 540)
            hosting.layoutSubtreeIfNeeded()
            
            if let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
                hosting.cacheDisplay(in: hosting.bounds, to: rep)
                if let pngData = rep.representation(using: .png, properties: [:]) {
                    let fileURL = outputDir.appendingPathComponent(String(format: "frame_%04d.png", i))
                    try? pngData.write(to: fileURL)
                }
            }
            
            if (i + 1) % 50 == 0 || i == frameCount - 1 {
                print("   Rendered \(i + 1)/\(frameCount) frames...")
            }
        }
        
        let elapsed = Date().timeIntervalSince(startTime)
        print("✅ Finished rendering in \(String(format: "%.2f", elapsed))s (\(String(format: "%.1f", Double(frameCount) / elapsed)) FPS)")
    }
}
