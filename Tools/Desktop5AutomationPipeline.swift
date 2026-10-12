// Tools/Desktop5AutomationPipeline.swift
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
            let p = t * t * (3.0 - 2.0 * t) // Smoothstep
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
struct Desktop5PipelineMain {
    static func main() {
        let rawVideoPath = "/tmp/purah_d5_full_take.mp4"
        try? FileManager.default.removeItem(atPath: rawVideoPath)
        
        print("⏳ Waiting 3.5s for desktop switch to settle...")
        sleep(3)
        usleep(500000)
        
        print("🎬 Starting 28-second screen recording on Desktop 5...")
        let captureProcess = Process()
        captureProcess.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        captureProcess.arguments = ["-v", "-k", "-C", "-V28", rawVideoPath]
        try? captureProcess.run()
        
        usleep(1000000) // 1.0s initial buffer
        
        // 1. Right Edge: Calendar (y=245)
        print("📍 [1/7] Exploring Calendar...")
        EventDriver.glideMouse(from: CGPoint(x: 864, y: 550), to: CGPoint(x: 1727, y: 245), duration: 1.2)
        usleep(400000)
        EventDriver.glideMouse(from: CGPoint(x: 1727, y: 245), to: CGPoint(x: 1540, y: 245), duration: 0.5)
        usleep(1400000)
        
        // 2. Right Edge: Todo (y=430)
        print("📍 [2/7] Exploring Todo...")
        EventDriver.glideMouse(from: CGPoint(x: 1540, y: 245), to: CGPoint(x: 1727, y: 430), duration: 1.0)
        usleep(400000)
        EventDriver.glideMouse(from: CGPoint(x: 1727, y: 430), to: CGPoint(x: 1540, y: 430), duration: 0.5)
        usleep(1200000)
        
        // 3. Right Edge: Music (y=916)
        print("📍 [3/7] Exploring Music Waveform...")
        EventDriver.glideMouse(from: CGPoint(x: 1540, y: 430), to: CGPoint(x: 1727, y: 916), duration: 1.2)
        usleep(400000)
        EventDriver.glideMouse(from: CGPoint(x: 1727, y: 916), to: CGPoint(x: 1550, y: 916), duration: 0.5)
        usleep(1800000)
        
        // 4. Left Edge: Hardware Vitals (y=193)
        print("📍 [4/7] Crossing to Left Rail: Hardware Vitals...")
        EventDriver.glideMouse(from: CGPoint(x: 1550, y: 916), to: CGPoint(x: 1, y: 193), duration: 1.8)
        usleep(400000)
        EventDriver.glideMouse(from: CGPoint(x: 1, y: 193), to: CGPoint(x: 200, y: 193), duration: 0.5)
        usleep(1600000)
        
        // 5. Left Edge: Drop Shelf (y=446)
        print("📍 [5/7] Exploring Drop Shelf...")
        EventDriver.glideMouse(from: CGPoint(x: 200, y: 193), to: CGPoint(x: 1, y: 446), duration: 1.1)
        usleep(400000)
        EventDriver.glideMouse(from: CGPoint(x: 1, y: 446), to: CGPoint(x: 220, y: 446), duration: 0.5)
        usleep(1600000)
        
        // 6. Left Edge: Script Runway & Click "Empty Trash" (y=680)
        print("📍 [6/7] Exploring Script Runway & Triggering Empty Trash...")
        EventDriver.glideMouse(from: CGPoint(x: 220, y: 446), to: CGPoint(x: 1, y: 680), duration: 1.1)
        usleep(400000)
        EventDriver.glideMouse(from: CGPoint(x: 1, y: 680), to: CGPoint(x: 220, y: 680), duration: 0.5)
        usleep(800000)
        // Click Empty Trash Run button inside drawer card (Action row 2, trailing side ~x=310, y=695)
        EventDriver.glideMouse(from: CGPoint(x: 220, y: 680), to: CGPoint(x: 310, y: 695), duration: 0.5)
        EventDriver.clickMouse(at: CGPoint(x: 310, y: 695))
        usleep(1600000)
        
        // 7. Left Edge: SwiftTerm Terminal (y=920)
        print("📍 [7/7] Exploring SwiftTerm Terminal...")
        EventDriver.glideMouse(from: CGPoint(x: 310, y: 695), to: CGPoint(x: 1, y: 920), duration: 1.1)
        usleep(400000)
        EventDriver.glideMouse(from: CGPoint(x: 1, y: 920), to: CGPoint(x: 280, y: 920), duration: 0.5)
        usleep(1800000)
        
        // 8. Freeze Mode Option+Tab
        print("❄️ Triggering Freeze Mode (⌥⇥)...")
        EventDriver.glideMouse(from: CGPoint(x: 280, y: 920), to: CGPoint(x: 864, y: 550), duration: 1.2)
        usleep(400000)
        EventDriver.postOptionTab()
        usleep(1600000)
        EventDriver.postOptionTab()
        usleep(1000000)
        
        captureProcess.waitUntilExit()
        print("✅ Screen capture completed successfully!")
    }
}
