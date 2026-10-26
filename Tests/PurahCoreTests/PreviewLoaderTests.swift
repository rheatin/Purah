// Tests/PurahCoreTests/PreviewLoaderTests.swift
import Testing
import Foundation
import AppKit
import ImageIO
@testable import PurahCore
@testable import PurahUI

/// Guards the bounded hover-preview reader: previews must never load a whole
/// file just to show the first screenful.
@Suite("Hover Preview Loader Tests")
struct PreviewLoaderTests {

    private func makeTempDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("purah_preview_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("Text preview stops at the character limit regardless of file size")
    func testTextPreviewIsBounded() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("big.log")

        let line = String(repeating: "a", count: 1_024)
        let body = Array(repeating: line, count: 512).joined(separator: "\n")
        try body.write(to: url, atomically: true, encoding: .utf8)

        let preview = try #require(PurahFilePreviewLoader.loadTextPreview(at: url))
        #expect(preview.count == PurahFilePreviewLoader.characterLimit)
        #expect(preview.hasPrefix("aaa"))
    }

    @Test("Text preview trims a partial trailing scalar instead of returning mojibake")
    func testTextPreviewHandlesSplitMultibyte() {
        // A 2-byte scalar whose second byte falls past a 3-byte window must be
        // dropped rather than decoded into garbage.
        let splitScalar = Data([0x41, 0x42, 0xC3]) // "AB" + first byte of "é"
        let dir = (try? makeTempDirectory()) ?? FileManager.default.temporaryDirectory
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("split.txt")
        try? splitScalar.write(to: url)

        let preview = PurahFilePreviewLoader.loadTextPreview(at: url, byteLimit: 3)
        #expect(preview == "AB")
    }

    @Test("Image preview downsamples but reports the source pixel dimensions")
    func testImagePreviewReportsSourceDimensions() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("large.png")

        let sourceSize = NSSize(width: 2_000, height: 1_000)
        let source = NSImage(size: sourceSize)
        source.lockFocus()
        NSColor.systemTeal.setFill()
        NSRect(origin: .zero, size: sourceSize).fill()
        source.unlockFocus()

        guard let tiff = source.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            Issue.record("Could not encode fixture image")
            return
        }
        try png.write(to: url)

        // Read the fixture's real dimensions back from disk: `NSImage` lockFocus
        // scales by the display's backing factor, so the encoded PNG is not
        // necessarily 2000×1000.
        let sourceRef = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let props = CGImageSourceCopyPropertiesAtIndex(sourceRef, 0, nil) as? [CFString: Any]
        let expectedWidth = try #require((props?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue)
        let expectedHeight = try #require((props?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue)

        let preview = try #require(PurahFilePreviewLoader.loadImagePreview(at: url, maxPixelSize: 256))
        // The decoded thumbnail is downsampled…
        #expect(preview.image.size.width <= 256)
        // …while the reported dimensions are the source's.
        #expect(preview.pixelWidth == expectedWidth)
        #expect(preview.pixelHeight == expectedHeight)
        #expect(preview.pixelWidth > 256, "fixture must be larger than the thumbnail bound")
    }

    @Test("Non-image and unreadable files yield no preview instead of trapping")
    func testMissingFileReturnsNil() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("purah_missing_\(UUID().uuidString).txt")
        #expect(PurahFilePreviewLoader.loadTextPreview(at: missing) == nil)
        #expect(PurahFilePreviewLoader.loadImagePreview(at: missing) == nil)
    }
}
