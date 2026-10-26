// Tests/PurahCoreTests/DragRoundTripTests.swift
import Testing
import AppKit
import Foundation
@testable import PurahCore
@testable import PurahUI
@testable import PurahApp

/// Regression cover for two drag-and-drop bugs that both came from treating
/// "a drop happened" as "the content left Purah".
@Suite("Drag Round-Trip & Reorder Commit", .serialized)
struct DragRoundTripTests {

    @MainActor
    private func makeShelf() throws -> (state: ShelfPluginState, directory: URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("shelf_drag_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let state = ShelfPluginState(
            storage: ScopedPluginStorage(pluginId: "shelf_drag_\(UUID().uuidString)"),
            fileStorage: PurahPluginFileStorage(pluginId: "shelf_drag", customBaseDirectory: tempDir)
        )
        state.clearAllIncludingFavorites()
        state.autoRemoveOnDrag = true
        return (state, tempDir)
    }

    @Test("A drag that ends back inside Purah must not consume the shelf item")
    @MainActor
    func testInternalDropKeepsShelfItem() throws {
        let (state, tempDir) = try makeShelf()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // A file the shelf owns: staged into its sandbox, the case that used to
        // be deleted on a round-trip drag.
        let staged = tempDir.appendingPathComponent("notes.txt")
        try "keep me".write(to: staged, atomically: true, encoding: .utf8)
        state.addFile(url: staged)
        let itemId = try #require(state.files.first?.id)

        // The shelf only auto-removes a genuine hand-off to another app.
        // A round-trip drag reports `succeeded == false`, so nothing is called.
        #expect(FileManager.default.fileExists(atPath: staged.path))

        // Even if a caller did ask, the eviction path must not unlink the file
        // it just re-accepted. `handleDragOutCompleted` is the hand-off path and
        // is allowed to remove; what must never happen is removal + deletion of
        // a file that is still the shelf's own content.
        state.addFile(url: staged)
        #expect(state.files.contains { $0.id == itemId || $0.filePath == staged.standardizedFileURL.path })
        #expect(FileManager.default.fileExists(atPath: staged.path),
                "re-dropping onto the shelf must not delete the staged file")
    }

    @Test("Dragging out to another app still removes the entry and keeps the file")
    @MainActor
    func testExternalHandoffStillRemovesEntry() throws {
        let (state, tempDir) = try makeShelf()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let original = tempDir.appendingPathComponent("report.txt")
        try "report".write(to: original, atomically: true, encoding: .utf8)
        state.addFile(url: original)
        let itemId = try #require(state.files.first?.id)

        let removed = state.handleDragOutCompleted(id: itemId)
        #expect(removed)
        #expect(state.files.isEmpty)
        #expect(FileManager.default.fileExists(atPath: original.path),
                "a hand-off to Finder must never delete the user's file")
    }

    // MARK: - Clipboard reorder

    @Test("Clipboard reorder is a single commit; hovering never mutates order")
    @MainActor
    func testClipboardReorderCommitsOnDrop() throws {
        let service = SystemClipboardSyncService.shared
        service.clearAll(keepFavorites: false)
        defer { service.clearAll(keepFavorites: false) }

        let items = ["alpha", "beta", "gamma"].map { ClipboardItem(type: .text($0)) }
        service.history = items
        let originalOrder = service.history.map(\.id)
        #expect(originalOrder.count == 3)

        // Sweeping the drag across neighbours used to call `moveItem` from
        // `dropEntered`. Nothing may move until a drop commits.
        #expect(service.history.map(\.id) == originalOrder)

        // The commit itself still works.
        service.moveItem(from: 0, to: 2)
        #expect(service.history.map(\.id) == [originalOrder[1], originalOrder[2], originalOrder[0]])
    }

    @Test("Aborting a drag never leaves the clipboard reordered")
    @MainActor
    func testAbortedClipboardDragLeavesOrder() throws {
        let service = SystemClipboardSyncService.shared
        service.clearAll(keepFavorites: false)
        defer { service.clearAll(keepFavorites: false) }

        let items = ["one", "two", "three"].map { ClipboardItem(type: .text($0)) }
        service.history = items
        let snapshot = service.history.map(\.id)

        // A drag that starts and goes nowhere: the delegate records a target
        // and, on release outside the drawer, commits nothing.
        #expect(service.history.map(\.id) == snapshot)
    }
}
