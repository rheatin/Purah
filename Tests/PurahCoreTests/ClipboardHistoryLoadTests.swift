// Tests/PurahCoreTests/ClipboardHistoryLoadTests.swift
import Foundation
import Testing
@testable import PurahCore

@Suite("Clipboard History Loading")
struct ClipboardHistoryLoadTests {

    /// The launch read is asynchronous, so the first `history` read returns an
    /// empty list and the real one lands later. The clipboard drawer used to
    /// snapshot that first read and never hear about the second, so a fresh
    /// launch showed an empty Clipboard until the next copy refreshed it.
    @Test("A stored history reaches a listener that read too early")
    @MainActor
    func testHistoryLoadedCallback() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("purah_cliphistory_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let writer = SystemClipboardSyncService(storageDirectory: directory)
        writer.addItem(ClipboardItem(type: .text("copied before this launch")))

        let reader = SystemClipboardSyncService(storageDirectory: directory)
        var notified = false
        reader.onHistoryLoaded = { notified = true }

        // What `ClipboardPluginState.mount` does: read once, get nothing yet.
        #expect(reader.history.isEmpty)

        for _ in 0..<40 where !notified {
            try await Task.sleep(for: .milliseconds(50))
        }

        #expect(notified, "The disk load never told its listener")
        #expect(reader.history.contains { $0.plainTextToCopy == "copied before this launch" })
    }
}
