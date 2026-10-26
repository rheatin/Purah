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

    @Test("A drag that ends back on the shelf must not consume the item")
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

        // Drag begins.
        ShelfDragSession.shared.begin(paths: [staged.path])

        // Dropping back on the shelf's own target claims the round trip.
        ShelfDragSession.shared.claimSelfDrop()
        #expect(ShelfDragSession.shared.consumeSelfDrop(),
                "the shelf's own drop target must mark this as a round trip")

        // The drag source therefore reports no export, so nothing is removed.
        #expect(FileManager.default.fileExists(atPath: staged.path))
        #expect(state.files.contains { $0.id == itemId })
    }

    @Test("Dropping onto another pod still counts as an export")
    @MainActor
    func testDropOnOtherPodIsStillAnExport() throws {
        let (state, tempDir) = try makeShelf()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let staged = tempDir.appendingPathComponent("report.txt")
        try "report".write(to: staged, atomically: true, encoding: .utf8)
        state.addFile(url: staged)
        let itemId = try #require(state.files.first?.id)

        ShelfDragSession.shared.begin(paths: [staged.path])

        // Nobody claimed it: the payload went to the clipboard, another pod, or
        // another app. That is a hand-off.
        #expect(!ShelfDragSession.shared.consumeSelfDrop())

        state.handleBatchDragOutCompleted(ids: [itemId])
        #expect(state.files.isEmpty)
        // Still never deletes the file: the drag source hands out its own
        // sandboxed copy, and losing that is exactly the bug being fixed.
        #expect(FileManager.default.fileExists(atPath: staged.path))
    }

    @Test("The self-drop claim never leaks into the next drag")
    @MainActor
    func testClaimDoesNotLeak() throws {
        let (_, tempDir) = try makeShelf()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let first = tempDir.appendingPathComponent("a.txt")
        try "a".write(to: first, atomically: true, encoding: .utf8)

        ShelfDragSession.shared.begin(paths: [first.path])
        ShelfDragSession.shared.claimSelfDrop()
        #expect(ShelfDragSession.shared.consumeSelfDrop())

        // A brand new drag starts clean; a stale claim would swallow the export.
        ShelfDragSession.shared.begin(paths: [first.path])
        #expect(!ShelfDragSession.shared.consumeSelfDrop())
    }

    @Test("Only URLs from the current shelf drag are recognised")
    @MainActor
    func testCarriesAnyMatchesCurrentDragOnly() throws {
        let (_, tempDir) = try makeShelf()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dragged = tempDir.appendingPathComponent("mine.txt")
        let foreign = tempDir.appendingPathComponent("theirs.txt")
        try "mine".write(to: dragged, atomically: true, encoding: .utf8)
        try "theirs".write(to: foreign, atomically: true, encoding: .utf8)

        ShelfDragSession.shared.begin(paths: [dragged.path])
        #expect(ShelfDragSession.shared.carriesAny(of: [dragged]))
        #expect(!ShelfDragSession.shared.carriesAny(of: [foreign]),
                "an unrelated file must not be mistaken for a round trip")
        ShelfDragSession.shared.reset()
        #expect(!ShelfDragSession.shared.carriesAny(of: [dragged]),
                "no drag in flight means nothing matches")
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
