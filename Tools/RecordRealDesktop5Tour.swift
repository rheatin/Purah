// Tools/RecordRealDesktop5Tour.swift
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
        usleep(50000)
        if let down = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left) {
            down.post(tap: .cghidEventTap)
        }
        usleep(90000)
        if let up = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) {
            up.post(tap: .cghidEventTap)
        }
        usleep(60000)
    }
    
    static func glideMouse(from start: CGPoint, to end: CGPoint, duration: Double, steps: Int = 50) {
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
        usleep(150000)
        let up = CGEvent(keyboardEventSource: src, virtualKey: 48, keyDown: false)
        up?.flags = .maskAlternate
        up?.post(tap: .cghidEventTap)
        usleep(100000)
    }
}

@main
struct RealDesktop5Main {
    static func main() {
        let rawVideoPath = "/tmp/real_desktop5_full_take.mp4"
        try? FileManager.default.removeItem(atPath: rawVideoPath)
        
        print("🎬 Starting 29-second 100% REAL Screen Recording on Desktop 5...")
        let captureProcess = Process()
        captureProcess.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        captureProcess.arguments = ["-v", "-k", "-C", "-V29", rawVideoPath]
        try? captureProcess.run()
        
        sleep(1) // 1.0s initial buffer
        
        // 1. Right Edge: Calendar Event 1 (y=115)
        print("📍 [1/6] Real Calendar Event 1...")
        EventDriver.glideMouse(from: CGPoint(x: 864, y: 550), to: CGPoint(x: 1727, y: 115), duration: 1.2)
        usleep(300000)
        EventDriver.glideMouse(from: CGPoint(x: 1727, y: 115), to: CGPoint(x: 1520, y: 115), duration: 0.5)
        usleep(1400000)
        
        // 2. Right Edge: Calendar Event 2 / Meeting (y=235)
        print("📍 [2/6] Real Meeting Dry Run & Join...")
        EventDriver.glideMouse(from: CGPoint(x: 1520, y: 115), to: CGPoint(x: 1727, y: 235), duration: 0.8)
        usleep(300000)
        EventDriver.glideMouse(from: CGPoint(x: 1727, y: 235), to: CGPoint(x: 1540, y: 235), duration: 0.5)
        usleep(1600000)
        
        // 3. Right Edge: Todo / Music (y=665)
        print("📍 [3/6] Real Todo / Music...")
        EventDriver.glideMouse(from: CGPoint(x: 1540, y: 235), to: CGPoint(x: 1727, y: 665), duration: 1.1)
        usleep(300000)
        EventDriver.glideMouse(from: CGPoint(x: 1727, y: 665), to: CGPoint(x: 1540, y: 665), duration: 0.5)
        usleep(1600000)
        
        // 4. Left Edge: CPU Activity Graph (y=246)
        print("📍 [4/6] Real CPU Activity Graph...")
        EventDriver.glideMouse(from: CGPoint(x: 1540, y: 665), to: CGPoint(x: 1, y: 246), duration: 1.8)
        usleep(300000)
        EventDriver.glideMouse(from: CGPoint(x: 1, y: 246), to: CGPoint(x: 180, y: 246), duration: 0.5)
        usleep(1800000)
        
        // 5. Left Edge: Battery & Power 100% (y=348)
        print("📍 [5/6] Real Battery & Power Telemetry...")
        EventDriver.glideMouse(from: CGPoint(x: 180, y: 246), to: CGPoint(x: 1, y: 348), duration: 0.9)
        usleep(300000)
        EventDriver.glideMouse(from: CGPoint(x: 1, y: 348), to: CGPoint(x: 180, y: 348), duration: 0.5)
        usleep(1600000)
        
        // 6. Left Edge: Script Runway & Empty Trash (y=953)
        print("📍 [6/6] Real Script Runway & Empty Trash...")
        EventDriver.glideMouse(from: CGPoint(x: 180, y: 348), to: CGPoint(x: 1, y: 953), duration: 1.2)
        usleep(300000)
        EventDriver.glideMouse(from: CGPoint(x: 1, y: 953), to: CGPoint(x: 160, y: 953), duration: 0.5)
        usleep(1000000)
        // Click to execute action
        EventDriver.clickMouse(at: CGPoint(x: 160, y: 953))
        usleep(1800000)
        
        // 7. Center Desktop: Freeze Mode Option+Tab
        print("❄️ Real Freeze Mode (⌥⇥)...")
        EventDriver.glideMouse(from: CGPoint(x: 160, y: 953), to: CGPoint(x: 864, y: 550), duration: 1.2)
        usleep(400000)
        EventDriver.postOptionTab()
        usleep(2200000)
        EventDriver.postOptionTab()
        usleep(1200000)
        
        captureProcess.waitUntilExit()
        print("✅ 100% Real Desktop 5 Screen Recording Finished!")
    }
}
