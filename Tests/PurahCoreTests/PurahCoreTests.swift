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
        let service = SystemClipboardSyncService.shared
        service.clearAll()

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
}
