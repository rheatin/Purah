// Tools/RealDesktop5Recorder.swift
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
        usleep(50000)
    }
    
    static func glideMouse(from start: CGPoint, to end: CGPoint, duration: Double, steps: Int = 45) {
        let stepDelay = UInt32((duration / Double(steps)) * 1_000_000.0)
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            // Quintic smoothstep for Apple-style natural deceleration
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
struct RealDesktop5Main {
    static func main() {
        let rawVideoPath = "/tmp/purah_desktop5_raw.mp4"
        try? FileManager.default.removeItem(atPath: rawVideoPath)
        
        print("🚀 [1/4] Ensuring Purah is active on Desktop 5...")
        EventDriver.postOptionTab()
        usleep(300000)
        EventDriver.postOptionTab()
        usleep(500000)
        
        print("🎬 [2/4] Starting 15-second native screen recording...")
        let captureProcess = Process()
        captureProcess.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        captureProcess.arguments = ["-v", "-k", "-C", "-V", "15", rawVideoPath]
        try? captureProcess.run()
        
        // Wait 0.8s for screen recording engine to initialize
        usleep(800000)
        
        print("🖱️ [3/4] Executing choreographed interactions...")
        
        // Beat 1: Center to Right Bezel (Calendar)
        print("   -> Beat 1: Touching Right Bezel -> Calendar glides out...")
        EventDriver.glideMouse(from: CGPoint(x: 864, y: 550), to: CGPoint(x: 1727, y: 280), duration: 1.6)
        usleep(800000) // Dwell to trigger Calendar
        
        // Hover onto card and click Pin
        EventDriver.glideMouse(from: CGPoint(x: 1727, y: 280), to: CGPoint(x: 1540, y: 280), duration: 0.6)
        usleep(500000)
        EventDriver.glideMouse(from: CGPoint(x: 1540, y: 280), to: CGPoint(x: 1700, y: 232), duration: 0.4)
        EventDriver.clickMouse(at: CGPoint(x: 1700, y: 232))
        usleep(700000)
        
        // Beat 2: Down to Music on right rail
        print("   -> Beat 2: Gliding to Music -> Music drawer glides out...")
        EventDriver.glideMouse(from: CGPoint(x: 1700, y: 232), to: CGPoint(x: 1727, y: 850), duration: 1.4)
        usleep(800000) // Dwell to trigger Music
        EventDriver.glideMouse(from: CGPoint(x: 1727, y: 850), to: CGPoint(x: 1560, y: 850), duration: 0.6)
        usleep(1400000) // Hover over live waveform & track
        
        // Beat 3: Sweep across to Left Bezel (Hardware Vitals / Terminal)
        print("   -> Beat 3: Sweeping across to Left Bezel -> Left drawer glides out...")
        EventDriver.glideMouse(from: CGPoint(x: 1560, y: 850), to: CGPoint(x: 1, y: 280), duration: 1.8)
        usleep(900000) // Dwell to trigger left drawer
        EventDriver.glideMouse(from: CGPoint(x: 1, y: 280), to: CGPoint(x: 220, y: 280), duration: 0.6)
        usleep(1400000) // Hover over live telemetry
        
        // Beat 4: Glide to Center & Freeze Mode
        print("   -> Beat 4: Gliding to Center & Triggering ⌥⇥ Freeze Mode...")
        EventDriver.glideMouse(from: CGPoint(x: 220, y: 280), to: CGPoint(x: 864, y: 550), duration: 1.2)
        usleep(300000)
        
        // Press ⌥⇥: Rails Frozen HUD pops up, drawers vanish into bezel
        EventDriver.postOptionTab()
        usleep(1300000)
        
        // Press ⌥⇥: Rails Active HUD pops up, rails restore
        EventDriver.postOptionTab()
        usleep(800000)
        
        print("⏳ [4/4] Finalizing video...")
        captureProcess.waitUntilExit()
        
        print("🎉 Real recording complete!")
    }
}
