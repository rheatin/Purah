// Tests/PurahCoreTests/ClipboardUpgradeTests.swift
import Testing
import Foundation
import AppKit
import CoreGraphics
@testable import PurahCore

@Suite("Clipboard Image Deduplication & Deterministic Fingerprinting Tests", .serialized)
@MainActor
struct ClipboardUpgradeTests {
    @Test("service.processImageData and service.addItem deduplicate identical images from PNG and TIFF representations")
    func testImageDeduplicationAcrossTiffAndPng() {
        let (service, cleanup) = SystemClipboardSyncService.createIsolatedTestService()
        defer { cleanup() }

        // Create a test NSImage with a defined bitmap representation
        let size = NSSize(width: 80, height: 80)
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 80,
            pixelsHigh: 80,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 80 * 4,
            bitsPerPixel: 32
        )!
        NSGraphicsContext.saveGraphicsState()
        let ctx = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.current = ctx
        NSColor.systemPurple.setFill()
        NSRect(origin: .zero, size: size).fill()
        NSGraphicsContext.restoreGraphicsState()

        let nsImage = NSImage(size: size)
        nsImage.addRepresentation(rep)

        guard let tiffData = nsImage.tiffRepresentation,
              let pngData = rep.representation(using: .png, properties: [:]) else {
            #expect(Bool(false), "Failed to generate TIFF and PNG test data")
            return
        }

        // 1. First ingestion from TIFF
        guard let itemFromTIFF = service.processImageData(tiffData, isPNG: false) else {
            #expect(Bool(false), "Failed to process TIFF data")
            return
        }
        service.addItem(itemFromTIFF)
        #expect(service.history.count == 1)

        // 2. Second ingestion from PNG of the exact same NSImage (simulating lazy pasteboard updates)
        guard let itemFromPNG = service.processImageData(pngData, isPNG: true) else {
            #expect(Bool(false), "Failed to process PNG data")
            return
        }
        service.addItem(itemFromPNG)
        #expect(service.history.count == 1, "Duplicate image representation must be deduplicated in clipboard history")
        #expect(itemFromTIFF.plainTextToCopy == itemFromPNG.plainTextToCopy)

        // 3. Third ingestion with TIFF again
        service.addItem(itemFromTIFF)
        #expect(service.history.count == 1, "Repeated addition of same image must remain 1 item")

        // 4. Test re-copying moves item to top and preserves favorite status
        let textItem = ClipboardItem(type: .text("Middle text item"))
        service.addItem(textItem)
        #expect(service.history.count == 2)
        #expect(service.history.first?.plainTextToCopy == "Middle text item")

        // Favorite the image item at index 1
        service.toggleFavorite(id: service.history[1].id)
        #expect(service.history[1].isFavorite == true)

        // Re-copy the same image
        service.addItem(itemFromPNG)
        #expect(service.history.count == 2)
        #expect(service.history.first?.plainTextToCopy == itemFromPNG.plainTextToCopy)
        #expect(service.history.first?.isFavorite == true, "Re-copied image item must retain star/favorite status")
    }

    @Test("computeImageFingerprint produces deterministic output for identical images")
    func testDeterministicImageFingerprint() {
        let size = NSSize(width: 60, height: 60)
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 60,
            pixelsHigh: 60,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 60 * 4,
            bitsPerPixel: 32
        )!
        NSGraphicsContext.saveGraphicsState()
        let ctx = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.current = ctx
        NSColor.systemTeal.setFill()
        NSRect(origin: .zero, size: size).fill()
        NSGraphicsContext.restoreGraphicsState()

        let nsImage = NSImage(size: size)
        nsImage.addRepresentation(rep)

        guard let tiffData = nsImage.tiffRepresentation,
              let pngData = rep.representation(using: .png, properties: [:]) else {
            #expect(Bool(false), "Failed to generate test image data")
            return
        }

        let s1 = CGImageSourceCreateWithData(tiffData as CFData, nil)!
        let s2 = CGImageSourceCreateWithData(pngData as CFData, nil)!
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 100
        ]
        let t1 = CGImageSourceCreateThumbnailAtIndex(s1, 0, thumbOptions as CFDictionary)!
        let t2 = CGImageSourceCreateThumbnailAtIndex(s2, 0, thumbOptions as CFDictionary)!

        let hash1 = SystemClipboardSyncService.computeImageFingerprint(cgImage: t1, pixelWidth: 60, pixelHeight: 60, fallbackData: tiffData)
        let hash2 = SystemClipboardSyncService.computeImageFingerprint(cgImage: t2, pixelWidth: 60, pixelHeight: 60, fallbackData: pngData)

        #expect(hash1 == hash2)
        #expect(!hash1.isEmpty)
    }
}
