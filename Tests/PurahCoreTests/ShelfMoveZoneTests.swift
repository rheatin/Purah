import Testing
import Foundation
import PurahCore
@testable import PurahUI

@Suite("Drop Shelf Move Zone", .serialized)
@MainActor
struct ShelfMoveZoneTests {
    private struct Fixture {
        let state: ShelfPluginState
        let store: PurahWorkspaceStore
        let defaults: UserDefaults
        let suiteName: String
        let workspace: URL

        func cleanUp() {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: workspace)
        }
    }

    private func makeFixture(
        storage: (any PurahPluginStorage)? = nil
    ) throws -> Fixture {
        let suiteName = "shelf_move_\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("shelf-move-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)

        let scoped = storage ?? ScopedPluginStorage(pluginId: "shelf-move", defaults: defaults)
        let fileStorage = PurahPluginFileStorage(
            pluginId: "shelf-move",
            customBaseDirectory: workspace.appendingPathComponent("PluginStorage", isDirectory: true)
        )
        let state = ShelfPluginState(storage: scoped, fileStorage: fileStorage)
        let store = PurahWorkspaceStore(userDefaults: defaults)
        state.mount(store: store)
        return Fixture(
            state: state,
            store: store,
            defaults: defaults,
            suiteName: suiteName,
            workspace: workspace
        )
    }

    private func makeSource(
        named name: String,
        in directory: URL,
        contents: String = "payload"
    ) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url, options: .atomic)
        return url
    }

    @Test("Moving a temp file into the shelf records the original path")
    func moveFileIntoAssets() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let source = try makeSource(
            named: "move-me.txt",
            in: fixture.workspace.appendingPathComponent("Origin", isDirectory: true)
        )

        let item = try #require(fixture.state.addFile(url: source, mode: .moved))

        #expect(!FileManager.default.fileExists(atPath: source.path))
        #expect(item.ingestMode == .moved)
        #expect(item.originPath == source.standardizedFileURL.path)
        #expect(item.filePath.map { FileManager.default.fileExists(atPath: $0) } == true)
        #expect(item.filePath.map {
            ShelfPluginState.isPath($0, inside: fixture.state.fileStorage.assetsDirectory)
        } == true)

        let persisted = try #require(fixture.state.fileStorage.loadIndex([ShelfFileItem].self))
        #expect(persisted.first?.ingestMode == .moved)
        #expect(persisted.first?.originPath == source.standardizedFileURL.path)
    }

    @Test("A failed move falls back to a link and keeps the original")
    func failedMoveFallsBackToLink() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let source = try makeSource(
            named: "blocked.txt",
            in: fixture.workspace.appendingPathComponent("Origin", isDirectory: true)
        )
        fixture.state.moveHandler = { _, _ in throw CocoaError(.fileWriteNoPermission) }

        let outcome = fixture.state.ingest(urls: [source], mode: .moved)
        let item = try #require(fixture.state.files.first)

        #expect(item.ingestMode == .link)
        #expect(item.originPath == nil)
        #expect(FileManager.default.fileExists(atPath: source.path))
        #expect(outcome.fallbackURLs == [source.standardizedFileURL])
        #expect(outcome.failedURLs.isEmpty)
    }

    @Test("Moved originals escape retention and quota while owned files do not")
    func storagePoliciesProtectMovedOriginals() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let fileStorage = fixture.state.fileStorage
        let old = Date(timeIntervalSinceNow: -8 * 86_400)
        let movedURL = fileStorage.assetsDirectory.appendingPathComponent("moved-old.txt")
        let ownedURL = fileStorage.assetsDirectory.appendingPathComponent("owned-old.txt")
        let largeURL = fileStorage.assetsDirectory.appendingPathComponent("owned-large.bin")
        try Data("moved".utf8).write(to: movedURL)
        try Data("owned".utf8).write(to: ownedURL)
        FileManager.default.createFile(atPath: largeURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: largeURL)
        try handle.truncate(atOffset: 101 * 1024 * 1024)
        try handle.close()

        fixture.state.storage.setCodable(PurahRetentionPeriod.oneHour, forKey: "retentionPeriod")
        fixture.state.storage.setCodable(PurahDiskQuota.mb100, forKey: "diskQuota")
        fileStorage.saveIndex([
            ShelfFileItem(
                id: "moved",
                name: movedURL.lastPathComponent,
                sizeDescription: "5 bytes",
                fileExtension: "txt",
                filePath: movedURL.path,
                timestamp: old,
                ingestMode: .moved,
                originPath: fixture.workspace.appendingPathComponent("Origin/moved-old.txt").path
            ),
            ShelfFileItem(
                id: "owned-old",
                name: ownedURL.lastPathComponent,
                sizeDescription: "5 bytes",
                fileExtension: "txt",
                filePath: ownedURL.path,
                timestamp: old,
                ingestMode: .owned
            ),
            ShelfFileItem(
                id: "owned-large",
                name: largeURL.lastPathComponent,
                sizeDescription: "101 MB",
                fileExtension: "bin",
                filePath: largeURL.path,
                ingestMode: .owned
            )
        ])

        let policyState = ShelfPluginState(
            storage: fixture.state.storage,
            fileStorage: fileStorage
        )

        #expect(policyState.files.map(\.id) == ["moved"])
        #expect(FileManager.default.fileExists(atPath: movedURL.path))
        #expect(!FileManager.default.fileExists(atPath: ownedURL.path))
        #expect(!FileManager.default.fileExists(atPath: largeURL.path))
    }

    @Test("Explicit deletion recycles moved files but permanently deletes owned files")
    func explicitDeletionUsesTrashOnlyForMovedFiles() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let source = try makeSource(
            named: "recycle-me.txt",
            in: fixture.workspace.appendingPathComponent("Origin", isDirectory: true)
        )
        let moved = try #require(fixture.state.addFile(url: source, mode: .moved))
        let movedPath = try #require(moved.filePath)
        let owned = try #require(fixture.state.addDroppedTextSnippet("owned payload"))
        let ownedPath = try #require(owned.filePath)
        let trashDirectory = fixture.workspace.appendingPathComponent("TestTrash", isDirectory: true)
        try FileManager.default.createDirectory(at: trashDirectory, withIntermediateDirectories: true)
        var recycled: [URL] = []
        fixture.state.recycleHandler = { url in
            recycled.append(url)
            try FileManager.default.moveItem(
                at: url,
                to: trashDirectory.appendingPathComponent(url.lastPathComponent)
            )
        }

        fixture.state.removeFile(id: moved.id)
        #expect(recycled.map(\.standardizedFileURL) == [URL(fileURLWithPath: movedPath).standardizedFileURL])
        #expect(!fixture.state.files.contains { $0.id == moved.id })
        #expect(!FileManager.default.fileExists(atPath: movedPath))
        #expect(FileManager.default.fileExists(
            atPath: trashDirectory.appendingPathComponent(URL(fileURLWithPath: movedPath).lastPathComponent).path
        ))

        fixture.state.removeFile(id: owned.id)
        #expect(recycled.count == 1)
        #expect(!fixture.state.files.contains { $0.id == owned.id })
        #expect(!FileManager.default.fileExists(atPath: ownedPath))
    }

    @Test("A moved row survives auto-remove-on-drag")
    func movedRowSurvivesDragOut() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let source = try makeSource(
            named: "keep-me.txt",
            in: fixture.workspace.appendingPathComponent("Keep", isDirectory: true)
        )
        let item = try #require(fixture.state.addFile(url: source, mode: .moved))
        let sandboxPath = try #require(item.filePath)

        let removed = fixture.state.handleDragOutCompleted(id: item.id)

        #expect(removed == false)
        #expect(fixture.state.files.contains { $0.id == item.id })
        // The row is the only thing keeping the file out of the orphan sweep.
        #expect(FileManager.default.fileExists(atPath: sandboxPath))
    }

    @Test("A linked row is still removed on drag-out")
    func linkedRowIsRemovedOnDragOut() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let source = try makeSource(
            named: "link-me.txt",
            in: fixture.workspace.appendingPathComponent("Link", isDirectory: true)
        )
        let item = try #require(fixture.state.addFile(url: source))

        let removed = fixture.state.handleDragOutCompleted(id: item.id)

        #expect(removed)
        #expect(!fixture.state.files.contains { $0.id == item.id })
        // A link only referenced the original, which stays where it was.
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    @Test("Undo restores a moved original and removes its row")
    func undoRestoresOriginal() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let originDirectory = fixture.workspace.appendingPathComponent("Origin", isDirectory: true)
        let source = try makeSource(named: "restore.txt", in: originDirectory, contents: "restore me")
        let item = try #require(fixture.state.addFile(url: source, mode: .moved))
        let sandboxPath = try #require(item.filePath)

        let outcome = fixture.state.undoMove(itemIDs: [item.id])

        #expect(outcome.restoredIDs == [item.id])
        #expect(outcome.failedIDs.isEmpty)
        #expect(try String(contentsOf: source, encoding: .utf8) == "restore me")
        #expect(!FileManager.default.fileExists(atPath: sandboxPath))
        #expect(fixture.state.files.isEmpty)
        #expect(fixture.store._shelfFiles.isEmpty)
    }

    @Test("Undo refuses a missing or occupied origin and keeps the shelf row")
    func undoRefusesUnsafeDestinations() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let missingOrigin = try makeSource(
            named: "missing-origin.txt",
            in: fixture.workspace.appendingPathComponent("MissingOrigin", isDirectory: true)
        )
        let missingItem = try #require(fixture.state.addFile(url: missingOrigin, mode: .moved))
        try FileManager.default.removeItem(at: missingOrigin.deletingLastPathComponent())

        let occupiedOrigin = try makeSource(
            named: "occupied.txt",
            in: fixture.workspace.appendingPathComponent("OccupiedOrigin", isDirectory: true),
            contents: "new file"
        )
        let occupiedItem = try #require(fixture.state.addFile(url: occupiedOrigin, mode: .moved))
        try Data("do not overwrite".utf8).write(to: occupiedOrigin, options: .atomic)

        let outcome = fixture.state.undoMove(itemIDs: [missingItem.id, occupiedItem.id])

        #expect(outcome.restoredIDs.isEmpty)
        #expect(Set(outcome.failedIDs) == [missingItem.id, occupiedItem.id])
        #expect(fixture.state.files.contains { $0.id == missingItem.id })
        #expect(fixture.state.files.contains { $0.id == occupiedItem.id })
        #expect(try String(contentsOf: occupiedOrigin, encoding: .utf8) == "do not overwrite")
        #expect(missingItem.filePath.map { FileManager.default.fileExists(atPath: $0) } == true)
        #expect(occupiedItem.filePath.map { FileManager.default.fileExists(atPath: $0) } == true)
    }

    private final class CountingStorage: PurahPluginStorage, @unchecked Sendable {
        private let base: ScopedPluginStorage
        private let lock = NSLock()
        private var stashedFileWrites = 0

        init(base: ScopedPluginStorage) {
            self.base = base
        }

        var writeCount: Int {
            lock.withLock { stashedFileWrites }
        }

        func string(forKey key: String) -> String? { base.string(forKey: key) }
        func set(_ value: String?, forKey key: String) { base.set(value, forKey: key) }
        func double(forKey key: String) -> Double { base.double(forKey: key) }
        func set(_ value: Double, forKey key: String) { base.set(value, forKey: key) }
        func bool(forKey key: String) -> Bool { base.bool(forKey: key) }
        func set(_ value: Bool, forKey key: String) { base.set(value, forKey: key) }
        func int(forKey key: String) -> Int { base.int(forKey: key) }
        func set(_ value: Int, forKey key: String) { base.set(value, forKey: key) }

        func codable<T: Codable>(forKey key: String, as: T.Type) -> T? {
            base.codable(forKey: key, as: T.self)
        }

        func setCodable<T: Codable>(_ value: T?, forKey key: String) {
            if key == "stashedFiles" {
                lock.withLock { stashedFileWrites += 1 }
            }
            base.setCodable(value, forKey: key)
        }

        func removeObject(forKey key: String) {
            base.removeObject(forKey: key)
        }
    }

    @Test("A second Undo tap is skipped, not reported as a failure")
    func secondUndoIsNotAFailure() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let source = try makeSource(
            named: "twice.txt",
            in: fixture.workspace.appendingPathComponent("Twice", isDirectory: true)
        )
        let item = try #require(fixture.state.addFile(url: source, mode: .moved))

        let first = fixture.state.undoMove(itemIDs: [item.id])
        // The banner is still on screen for a moment, so a double tap must not
        // claim the restore failed when the first tap already did the work.
        let second = fixture.state.undoMove(itemIDs: [item.id])

        #expect(first.restoredIDs == [item.id])
        #expect(first.failedIDs.isEmpty)
        #expect(second.restoredIDs.isEmpty)
        #expect(second.failedIDs.isEmpty)
    }

    @Test("A batch reports each result and writes the shelf mirror once")
    func batchReportsResultsAndUpdatesMirrorOnce() throws {
        let suiteName = "shelf_move_batch_\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("shelf-move-batch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: workspace)
        }

        let storage = CountingStorage(
            base: ScopedPluginStorage(pluginId: "shelf-move-batch", defaults: defaults)
        )
        let fileStorage = PurahPluginFileStorage(
            pluginId: "shelf-move-batch",
            customBaseDirectory: workspace.appendingPathComponent("PluginStorage", isDirectory: true)
        )
        let state = ShelfPluginState(storage: storage, fileStorage: fileStorage)
        let store = PurahWorkspaceStore(userDefaults: defaults)
        state.mount(store: store)

        let good = try makeSource(
            named: "good.txt",
            in: workspace.appendingPathComponent("Origin", isDirectory: true)
        )
        let blocked = try makeSource(
            named: "blocked.txt",
            in: workspace.appendingPathComponent("Origin", isDirectory: true)
        )
        let missing = workspace.appendingPathComponent("Origin/missing.txt")
        state.moveHandler = { source, destination in
            if source.lastPathComponent == "blocked.txt" {
                throw CocoaError(.fileWriteNoPermission)
            }
            try FileManager.default.moveItem(at: source, to: destination)
        }

        let outcome = state.ingest(urls: [good, blocked, missing], mode: .moved)

        #expect(outcome.movedIDs.count == 1)
        #expect(outcome.itemIDs.count == 2)
        #expect(outcome.fallbackURLs == [blocked.standardizedFileURL])
        #expect(outcome.failedURLs == [missing.standardizedFileURL])
        #expect(Set(outcome.itemIDs) == Set(state.files.map(\.id)))
        #expect(store._shelfFiles == state.files)
        #expect(storage.writeCount == 1)
    }

    @Test("A legacy row without ingestMode decodes as a link")
    func legacyRowDefaultsToLink() throws {
        let item = ShelfFileItem(
            name: "legacy.txt",
            sizeDescription: "1 KB",
            fileExtension: "txt",
            filePath: "/tmp/legacy.txt",
            ingestMode: .moved,
            originPath: "/tmp/original.txt"
        )
        var object = try #require(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as? [String: Any]
        )
        object.removeValue(forKey: "ingestMode")
        object.removeValue(forKey: "originPath")

        let decoded = try JSONDecoder().decode(
            ShelfFileItem.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        #expect(decoded.ingestMode == .link)
        #expect(decoded.originPath == nil)
    }
}
