// Tools/RunRealDemoAutomation.swift
import Foundation
import CoreGraphics
import AppKit

// MARK: - Mouse & Keyboard Event Dispatcher
struct EventDriver {
    static let src = CGEventSource(stateID: .hidSystemState)
    
    static func moveMouse(to point: CGPoint) {
        if let event = CGEvent(mouseEventSource: src, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left) {
            event.post(tap: .cghidEventTap)
        }
    }
    
    static func clickMouse(at point: CGPoint) {
        moveMouse(to: point)
        usleep(30000)
        if let down = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left) {
            down.post(tap: .cghidEventTap)
        }
        usleep(60000)
        if let up = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) {
            up.post(tap: .cghidEventTap)
        }
        usleep(50000)
    }
    
    static func glideMouse(from start: CGPoint, to end: CGPoint, duration: Double, steps: Int = 40) {
        let stepDelay = UInt32((duration / Double(steps)) * 1_000_000.0)
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            // Cubic ease-in-out
            let p = t < 0.5 ? 4.0 * t * t * t : 1.0 - pow(-2.0 * t + 2.0, 3.0) / 2.0
            let x = start.x + (end.x - start.x) * p
            let y = start.y + (end.y - start.y) * p
            moveMouse(to: CGPoint(x: x, y: y))
            usleep(stepDelay)
        }
    }
    
    static func postOptionTab() {
        let down = CGEvent(keyboardEventSource: src, virtualKey: 48, keyDown: true) // 48 = Tab
        down?.flags = .maskAlternate
        down?.post(tap: .cghidEventTap)
        usleep(120000)
        let up = CGEvent(keyboardEventSource: src, virtualKey: 48, keyDown: false)
        up?.flags = .maskAlternate
        up?.post(tap: .cghidEventTap)
        usleep(100000)
    }
}

// MARK: - Main Automation Sequence
@main
struct RealDemoAutomationMain {
    static func main() {
        let rawVideoPath = "/tmp/purah_live_real_raw.mp4"
        try? FileManager.default.removeItem(atPath: rawVideoPath)
        
        print("🚀 [Step 1] Ensuring Purah is active & rails un-frozen...")
        // Ensure Purah is un-frozen
        EventDriver.postOptionTab()
        usleep(400000)
        EventDriver.postOptionTab()
        usleep(600000)
        
        print("🎬 [Step 2] Starting native screencapture (14 seconds)...")
        let captureProcess = Process()
        captureProcess.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        captureProcess.arguments = ["-v", "-k", "-C", "-V", "14", rawVideoPath]
        try? captureProcess.run()
        
        // Wait 1.0s for screencapture to begin capturing frames
        usleep(1000000)
        
        print("🖱️ [Step 3] Executing choreographed real mouse gestures...")
        
        // 1. Move from center toward right edge (Music Waveform)
        print("   -> Gliding to Right Edge (Music Waveform)...")
        EventDriver.glideMouse(from: CGPoint(x: 1000, y: 600), to: CGPoint(x: 1727, y: 780), duration: 1.8)
        usleep(800000) // Dwell on bezel to trigger drawer slide-out
        
        // 2. Hover inside Music drawer card and click Pin
        print("   -> Hovering Music Drawer & Pinning...")
        EventDriver.glideMouse(from: CGPoint(x: 1727, y: 780), to: CGPoint(x: 1560, y: 780), duration: 0.8)
        usleep(600000)
        // Click Pin button near top-right of the card
        EventDriver.glideMouse(from: CGPoint(x: 1560, y: 780), to: CGPoint(x: 1690, y: 720), duration: 0.5)
        EventDriver.clickMouse(at: CGPoint(x: 1690, y: 720))
        usleep(600000)
        
        // 3. Move up to Calendar on right rail
        print("   -> Gliding up to Calendar Timeline...")
        EventDriver.glideMouse(from: CGPoint(x: 1690, y: 720), to: CGPoint(x: 1727, y: 320), duration: 1.4)
        usleep(800000) // Dwell to trigger Calendar card slide-out
        EventDriver.glideMouse(from: CGPoint(x: 1727, y: 320), to: CGPoint(x: 1580, y: 320), duration: 0.6)
        usleep(1000000) // Hover over meeting card
        
        // 4. Sweep across to Left Rail (Terminal / Hardware Vitals)
        print("   -> Sweeping across to Left Edge Rail...")
        EventDriver.glideMouse(from: CGPoint(x: 1580, y: 320), to: CGPoint(x: 1, y: 400), duration: 2.0)
        usleep(1000000) // Dwell to trigger left drawer slide-out
        EventDriver.glideMouse(from: CGPoint(x: 1, y: 400), to: CGPoint(x: 220, y: 400), duration: 0.7)
        usleep(1200000) // Hover on card
        
        // 5. Glide to Center and trigger Freeze Mode HUD
        print("   -> Gliding to Center & Triggering Option+Tab (⌥⇥)...")
        EventDriver.glideMouse(from: CGPoint(x: 220, y: 400), to: CGPoint(x: 864, y: 600), duration: 1.2)
        usleep(300000)
        
        // Press Option + Tab: Rails Frozen HUD appears
        EventDriver.postOptionTab()
        usleep(1200000)
        
        // Press Option + Tab again: Rails Active HUD appears
        EventDriver.postOptionTab()
        usleep(800000)
        
        print("⏳ Waiting for screencapture to finalize...")
        captureProcess.waitUntilExit()
        
        print("✅ Real screen recording completed successfully!")
    }
}
