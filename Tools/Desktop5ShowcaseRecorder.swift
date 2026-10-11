// Tools/Desktop5ShowcaseRecorder.swift
import Foundation
import CoreGraphics
import AppKit

struct EventDriver {
    static let src = CGEventSource(stateID: .hidSystemState)
    
    static func moveMouse(to point: CGPoint) {
        if let event = CGEvent(mouseEventSource: src, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left) {
            event.post(tap: .cghidEventTap)
        }
    }
    
    static func clickMouse(at point: CGPoint) {
        moveMouse(to: point)
        usleep(40000)
        if let down = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left) {
            down.post(tap: .cghidEventTap)
        }
        usleep(80000)
        if let up = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) {
            up.post(tap: .cghidEventTap)
        }
        usleep(60000)
    }
    
    static func glideMouse(from start: CGPoint, to end: CGPoint, duration: Double, steps: Int = 45) {
        let stepDelay = UInt32((duration / Double(steps)) * 1_000_000.0)
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            // Quintic smoothstep for Apple-style natural glide
            let p = t * t * t * (t * (t * 6.0 - 15.0) + 10.0)
            let x = start.x + (end.x - start.x) * p
            let y = start.y + (end.y - start.y) * p
            moveMouse(to: CGPoint(x: x, y: y))
            usleep(stepDelay)
        }
    }
    
    static func postOptionTab() {
        let down = CGEvent(keyboardEventSource: src, virtualKey: 48, keyDown: true)
        down?.flags = .maskAlternate
        down?.post(tap: .cghidEventTap)
        usleep(140000)
        let up = CGEvent(keyboardEventSource: src, virtualKey: 48, keyDown: false)
        up?.flags = .maskAlternate
        up?.post(tap: .cghidEventTap)
        usleep(100000)
    }
}

@main
struct ShowcaseMain {
    static func main() {
        let rawVideoPath = "/tmp/purah_d5_showcase_raw.mp4"
        try? FileManager.default.removeItem(atPath: rawVideoPath)
        
        print("🚀 [1/5] Ensuring Purah rails are un-frozen...")
        EventDriver.postOptionTab()
        usleep(300000)
        EventDriver.postOptionTab()
        usleep(600000)
        
        print("🎬 [2/5] Starting 18-second native screen capture...")
        let captureProcess = Process()
        captureProcess.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        captureProcess.arguments = ["-v", "-k", "-C", "-V", "18", rawVideoPath]
        try? captureProcess.run()
        
        // Wait 0.8s for screen capture engine
        usleep(800000)
        
        print("🖱️ [3/5] Choreographing high-density real interactions...")
        
        // Beat 1: Center -> Right Bezel (Calendar at y=245)
        print("   -> Beat 1: Calendar slide-out...")
        EventDriver.glideMouse(from: CGPoint(x: 864, y: 550), to: CGPoint(x: 1727, y: 245), duration: 1.5)
        usleep(700000) // Dwell on bezel to trigger Calendar
        
        // Hover onto Calendar card & click Pin
        EventDriver.glideMouse(from: CGPoint(x: 1727, y: 245), to: CGPoint(x: 1540, y: 245), duration: 0.5)
        usleep(500000)
        // Click Pin button at (1703, 75)
        EventDriver.glideMouse(from: CGPoint(x: 1540, y: 245), to: CGPoint(x: 1703, y: 75), duration: 0.4)
        EventDriver.clickMouse(at: CGPoint(x: 1703, y: 75))
        usleep(700000)
        
        // Beat 2: Right Bezel (Music at y=916)
        print("   -> Beat 2: Music slide-out...")
        EventDriver.glideMouse(from: CGPoint(x: 1703, y: 75), to: CGPoint(x: 1727, y: 916), duration: 1.5)
        usleep(700000) // Dwell on bezel to trigger Music
        
        // Hover onto Music card & click Play/Pause
        EventDriver.glideMouse(from: CGPoint(x: 1727, y: 916), to: CGPoint(x: 1550, y: 916), duration: 0.6)
        usleep(800000)
        // Click Play/Pause button
        EventDriver.glideMouse(from: CGPoint(x: 1550, y: 916), to: CGPoint(x: 1588, y: 960), duration: 0.4)
        EventDriver.clickMouse(at: CGPoint(x: 1588, y: 960))
        usleep(1200000) // Dwell to see live audio waveform
        
        // Beat 3: Sweep across to Left Bezel (Terminal at y=975)
        print("   -> Beat 3: Terminal slide-out on left edge...")
        EventDriver.glideMouse(from: CGPoint(x: 1588, y: 960), to: CGPoint(x: 1, y: 975), duration: 2.0)
        usleep(900000) // Dwell on left bezel to trigger Terminal
        EventDriver.glideMouse(from: CGPoint(x: 1, y: 975), to: CGPoint(x: 240, y: 975), duration: 0.7)
        usleep(1800000) // Dwell inside Terminal
        
        // Beat 4: Left Bezel (Hardware Vitals at y=193)
        print("   -> Beat 4: Hardware Vitals slide-out...")
        EventDriver.glideMouse(from: CGPoint(x: 240, y: 975), to: CGPoint(x: 1, y: 193), duration: 1.5)
        usleep(800000) // Dwell on left bezel to trigger Vitals
        EventDriver.glideMouse(from: CGPoint(x: 1, y: 193), to: CGPoint(x: 200, y: 193), duration: 0.6)
        usleep(1600000) // Dwell inside Vitals
        
        // Beat 5: Center & Option+Tab Freeze Mode
        print("   -> Beat 5: Center Glide & ⌥⇥ Freeze Mode...")
        EventDriver.glideMouse(from: CGPoint(x: 200, y: 193), to: CGPoint(x: 864, y: 550), duration: 1.2)
        usleep(300000)
        
        // Press ⌥⇥: Rails Frozen HUD appears, all drawers vanish
        EventDriver.postOptionTab()
        usleep(1300000)
        
        // Press ⌥⇥: Rails Active HUD appears, rails return
        EventDriver.postOptionTab()
        usleep(800000)
        
        print("⏳ [4/5] Waiting for screencapture to finalize...")
        captureProcess.waitUntilExit()
        
        print("🎉 [5/5] Real showcase recording completed!")
    }
}
