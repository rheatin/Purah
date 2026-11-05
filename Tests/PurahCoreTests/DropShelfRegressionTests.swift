// Tests/PurahCoreTests/DropShelfRegressionTests.swift
import Testing
import Foundation
@testable import PurahCore
@testable import PurahUI

@Suite("Drop Shelf Regressions", .serialized)
struct DropShelfRegressionTests {
    @Test("Shelf ownership compares path components instead of a string prefix")
    func shelfPathOwnershipRejectsSiblingDirectories() {
        let base = URL(fileURLWithPath: "/tmp/shelf-images", isDirectory: true)

        #expect(ShelfPluginState.isPath("/tmp/shelf-images/archive.zip", inside: base))
        #expect(!ShelfPluginState.isPath("/tmp/shelf-images-backup/archive.zip", inside: base))
    }

    @Test("A persisted empty shelf stays empty after mount")
    @MainActor
    func persistedEmptyShelfStaysEmpty() throws {
        let suiteName = "DropShelfEmpty-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("drop-shelf-empty-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let storage = ScopedPluginStorage(pluginId: "shelf-regression", defaults: defaults)
        let fileStorage = PurahPluginFileStorage(
            pluginId: "shelf-regression",
            customBaseDirectory: tempDir
        )

        let firstRun = ShelfPluginState(storage: storage, fileStorage: fileStorage)
        firstRun.clearAllIncludingFavorites()

        let reopened = ShelfPluginState(storage: storage, fileStorage: fileStorage)
        #expect(reopened.files.isEmpty)

        let store = PurahWorkspaceStore(userDefaults: defaults)
        #expect(store._shelfFiles.isEmpty)

        reopened.mount(store: store)
        #expect(reopened.files.isEmpty)
        #expect(store._shelfFiles.isEmpty)
    }

    @Test("A corrupt index never lets orphan cleanup delete the assets behind it")
    @MainActor
    func corruptIndexDoesNotDeleteUnreferencedAssets() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("drop-shelf-corrupt-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let storage = ScopedPluginStorage(
            pluginId: "shelf-corrupt-regression-\(UUID().uuidString)"
        )
        let fileStorage = PurahPluginFileStorage(
            pluginId: "shelf-corrupt-regression",
            customBaseDirectory: tempDir
        )
        let assetURL = fileStorage.assetsDirectory.appendingPathComponent("user-content.zip")
        try Data("keep me".utf8).write(to: assetURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -172_800)],
            ofItemAtPath: assetURL.path
        )

        let indexURL = fileStorage.dataDirectory.appendingPathComponent("index.json")
        try Data("not a shelf index".utf8).write(to: indexURL, options: .atomic)

        _ = ShelfPluginState(storage: storage, fileStorage: fileStorage)

        #expect(FileManager.default.fileExists(atPath: assetURL.path))
    }

    @Test("showToast keeps an SF Symbol name out of the message")
    @MainActor
    func showToastDoesNotPrefixTheIconName() throws {
        let suiteName = "DropShelfToast-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = PurahWorkspaceStore(userDefaults: defaults)
        let pod = store.pods[0]
        var warningText: String?
        store.onCapacityWarningToast = { warningText = $0 }

        let context = PurahPluginContext(
            pod: pod,
            edge: .left,
            railWidth: 8,
            slotHeight: 120,
            drawerWidth: 320,
            isExpanded: false,
            isPinned: false,
            accentColor: .purple,
            palette: ThemeManager.shared.palette,
            store: store,
            requestExpand: {},
            requestDismiss: {},
            togglePin: {}
        )

        context.showToast("Created Shelf_Archive_1793.zip", "archivebox.fill")
        #expect(warningText == "Created Shelf_Archive_1793.zip")
    }

    @Test("A shelf-owned asset survives the drag session until the receiver can read it")
    @MainActor
    func dragOutDoesNotDeleteShelfOwnedAssetImmediately() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("drop-shelf-drag-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let state = ShelfPluginState(
            storage: ScopedPluginStorage(pluginId: "shelf-drag-regression-\(UUID().uuidString)"),
            fileStorage: PurahPluginFileStorage(
                pluginId: "shelf-drag-regression",
                customBaseDirectory: tempDir
            )
        )
        state.clearAllIncludingFavorites()

        let archiveURL = state.fileStorage.assetsDirectory
            .appendingPathComponent("Shelf_Archive_1793.zip")
        let payload = Data("zip payload".utf8)
        try payload.write(to: archiveURL, options: .atomic)
        state.addFile(url: archiveURL)

        let item = try #require(state.files.first)
        #expect(item.filePath == archiveURL.standardizedFileURL.path)

        #expect(state.handleDragOutCompleted(id: item.id))
        #expect(state.files.isEmpty)
        #expect(FileManager.default.fileExists(atPath: archiveURL.path))
        #expect(try Data(contentsOf: archiveURL) == payload)
    }
}
