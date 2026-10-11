// Tools/MasterDesktop5Recorder.swift
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
struct MasterDesktop5Main {
    static func main() {
        let rawVideoPath = "/tmp/purah_d5_master_raw.mp4"
        try? FileManager.default.removeItem(atPath: rawVideoPath)
        
        print("🎬 Starting 20-second multi-tool screen recording on Desktop 5...")
        let captureProcess = Process()
        captureProcess.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        captureProcess.arguments = ["-v", "-k", "-C", "-V", "20", rawVideoPath]
        try? captureProcess.run()
        
        usleep(800000) // 0.8s
        
        // 1. Right Edge: Calendar (y=245)
        print("1. Right Edge: Calendar...")
        EventDriver.glideMouse(from: CGPoint(x: 864, y: 550), to: CGPoint(x: 1727, y: 245), duration: 1.4)
        usleep(600000)
        EventDriver.glideMouse(from: CGPoint(x: 1727, y: 245), to: CGPoint(x: 1540, y: 245), duration: 0.5)
        usleep(500000)
        // Click Pin
        EventDriver.glideMouse(from: CGPoint(x: 1540, y: 245), to: CGPoint(x: 1702, y: 75), duration: 0.4)
        EventDriver.clickMouse(at: CGPoint(x: 1702, y: 75))
        usleep(800000)
        
        // 2. Right Edge: Music (y=916)
        print("2. Right Edge: Music Waveform...")
        EventDriver.glideMouse(from: CGPoint(x: 1702, y: 75), to: CGPoint(x: 1727, y: 916), duration: 1.4)
        usleep(600000)
        EventDriver.glideMouse(from: CGPoint(x: 1727, y: 916), to: CGPoint(x: 1550, y: 916), duration: 0.5)
        usleep(1400000)
        
        // 3. Left Edge: Hardware Vitals (y=193)
        print("3. Left Edge: Hardware Vitals...")
        EventDriver.glideMouse(from: CGPoint(x: 1550, y: 916), to: CGPoint(x: 1, y: 193), duration: 1.8)
        usleep(600000)
        EventDriver.glideMouse(from: CGPoint(x: 1, y: 193), to: CGPoint(x: 200, y: 193), duration: 0.5)
        usleep(1400000)
        
        // 4. Left Edge: Drop Shelf (y=446)
        print("4. Left Edge: Drop Shelf...")
        EventDriver.glideMouse(from: CGPoint(x: 200, y: 193), to: CGPoint(x: 1, y: 446), duration: 1.2)
        usleep(600000)
        EventDriver.glideMouse(from: CGPoint(x: 1, y: 446), to: CGPoint(x: 220, y: 446), duration: 0.5)
        usleep(1400000)
        
        // 5. Left Edge: Script Runway (y=897)
        print("5. Left Edge: Script Runway...")
        EventDriver.glideMouse(from: CGPoint(x: 220, y: 446), to: CGPoint(x: 1, y: 897), duration: 1.3)
        usleep(600000)
        EventDriver.glideMouse(from: CGPoint(x: 1, y: 897), to: CGPoint(x: 220, y: 897), duration: 0.5)
        usleep(1400000)
        
        // 6. Center: Freeze Mode Option+Tab
        print("6. Center: Freeze Mode...")
        EventDriver.glideMouse(from: CGPoint(x: 220, y: 897), to: CGPoint(x: 864, y: 550), duration: 1.2)
        usleep(300000)
        EventDriver.postOptionTab()
        usleep(1400000)
        EventDriver.postOptionTab()
        usleep(800000)
        
        captureProcess.waitUntilExit()
        print("✅ Finished master recording on Desktop 5!")
    }
}
