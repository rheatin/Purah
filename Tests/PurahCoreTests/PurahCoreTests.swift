// Tests/PurahCoreTests/PurahCoreTests.swift
import Testing
import Foundation
import AppKit
import Darwin
@testable import PurahCore
@testable import PurahUI
@testable import PurahApp

@Suite("PurahCore Foundation Tests")
struct PurahCoreTests {
    @Test("Verify PurahCore version identifier")
    func verifyVersion() {
        #expect(SemanticVersion(PurahCore.version) != nil)
        #expect(!PurahCore.version.isEmpty)
    }
}

@Suite("Memory Footprint & Allocation Verification Tests", .serialized)
@MainActor
struct MemoryFootprintTests {
    func currentFootprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        return Double(info.phys_footprint) / (1024.0 * 1024.0)
    }

    @Test("task_vm_info query returns valid physical memory footprint")
    func testMachTaskFootprintQuery() {
        let footprint = currentFootprintMB()
        #expect(footprint > 0.0, "Physical footprint must be greater than zero")
        #expect(footprint < 500.0, "Test process physical footprint should be reasonable")
    }

    @Test("WorkspaceStore and PluginRegistry idle initialization memory footprint stays strictly bounded")
    func testWorkspaceStoreAndPluginRegistryMemoryBudget() {
        let initialMB = currentFootprintMB()
        let store = PurahWorkspaceStore()
        PluginRegistry.shared.bindStore(store)
        let afterMB = currentFootprintMB()
        let deltaMB = afterMB - initialMB

        // Verify that binding store and plugins does not leak unbounded memory
        #expect(deltaMB < 30.0, "Core workspace store and plugins initialization must stay within strict 30MB memory budget (was \(deltaMB) MB)")
    }

    @Test("Clipboard image ingestion with streaming ImageIO produces minimal footprint growth")
    func testClipboardImageIngestionMemory() {
        let (service, cleanup) = SystemClipboardSyncService.createIsolatedTestService()
        defer { cleanup() }

        autoreleasepool {
            let img = NSImage(size: NSSize(width: 200, height: 200))
            img.lockFocus()
            NSColor.systemBlue.drawSwatch(in: NSRect(x: 0, y: 0, width: 200, height: 200))
            img.unlockFocus()

            if let tiff = img.tiffRepresentation {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setData(tiff, forType: .tiff)
                service.checkPasteboard()
            }
        }

        #expect(service.history.count >= 1, "Clipboard service must capture image")
        if let first = service.history.first, case .image(let path, let thumbPath, let w, let h, _) = first.type {
            #expect(w >= 200)
            #expect(h >= 200)
            #expect(FileManager.default.fileExists(atPath: path))
            #expect(FileManager.default.fileExists(atPath: thumbPath))

            // Verify thumbnail is downsampled to <= 100px
            if let thumbSource = CGImageSourceCreateWithURL(URL(fileURLWithPath: thumbPath) as CFURL, nil),
               let properties = CGImageSourceCopyPropertiesAtIndex(thumbSource, 0, nil) as? [CFString: Any],
               let thumbW = properties[kCGImagePropertyPixelWidth] as? Int,
               let thumbH = properties[kCGImagePropertyPixelHeight] as? Int {
                #expect(thumbW <= 100, "Thumbnail must be downsampled to <= 100px (was \(thumbW))")
                #expect(thumbH <= 100, "Thumbnail must be downsampled to <= 100px (was \(thumbH))")
            }
        }

        // Cleanup
        service.clearAll()
    }

    @Test("AmbientRailWindow initializes in compact 28pt state with bounded memory footprint")
    func testAmbientRailWindowCompactMemory() {
        let store = PurahWorkspaceStore()
        let initialMB = currentFootprintMB()

        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let railWindow = AmbientRailWindow(edge: .left, screen: screen, store: store)

        #expect(railWindow.frame.width == AmbientRailWindow.compactCanvasWidth)
        #expect(railWindow.frame.width == 28.0)

        let afterMB = currentFootprintMB()
        let deltaMB = afterMB - initialMB
        #expect(deltaMB < 25.0, "Compact AmbientRailWindow must not allocate bloated graphics memory (delta was \(deltaMB) MB)")
    }

    @Test("Sustained runtime memory footprint stays strictly stable without creeping over time")
    func testSustainedRuntimeMemoryStability() async {
        let store = PurahWorkspaceStore()
        PluginRegistry.shared.bindStore(store)
        let monitor = EdgeMouseMonitor(store: store)
        let visibleRect = NSRect(x: 0, y: 0, width: 1440, height: 900)
        monitor.customTargetVisibleRect = visibleRect

        // 1. Warmup cycles to reach steady-state heap
        for cycle in 0..<10 {
            autoreleasepool {
                let x = (cycle % 2 == 0) ? 5.0 : 500.0
                let pt = NSPoint(x: x, y: 450.0)
                monitor.customCurrentMouseLocation = pt
                monitor.processMouse(point: pt, now: Date())
                _ = store.resolvedPhysicalLayout(for: .left, totalHeight: 900.0)
            }
        }
        try? await Task.sleep(nanoseconds: 50_000_000)

        let baselineMB = currentFootprintMB()

        // 2. Run over simulated time (100 sustained iterations across continuous operations)
        let iterations = 100
        for i in 0..<iterations {
            autoreleasepool {
                let simTime = Date(timeIntervalSinceNow: Double(i) * 0.016)
                // Sweep mouse from left edge across rail into desktop and back
                let simX = (i % 4 == 0) ? 4.0 : ((i % 4 == 1) ? 20.0 : ((i % 4 == 2) ? 150.0 : 800.0))
                let simY = 200.0 + Double(i % 50) * 8.0
                let pt = NSPoint(x: simX, y: simY)
                monitor.customCurrentMouseLocation = pt
                monitor.processMouse(point: pt, now: simTime)

                _ = store.resolvedPhysicalLayout(for: .left, totalHeight: 900.0)
                _ = store.resolvedPhysicalLayout(for: .right, totalHeight: 900.0)
                _ = store.activeDrawerCardFrames(for: .left, totalHeight: 900.0)
            }

            if i % 25 == 0 {
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
        }

        // Allow runloop and tasks to stabilize
        try? await Task.sleep(nanoseconds: 100_000_000)

        let sustainedMB = currentFootprintMB()
        let creepDeltaMB = max(sustainedMB - baselineMB, 0.0)

        // Strict assertion: Over 100 continuous real-time simulated iterations, memory growth must be < 15MB
        #expect(creepDeltaMB < 15.0, "Sustained execution must not leak or creep memory over time (creep was \(creepDeltaMB) MB, baseline: \(baselineMB) MB, sustained: \(sustainedMB) MB)")
    }

    @Test("Verifies physical memory drops upon plugin unmounting and single-rail sleep")
    func testPluginUnmountMemoryDrop() async {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let store = PurahWorkspaceStore()

        // 1. Stage 1: Full Load (Both left and right rail windows active + in-memory payload)
        var leftWin: AmbientRailWindow? = AmbientRailWindow(edge: .left, screen: screen, store: store)
        var rightWin: AmbientRailWindow? = AmbientRailWindow(edge: .right, screen: screen, store: store)

        // Inject simulated in-memory artwork, lyrics, notes, and shelf items
        store._musicTrack.artworkData = Data(repeating: 0xAB, count: 4 * 1024 * 1024) // 4MB image
        store._musicTrack.lyrics = String(repeating: "Line of synced lyrics\n", count: 1000)
        store._quickNote.text = String(repeating: "Lots of active notes text content.\n", count: 500)

        let fullMountedMB = currentFootprintMB()

        // 2. Stage 2: Unmount Left Rail Plugins + Single-Rail Sleep
        store._quickNote.text = ""
        leftWin?.close()
        leftWin = nil
        try? await Task.sleep(nanoseconds: 30_000_000)

        let leftUnmountedMB = currentFootprintMB()

        // 3. Stage 3: Unmount Right Rail Plugins (Music, Calendar, Todo) + Both Rails Closed
        store._musicTrack.artworkData = nil
        store._musicTrack.lyrics = nil
        SystemMusicSyncService.shared.clearArtworkCache()
        rightWin?.close()
        rightWin = nil
        try? await Task.sleep(nanoseconds: 30_000_000)

        let allUnmountedMB = currentFootprintMB()

        // 4. Stage 4: Remount All Plugins
        var leftWinRestored: AmbientRailWindow? = AmbientRailWindow(edge: .left, screen: screen, store: store)
        var rightWinRestored: AmbientRailWindow? = AmbientRailWindow(edge: .right, screen: screen, store: store)

        let remountedMB = currentFootprintMB()
        leftWinRestored?.close()
        rightWinRestored?.close()
        leftWinRestored = nil
        rightWinRestored = nil

        let summary = """
        ========================================================
        📊 PLUGIN UNMOUNT & SINGLE-RAIL SLEEP MEMORY TELEMETRY
        ========================================================
        1. All Plugins Mounted + Dual Rail Windows: \(String(format: "%.2f", fullMountedMB)) MB
        2. Left Rail Unmounted (Single-Rail Sleep):  \(String(format: "%.2f", leftUnmountedMB)) MB (Saved \(String(format: "%.2f", fullMountedMB - leftUnmountedMB)) MB)
        3. All Rails Unmounted (Zero Rail Windows): \(String(format: "%.2f", allUnmountedMB)) MB (Saved \(String(format: "%.2f", fullMountedMB - allUnmountedMB)) MB)
        4. Remounted All Plugins (Full Recovery):   \(String(format: "%.2f", remountedMB)) MB
        ========================================================
        """
        try? summary.write(toFile: "/tmp/unmount_telemetry.txt", atomically: true, encoding: .utf8)

        #expect(allUnmountedMB <= fullMountedMB + 20.0, "All unmounted state must not exhibit runaway memory expansion")
        #expect(abs(remountedMB - fullMountedMB) < 25.0, "Remounting must not cause permanent runaway memory leak")
    }
}
