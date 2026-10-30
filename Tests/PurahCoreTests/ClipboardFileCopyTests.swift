// Tests/PurahCoreTests/ClipboardFileCopyTests.swift
import Testing
import Foundation
import AppKit
@testable import PurahCore

/// Finder puts the copied file's **icon** on the pasteboard as TIFF as well as the file URL.
/// The image branch ran first, so copying a picture recorded a 1024pt "PNG file" icon and the
/// clipboard showed a blank card for an image that was readable on disk.
@Suite("Clipboard File Copy Capture")
@MainActor
struct ClipboardFileCopyTests {

    private func makePasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("PurahClipboardFileCopyTests-\(UUID().uuidString)"))
        pasteboard.clearContents()
        return pasteboard
    }

    private func writeImageFile(ext: String = "png") throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PurahClipboardCopyTests", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("picture-\(UUID().uuidString).\(ext)")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: url)
        return url
    }

    @Test("A copied picture resolves to the file, not to its icon")
    func testFileURLWinsOverIconData() throws {
        let pasteboard = makePasteboard()
        let fileURL = try writeImageFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        pasteboard.writeObjects([fileURL as NSURL])
        pasteboard.setData(Data([0x00, 0x01, 0x02]), forType: .tiff)

        #expect(SystemClipboardSyncService.copiedImageFileURL(from: pasteboard)?.path == fileURL.path)
    }

    @Test("A copied non-picture file is not read as an image")
    func testNonImageFileIgnored() throws {
        let pasteboard = makePasteboard()
        let fileURL = try writeImageFile(ext: "pdf")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        pasteboard.writeObjects([fileURL as NSURL])
        #expect(SystemClipboardSyncService.copiedImageFileURL(from: pasteboard) == nil)
    }

    @Test("A file URL that no longer exists is not an image source")
    func testMissingFileIgnored() {
        let pasteboard = makePasteboard()
        let ghost = URL(fileURLWithPath: "/tmp/purah-\(UUID().uuidString).png")
        pasteboard.writeObjects([ghost as NSURL])
        #expect(SystemClipboardSyncService.copiedImageFileURL(from: pasteboard) == nil)
    }
}
