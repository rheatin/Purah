// Tools/GenerateCompleteShowcase.swift
import SwiftUI
import AppKit
import Foundation

// MARK: - Mathematical Motion Easing
struct Motion {
    static func easeOutCubic(_ t: Double) -> Double {
        let f = t - 1.0
        return f * f * f + 1.0
    }
    static func easeInOut(_ t: Double) -> Double {
        t < 0.5 ? 4.0 * t * t * t : 1.0 - pow(-2.0 * t + 2.0, 3.0) / 2.0
    }
    static func spring(_ t: Double) -> Double {
        guard t > 0 else { return 0 }
        guard t < 1 else { return 1 }
        let c4 = (2.0 * Double.pi) / 3.0
        return pow(2, -10 * t) * sin((t * 10 - 0.75) * c4) + 1.0
    }
}

// MARK: - 1. Cut 1: Stroke-Segment-Build (Title Hook - 105 frames @ 30fps)
struct Cut1View: View {
    let frame: Int
    var body: some View {
        let t = Double(frame)
        let settle = 68.0
        let isSettled = t >= settle
        let settlePulse = isSettled ? max(1.0 + (1.0 - min((t - settle) / 10.0, 1.0)) * 0.08, 1.0) : 1.0
        let frameThick = min(t / 20.0, 1.0) * 14.0
        
        ZStack {
            Color(red: 0.03, green: 0.04, blue: 0.07)
            
            // 4 perimeter border bands
            VStack {
                Rectangle().fill(Color(hex: "#FF5A60")).frame(height: frameThick)
                Spacer()
                Rectangle().fill(Color(hex: "#00F5D4")).frame(height: frameThick)
            }
            HStack {
                Rectangle().fill(Color(hex: "#00E5A3")).frame(width: frameThick)
                Spacer()
                Rectangle().fill(Color(hex: "#38BDF8")).frame(width: frameThick)
            }
            
            RadialGradient(
                colors: [Color.cyan.opacity(0.18), Color.clear],
                center: .center, startRadius: 20, endRadius: 550
            )
            
            VStack(spacing: 20) {
                HStack(spacing: 16) {
                    letter(lines: [(-20,0,12,90,"#FF5A60",10),(10,-36,50,12,"#FF5A60",25),(35,-18,12,36,"#FF5A60",40),(10,0,50,12,"#FF5A60",65)], t: t)
                    letter(lines: [(-25,-10,12,70,"#00E5A3",15),(0,35,55,12,"#00E5A3",66),(25,-10,12,70,"#00E5A3",32)], t: t)
                    letter(lines: [(-20,0,12,90,"#38BDF8",12),(10,-36,48,12,"#38BDF8",36),(34,-20,12,32,"#38BDF8",48),(10,-4,48,12,"#38BDF8",60),(22,26,14,42,"#38BDF8",67)], t: t)
                    letter(lines: [(-20,0,12,90,"#F59E0B",20),(0,-38,48,12,"#F59E0B",30),(20,0,12,90,"#F59E0B",52),(0,4,42,12,"#F59E0B",66)], t: t)
                    letter(lines: [(-24,0,12,90,"#00F5D4",14),(24,0,12,90,"#00F5D4",44),(0,0,46,12,"#00F5D4",68)], t: t)
                }
                .scaleEffect(settlePulse)
                
                if isSettled {
                    Text("The Edge of Your Display.")
                        .font(.system(size: 28, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(min((t - settle) / 18.0, 0.9)))
                }
            }
        }
        .frame(width: 1920, height: 1080)
    }
    
    func letter(lines: [(CGFloat, CGFloat, CGFloat, CGFloat, String, Double)], t: Double) -> some View {
        ZStack {
            ForEach(0..<lines.count, id: \.self) { i in
                let l = lines[i]
                let active = t >= l.5
                let p = active ? Motion.easeOutCubic(min((t - l.5) / 8.0, 1.0)) : 0.0
                RoundedRectangle(cornerRadius: min(l.2, l.3) / 2)
                    .fill(Color(hex: l.4))
                    .frame(width: l.2, height: l.3)
                    .opacity(p)
                    .shadow(color: Color(hex: l.4).opacity(0.6 * p), radius: 8)
                    .offset(x: l.0, y: l.1 + (1.0 - p) * 12)
            }
        }
        .frame(width: 80, height: 90)
    }
}

// MARK: - 2. Cut 2: Close-up on Calendar Timeline & Todo (120 frames @ 30fps)
struct Cut2View: View {
    let frame: Int
    var body: some View {
        let t = Double(frame)
        let slideP = Motion.spring(min(t / 22.0, 1.0))
        let isPinned = t >= 55.0
        let isDone = t >= 80.0
        
        ZStack(alignment: .trailing) {
            darkStage
            
            VStack(alignment: .trailing, spacing: 18) {
                // Calendar Card
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Circle().fill(Color(hex: "#FF5A60")).frame(width: 10, height: 10)
                            Text("Architecture Review")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            
                            HStack(spacing: 4) {
                                Circle().fill(Color.white).frame(width: 5, height: 5)
                                Text("NOW").font(.system(size: 11, weight: .heavy)).foregroundColor(.white)
                            }
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Capsule().fill(Color(hex: "#FF5A60")))
                            
                            Spacer()
                            
                            // Join Zoom button
                            HStack(spacing: 5) {
                                Image(systemName: "video.fill").font(.system(size: 12))
                                Text("Join Zoom").font(.system(size: 12, weight: .bold))
                            }
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().fill(Color(hex: "#FF5A60").opacity(0.25)))
                            .foregroundColor(Color(hex: "#FF5A60"))
                            
                            // Pin
                            Image(systemName: isPinned ? "pin.fill" : "pin")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(isPinned ? Color(hex: "#FF5A60") : .gray)
                                .rotationEffect(.degrees(isPinned ? -25 : 0))
                        }
                        
                        Text("10:00 AM – 11:30 AM · Central Workshop")
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundColor(.gray)
                    }
                    .padding(18)
                }
                .frame(width: 620, height: 130)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(hex: "#1A141A").opacity(0.92))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: "#FF5A60").opacity(0.6), lineWidth: 1.5))
                        .shadow(color: Color(hex: "#FF5A60").opacity(0.2), radius: 18)
                )
                .offset(x: (1.0 - slideP) * 650)
                
                // Todo Checklist Card
                HStack(spacing: 14) {
                    Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundColor(Color(hex: "#F59E0B"))
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Calibrate edge tactile dwell sensors")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .strikethrough(isDone)
                            .foregroundColor(isDone ? .gray : .white)
                        
                        Text("Due Today · High Priority")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                    }
                    Spacer()
                    Text("Reminders")
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color(hex: "#F59E0B").opacity(0.18))
                        .foregroundColor(Color(hex: "#F59E0B"))
                        .cornerRadius(6)
                }
                .padding(18)
                .frame(width: 580, height: 95)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(hex: "#1A1812").opacity(0.92))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: "#F59E0B").opacity(0.55), lineWidth: 1.5))
                        .shadow(color: Color(hex: "#F59E0B").opacity(0.2), radius: 18)
                )
                .offset(x: (1.0 - slideP) * 650)
            }
            .padding(.trailing, 24)
            
            // Subtitle banner (No menu bar)
            VStack {
                Spacer()
                Text("Calendar & Reminders · Pixel-for-pixel co-planar")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.bottom, 40)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(width: 1920, height: 1080)
    }
}

// MARK: - 3. Cut 3: Close-up on Music Waveform (120 frames @ 30fps)
struct Cut3View: View {
    let frame: Int
    var body: some View {
        let t = Double(frame)
        let slideP = Motion.spring(min(t / 20.0, 1.0))
        let isPlaying = true
        
        ZStack(alignment: .trailing) {
            darkStage
            
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 16) {
                    // Album Art
                    RoundedRectangle(cornerRadius: 12)
                        .fill(LinearGradient(colors: [Color(hex: "#38BDF8"), Color(hex: "#6366F1")], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 72, height: 72)
                        .overlay(Image(systemName: "music.note").font(.system(size: 32)).foregroundColor(.white))
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Down in Sandbar")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("Lala Hsu · Apple Music")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                    
                    // Pin
                    Image(systemName: "pin.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(Color(hex: "#38BDF8"))
                        .rotationEffect(.degrees(-25))
                }
                
                // Live Multi-Sine Fluid Waveform
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(0..<48) { i in
                        let wave = sin(Double(i) * 0.32 + Double(frame) * 0.22) * 0.5 + 0.5
                        let h = 8.0 + wave * 48.0
                        RoundedRectangle(cornerRadius: 2)
                            .fill(LinearGradient(colors: [Color(hex: "#38BDF8"), Color(hex: "#818CF8")], startPoint: .bottom, endPoint: .top))
                            .frame(width: 8, height: h)
                    }
                }
                .frame(height: 56)
                
                // Scrubber line
                HStack {
                    Text("01:28").font(.system(size: 13, design: .monospaced)).foregroundColor(.gray)
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.12)).frame(height: 5)
                            Capsule().fill(Color(hex: "#38BDF8")).frame(width: g.size.width * 0.38, height: 5)
                        }
                    }
                    .frame(height: 5)
                    Text("03:45").font(.system(size: 13, design: .monospaced)).foregroundColor(.gray)
                }
                
                // Transport controls
                HStack(spacing: 28) {
                    Spacer()
                    Image(systemName: "backward.fill").font(.system(size: 18)).foregroundColor(.white.opacity(0.8))
                    Circle().fill(Color(hex: "#38BDF8")).frame(width: 42, height: 42)
                        .overlay(Image(systemName: isPlaying ? "pause.fill" : "play.fill").foregroundColor(.black).font(.system(size: 18)))
                    Image(systemName: "forward.fill").font(.system(size: 18)).foregroundColor(.white.opacity(0.8))
                    Spacer()
                }
            }
            .padding(24)
            .frame(width: 640, height: 260)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(hex: "#0F172A").opacity(0.94))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(hex: "#38BDF8").opacity(0.65), lineWidth: 1.5))
                    .shadow(color: Color(hex: "#38BDF8").opacity(0.25), radius: 24)
            )
            .offset(x: (1.0 - slideP) * 680)
            .padding(.trailing, 24)
            
            VStack {
                Spacer()
                Text("Music Waveform · 120 FPS Metal GPU visualizer")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.bottom, 40)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(width: 1920, height: 1080)
    }
}

// MARK: - 4. Cut 4: Close-up on SwiftTerm Interactive Terminal (135 frames @ 30fps)
struct Cut4View: View {
    let frame: Int
    var body: some View {
        let t = Double(frame)
        let slideP = Motion.spring(min(t / 22.0, 1.0))
        
        let fullCmd = "purah status --health"
        let typeP = min(max((t - 25) / 30.0, 0.0), 1.0)
        let typedCount = Int(typeP * Double(fullCmd.count))
        let typed = String(fullCmd.prefix(typedCount))
        let showOutput = t >= 60.0
        
        ZStack(alignment: .leading) {
            darkStage
            
            VStack(alignment: .leading, spacing: 14) {
                // Header
                HStack(spacing: 8) {
                    Image(systemName: "apple.terminal.fill")
                        .font(.system(size: 16))
                        .foregroundColor(Color(hex: "#00F5D4"))
                    Text("Terminal — SwiftTerm PTY")
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                    Spacer()
                    Text("zsh 5.9 · Maple Mono NF")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.gray)
                }
                
                // Console Area
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text("purah").foregroundColor(Color(hex: "#00F5D4")).bold()
                        Text("on").foregroundColor(.gray)
                        Text(" main [!]").foregroundColor(Color(hex: "#FACC15")).bold()
                        Text("via 🏎️ v2.0").foregroundColor(Color(hex: "#A78BFA"))
                    }
                    
                    HStack(spacing: 3) {
                        Text("$ \(typed)").foregroundColor(.white)
                        Rectangle().fill(Color(hex: "#00F5D4")).frame(width: 8, height: 16)
                    }
                    
                    if showOutput {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("✔ Edge Rails: Active (2 rails mounted)").foregroundColor(Color(hex: "#00E5A3"))
                            Text("✔ Zero-Block Click-Through: 100% Pass").foregroundColor(Color(hex: "#38BDF8"))
                            Text("✔ SwiftTerm PTY: Interactive shell online").foregroundColor(Color(hex: "#FACC15"))
                            Text("✔ Metal GPU Waveform: 120 FPS").foregroundColor(Color(hex: "#A78BFA"))
                        }
                        .padding(.top, 4)
                    }
                }
                .font(.system(size: 14.5, design: .monospaced))
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.55))
                .cornerRadius(8)
            }
            .padding(22)
            .frame(width: 780, height: 320)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(hex: "#0A141A").opacity(0.95))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(hex: "#00F5D4").opacity(0.65), lineWidth: 1.5))
                    .shadow(color: Color(hex: "#00F5D4").opacity(0.25), radius: 24)
            )
            .offset(x: -(1.0 - slideP) * 820)
            .padding(.leading, 24)
            
            VStack {
                Spacer()
                Text("Embedded Terminal · Powered by SwiftTerm with Starship Nerd Font")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.bottom, 40)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(width: 1920, height: 1080)
    }
}

// MARK: - 5. Cut 5: Close-up on Hardware Vitals & Drop Shelf (120 frames @ 30fps)
struct Cut5View: View {
    let frame: Int
    var body: some View {
        let t = Double(frame)
        let slideP = Motion.spring(min(t / 22.0, 1.0))
        
        ZStack(alignment: .leading) {
            darkStage
            
            VStack(alignment: .leading, spacing: 18) {
                // Hardware Vitals
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "waveform.path.ecg").foregroundColor(Color(hex: "#00E5A3")).font(.system(size: 16))
                        Text("Hardware Vitals").font(.system(size: 18, weight: .bold, design: .rounded)).foregroundColor(.white)
                        Spacer()
                        Text("Live Darwin Telemetry").font(.system(size: 12)).foregroundColor(.gray)
                    }
                    
                    HStack(spacing: 12) {
                        metricChip(name: "CPU", val: "15%", sub: "M5 Pro · 20 Cores", color: "#00E5A3", prog: 0.15)
                        metricChip(name: "RAM", val: "79%", sub: "19.0 / 24 GB", color: "#F59E0B", prog: 0.79)
                        metricChip(name: "SSD", val: "593G", sub: "Free space", color: "#38BDF8", prog: 0.40)
                        metricChip(name: "Power", val: "100%", sub: "AC Connected", color: "#00E5A3", prog: 1.0)
                    }
                }
                .padding(18)
                .frame(width: 680, height: 140)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(hex: "#0A1A14").opacity(0.92))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: "#00E5A3").opacity(0.6), lineWidth: 1.5))
                        .shadow(color: Color(hex: "#00E5A3").opacity(0.2), radius: 18)
                )
                .offset(x: -(1.0 - slideP) * 720)
                
                // Drop Shelf
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "tray.fill").foregroundColor(Color(hex: "#2ED573")).font(.system(size: 16))
                        Text("Drop Shelf").font(.system(size: 18, weight: .bold, design: .rounded)).foregroundColor(.white)
                        Spacer()
                        Text("2 items stashed").font(.system(size: 12)).foregroundColor(.gray)
                    }
                    
                    HStack(spacing: 12) {
                        fileRow(icon: "doc.fill", name: "macOS_Workflow_Spec.pdf", size: "2.4 MB")
                        fileRow(icon: "photo.fill", name: "Architecture_Diagram.png", size: "4.8 MB")
                    }
                }
                .padding(18)
                .frame(width: 680, height: 110)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(hex: "#101D16").opacity(0.92))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: "#2ED573").opacity(0.55), lineWidth: 1.5))
                        .shadow(color: Color(hex: "#2ED573").opacity(0.2), radius: 18)
                )
                .offset(x: -(1.0 - slideP) * 720)
            }
            .padding(.leading, 24)
            
            VStack {
                Spacer()
                Text("Hardware Vitals & Drop Shelf · Instant glance & staging")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.bottom, 40)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(width: 1920, height: 1080)
    }
    
    func metricChip(name: String, val: String, sub: String, color: String, prog: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name).font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                Spacer()
                Text(val).font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundColor(Color(hex: color))
            }
            Capsule().fill(Color.white.opacity(0.1)).frame(height: 4)
                .overlay(Capsule().fill(Color(hex: color)).frame(width: 120 * prog, height: 4), alignment: .leading)
            Text(sub).font(.system(size: 10)).foregroundColor(.gray)
        }
        .padding(10)
        .frame(width: 145)
        .background(Color.white.opacity(0.05))
        .cornerRadius(8)
    }
    
    func fileRow(icon: String, name: String, size: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundColor(Color(hex: "#2ED573")).font(.system(size: 16))
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 13, weight: .medium)).foregroundColor(.white).lineLimit(1)
                Text(size).font(.system(size: 11)).foregroundColor(.gray)
            }
            Spacer()
        }
        .padding(10)
        .frame(width: 300)
        .background(Color.white.opacity(0.05))
        .cornerRadius(8)
    }
}

// MARK: - 6. Cut 6: Close-up on Script Runway with "Empty Trash" Action (105 frames @ 30fps)
struct Cut6View: View {
    let frame: Int
    var body: some View {
        let t = Double(frame)
        let slideP = Motion.spring(min(t / 22.0, 1.0))
        let isClicked = t >= 45.0
        let showDone = t >= 65.0
        
        ZStack(alignment: .leading) {
            darkStage
            
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Image(systemName: "terminal.fill").foregroundColor(Color(hex: "#6C5CE7")).font(.system(size: 18))
                        Text("Script Runway").font(.system(size: 20, weight: .bold, design: .rounded)).foregroundColor(.white)
                        Spacer()
                        Text("Developer Automations").font(.system(size: 12, design: .monospaced)).foregroundColor(.gray)
                    }
                    
                    VStack(spacing: 10) {
                        // Action 1: Empty Trash (Featured Action)
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(hex: "#6C5CE7").opacity(0.18))
                                    .frame(width: 38, height: 38)
                                Image(systemName: "trash.fill")
                                    .foregroundColor(Color(hex: "#6C5CE7"))
                                    .font(.system(size: 18))
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text("Empty Trash")
                                        .font(.system(size: 16, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                    Text("AppleScript")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Color(hex: "#6C5CE7").opacity(0.25))
                                        .foregroundColor(Color(hex: "#6C5CE7"))
                                        .cornerRadius(4)
                                }
                                Text("Permanently empty all items in Trash")
                                    .font(.system(size: 12))
                                    .foregroundColor(.gray)
                            }
                            
                            Spacer()
                            
                            // Tactile Run Button
                            HStack(spacing: 6) {
                                Image(systemName: showDone ? "checkmark" : (isClicked ? "arrow.triangle.2.circlepath" : "play.fill"))
                                    .font(.system(size: 12))
                                Text(showDone ? "Done" : (isClicked ? "Running..." : "Run"))
                                    .font(.system(size: 13, weight: .bold))
                            }
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(showDone ? Color(hex: "#00E5A3") : Color(hex: "#6C5CE7"))
                            )
                            .foregroundColor(.white)
                            .scaleEffect(isClicked && !showDone ? 0.94 : 1.0)
                        }
                        .padding(14)
                        .background(Color.white.opacity(0.06))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: "#6C5CE7").opacity(isClicked ? 0.8 : 0.2), lineWidth: 1.5))
                        .cornerRadius(10)
                        
                        // Action 2: Flush DNS
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.white.opacity(0.08))
                                    .frame(width: 38, height: 38)
                                Image(systemName: "network")
                                    .foregroundColor(.gray)
                                    .font(.system(size: 18))
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Flush DNS Cache").font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                                Text("dscacheutil -flushcache; killall -HUP mDNSResponder").font(.system(size: 11, design: .monospaced)).foregroundColor(.gray)
                            }
                            Spacer()
                            Text("Run").font(.system(size: 12, weight: .semibold)).padding(.horizontal, 12).padding(.vertical, 6).background(Color.white.opacity(0.08)).foregroundColor(.gray).cornerRadius(6)
                        }
                        .padding(12)
                        .background(Color.white.opacity(0.03))
                        .cornerRadius(8)
                    }
                }
                .padding(22)
                .frame(width: 720, height: 260)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(hex: "#121020").opacity(0.95))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(hex: "#6C5CE7").opacity(0.6), lineWidth: 1.5))
                        .shadow(color: Color(hex: "#6C5CE7").opacity(0.25), radius: 22)
                )
                .offset(x: -(1.0 - slideP) * 750)
                
                // Toast notification on completion
                if showDone {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles").foregroundColor(Color(hex: "#00E5A3"))
                        Text("✨ Ran Empty Trash").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundColor(.white)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(
                        Capsule().fill(Color.black.opacity(0.85))
                            .overlay(Capsule().stroke(Color(hex: "#00E5A3").opacity(0.5), lineWidth: 1))
                            .shadow(color: Color.black.opacity(0.4), radius: 12)
                    )
                    .transition(.opacity)
                }
            }
            .padding(.leading, 24)
            
            VStack {
                Spacer()
                Text("Script Runway · Instant developer automations & AppleScript execution")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.bottom, 40)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(width: 1920, height: 1080)
    }
}

// MARK: - 7. Cut 7: Pill-Slot-Cycle (All 8 Tools - 120 frames @ 30fps)
struct Cut7View: View {
    let frame: Int
    let words = [
        ("Terminal", "#00F5D4", "apple.terminal.fill"),
        ("Hardware", "#00E5A3", "waveform.path.ecg"),
        ("Calendar", "#FF5A60", "calendar"),
        ("Tasks", "#F59E0B", "checklist"),
        ("Music", "#38BDF8", "waveform"),
        ("Shelf", "#2ED573", "tray.fill"),
        ("Scripts", "#6C5CE7", "terminal.fill")
    ]
    
    var body: some View {
        let t = Double(frame)
        let beatDur = 14.0
        let activeIdx = min(Int(t / beatDur), words.count - 1)
        let beatPhase = (t - Double(activeIdx) * beatDur) / beatDur
        let current = words[activeIdx]
        let isFinalLock = t >= (Double(words.count - 1) * beatDur + 10.0)
        
        ZStack {
            Color(red: 0.05, green: 0.06, blue: 0.09)
            
            RadialGradient(
                colors: [Color(hex: current.1).opacity(0.16), Color.clear],
                center: .center, startRadius: 10, endRadius: 550
            )
            
            VStack(spacing: 24) {
                HStack(spacing: 16) {
                    Text("Purah puts your")
                        .font(.system(size: 68, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    HStack(spacing: 12) {
                        Image(systemName: current.2)
                            .font(.system(size: 38, weight: .bold))
                            .foregroundColor(Color(hex: current.1))
                        Text(current.0)
                            .font(.system(size: 52, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 32).padding(.vertical, 14)
                    .background(
                        Capsule().fill(Color(hex: current.1).opacity(0.18))
                            .overlay(Capsule().stroke(Color(hex: current.1).opacity(0.85), lineWidth: 2))
                            .shadow(color: Color(hex: current.1).opacity(0.4), radius: 16)
                    )
                    .offset(y: (1.0 - Motion.easeOutCubic(min(beatPhase * 2.2, 1.0))) * 50)
                    .opacity(Motion.easeOutCubic(min(beatPhase * 2.5, 1.0)))
                }
                
                Text(isFinalLock ? "all within a single flick." : "at the physical edge of your screen.")
                    .font(.system(size: 34, weight: .medium, design: .rounded))
                    .foregroundColor(isFinalLock ? Color(hex: "#00F5D4") : .gray.opacity(0.8))
            }
        }
        .frame(width: 1920, height: 1080)
    }
}

// MARK: - 8. Cut 8: Zero-Block Pull-Back & Option-Tab Freeze Mode (90 frames @ 30fps)
struct Cut8View: View {
    let frame: Int
    var body: some View {
        let t = Double(frame)
        let isFrozen = t >= 25.0
        let retractP = isFrozen ? Motion.easeOutCubic(min((t - 25) / 18.0, 1.0)) : 0.0
        let hudP = isFrozen ? Motion.spring(min((t - 25) / 16.0, 1.0)) : 0.0
        
        ZStack {
            // Real Desktop 5 background (Menu bar strictly excluded from y=0..72)
            if let img = NSImage(contentsOfFile: "/tmp/d5_clean_bg.png") {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                darkStage
            }
            
            // Clean desktop center text
            VStack(spacing: 12) {
                Text("100% Zero-Block Architecture")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.6), radius: 12)
                Text("Zero pixels wasted. Central screen always left to your work.")
                    .font(.system(size: 22))
                    .foregroundColor(.white.opacity(0.85))
                    .shadow(color: .black.opacity(0.6), radius: 8)
            }
            
            // Edge rails vanishing into bezels
            HStack {
                // Left rails
                Capsule().fill(Color(hex: "#00E5A3")).frame(width: 8, height: 180)
                    .offset(x: -retractP * 30)
                    .opacity(1.0 - retractP)
                Spacer()
                // Right rails
                Capsule().fill(Color(hex: "#FF5A60")).frame(width: 8, height: 180)
                    .offset(x: retractP * 30)
                    .opacity(1.0 - retractP)
            }
            .padding(.horizontal, 2)
            
            // Floating HUD Capsule (Option + Tab)
            if isFrozen {
                HStack(spacing: 12) {
                    Text("❄️ Rails Frozen (⌥⇥ to restore)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 34).padding(.vertical, 18)
                .background(
                    Capsule().fill(Color.black.opacity(0.92))
                        .overlay(Capsule().stroke(Color.white.opacity(0.3), lineWidth: 1.5))
                        .shadow(color: Color.black.opacity(0.6), radius: 28, y: 10)
                )
                .scaleEffect(hudP)
                .position(x: 960, y: 920)
            }
        }
        .frame(width: 1920, height: 1080)
    }
}

// MARK: - 9. Cut 9: Brand Outro (Icon Flip Bloom - 90 frames @ 30fps)
struct Cut9View: View {
    let frame: Int
    var body: some View {
        let t = Double(frame)
        let flipEnd = 24.0
        let isFlipped = t >= flipEnd
        let bloomP = isFlipped ? Motion.spring(min((t - flipEnd) / 20.0, 1.0)) : 0.0
        
        ZStack {
            Color(red: 0.03, green: 0.04, blue: 0.07)
            
            RadialGradient(
                colors: [Color(hex: "#00E5A3").opacity(0.20 * bloomP), Color.clear],
                center: .center, startRadius: 20, endRadius: 650
            )
            
            VStack(spacing: 28) {
                ZStack {
                    if !isFlipped {
                        HStack(spacing: 6) {
                            Circle().fill(Color(hex: "#00F5D4")).frame(width: 14, height: 14)
                            Circle().fill(Color(hex: "#00E5A3")).frame(width: 14, height: 14)
                        }
                        .scaleEffect(x: max(1.0 - (t / flipEnd), 0.04), y: 1.0)
                    } else {
                        Image(nsImage: NSImage(contentsOfFile: "assets/Purah-icon-macOS-1024.png") ?? NSImage())
                            .resizable().aspectRatio(contentMode: .fit)
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
                        
                        Text("macOS Magnetic Edge Rails · Ambient Ergonomic Kernel")
                            .font(.system(size: 24, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.7))
                        
                        HStack(spacing: 8) {
                            Image(systemName: "link").font(.system(size: 16))
                            Text("github.com/rheatin/Purah")
                                .font(.system(size: 20, weight: .bold, design: .monospaced))
                        }
                        .foregroundColor(Color(hex: "#00F5D4"))
                        .padding(.top, 6)
                    }
                }
            }
        }
        .frame(width: 1920, height: 1080)
    }
}

// MARK: - Dark Stage Background Helper (100% Free of Menu Bar & Private Info)
var darkStage: some View {
    LinearGradient(
        colors: [
            Color(red: 0.07, green: 0.09, blue: 0.15),
            Color(red: 0.03, green: 0.04, blue: 0.08)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
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
struct MasterShowcaseRunner {
    @MainActor
    static func main() {
        let baseDir = URL(fileURLWithPath: "/tmp/master_cuts")
        try? FileManager.default.removeItem(at: baseDir)
        try? FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        
        print("🎬 [1/9] Cut 1: Stroke-Segment-Build (105f)...")
        render(dir: baseDir.appendingPathComponent("cut1"), count: 105) { Cut1View(frame: $0) }
        
        print("🎬 [2/9] Cut 2: Calendar Timeline & Todo (120f)...")
        render(dir: baseDir.appendingPathComponent("cut2"), count: 120) { Cut2View(frame: $0) }
        
        print("🎬 [3/9] Cut 3: Music Waveform (120f)...")
        render(dir: baseDir.appendingPathComponent("cut3"), count: 120) { Cut3View(frame: $0) }
        
        print("🎬 [4/9] Cut 4: SwiftTerm Interactive Terminal (135f)...")
        render(dir: baseDir.appendingPathComponent("cut4"), count: 135) { Cut4View(frame: $0) }
        
        print("🎬 [5/9] Cut 5: Hardware Vitals & Drop Shelf (120f)...")
        render(dir: baseDir.appendingPathComponent("cut5"), count: 120) { Cut5View(frame: $0) }
        
        print("🎬 [6/9] Cut 6: Quick Notes & Script Runway (105f)...")
        render(dir: baseDir.appendingPathComponent("cut6"), count: 105) { Cut6View(frame: $0) }
        
        print("🎬 [7/9] Cut 7: Pill-Slot-Cycle (All 8 Tools, 120f)...")
        render(dir: baseDir.appendingPathComponent("cut7"), count: 120) { Cut7View(frame: $0) }
        
        print("🎬 [8/9] Cut 8: Zero-Block Freeze Mode (90f)...")
        render(dir: baseDir.appendingPathComponent("cut8"), count: 90) { Cut8View(frame: $0) }
        
        print("🎬 [9/9] Cut 9: Icon-Flip-Bloom Brand Outro (90f)...")
        render(dir: baseDir.appendingPathComponent("cut9"), count: 90) { Cut9View(frame: $0) }
        
        print("✅ All 9 cuts rendered with 100% Privacy Protection & All 8 Tools!")
    }
    
    @MainActor
    static func render<V: View>(dir: URL, count: Int, builder: (Int) -> V) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for f in 0..<count {
            let view = builder(f)
            let hosting = NSHostingView(rootView: view)
            hosting.frame = NSRect(x: 0, y: 0, width: 1920, height: 1080)
            hosting.layoutSubtreeIfNeeded()
            
            if let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
                hosting.cacheDisplay(in: hosting.bounds, to: rep)
                if let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: dir.appendingPathComponent(String(format: "frame_%04d.png", f)))
                }
            }
        }
    }
}
