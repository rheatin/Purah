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

    @Test("Shelf retention removes expired files but preserves favorites")
    @MainActor
    func retentionPolicyPreservesFavorites() throws {
        let suiteName = "ShelfPolicyRetention-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("shelf-policy-retention-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let storage = ScopedPluginStorage(pluginId: "shelf-policy", defaults: defaults)
        let fileStorage = PurahPluginFileStorage(pluginId: "shelf-policy", customBaseDirectory: tempDir)
        let oldDate = Date(timeIntervalSinceNow: -8 * 86_400)
        let expiredURL = fileStorage.assetsDirectory.appendingPathComponent("expired.txt")
        let favoriteURL = fileStorage.assetsDirectory.appendingPathComponent("favorite.txt")
        try Data("expired".utf8).write(to: expiredURL)
        try Data("favorite".utf8).write(to: favoriteURL)
        fileStorage.saveIndex([
            ShelfFileItem(
                id: "expired",
                name: expiredURL.lastPathComponent,
                sizeDescription: "7 bytes",
                fileExtension: "txt",
                filePath: expiredURL.path,
                timestamp: oldDate
            ),
            ShelfFileItem(
                id: "favorite",
                name: favoriteURL.lastPathComponent,
                sizeDescription: "8 bytes",
                fileExtension: "txt",
                filePath: favoriteURL.path,
                timestamp: oldDate,
                isFavorite: true
            )
        ])

        let state = ShelfPluginState(storage: storage, fileStorage: fileStorage)

        #expect(state.files.map(\.id) == ["favorite"])
        #expect(!FileManager.default.fileExists(atPath: expiredURL.path))
        #expect(FileManager.default.fileExists(atPath: favoriteURL.path))
    }

    @Test("Shelf quota pruning removes oldest non-favorites first")
    @MainActor
    func quotaPolicyPrunesOldestFirst() throws {
        let suiteName = "ShelfPolicyQuota-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("shelf-policy-quota-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let storage = ScopedPluginStorage(pluginId: "shelf-policy", defaults: defaults)
        storage.setCodable(PurahRetentionPeriod.never, forKey: "retentionPeriod")
        storage.setCodable(PurahDiskQuota.mb100, forKey: "diskQuota")
        let fileStorage = PurahPluginFileStorage(pluginId: "shelf-policy", customBaseDirectory: tempDir)
        let items = try (0..<3).map { index in
            let url = fileStorage.assetsDirectory.appendingPathComponent("quota-\(index).bin")
            FileManager.default.createFile(atPath: url.path, contents: nil)
            let handle = try FileHandle(forWritingTo: url)
            try handle.truncate(atOffset: 40 * 1024 * 1024)
            try handle.close()
            return ShelfFileItem(
                id: "item-\(index)",
                name: url.lastPathComponent,
                sizeDescription: "40 MB",
                fileExtension: "bin",
                filePath: url.path,
                timestamp: Date(timeIntervalSinceNow: TimeInterval(index))
            )
        }
        fileStorage.saveIndex(items)

        let state = ShelfPluginState(storage: storage, fileStorage: fileStorage)

        #expect(state.files.map(\.id) == ["item-1", "item-2"])
        #expect(!FileManager.default.fileExists(atPath: items[0].filePath!))
        #expect(FileManager.default.fileExists(atPath: items[1].filePath!))
        #expect(FileManager.default.fileExists(atPath: items[2].filePath!))
    }

    @Test("Shelf quota pruning does nothing when automatic pruning is disabled")
    @MainActor
    func quotaPolicyRespectsAutoPruneOff() throws {
        let suiteName = "ShelfPolicyDisabled-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("shelf-policy-disabled-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let storage = ScopedPluginStorage(pluginId: "shelf-policy", defaults: defaults)
        storage.setCodable(PurahRetentionPeriod.never, forKey: "retentionPeriod")
        storage.setCodable(PurahDiskQuota.mb100, forKey: "diskQuota")
        storage.set(false, forKey: "autoPrune")
        let fileStorage = PurahPluginFileStorage(pluginId: "shelf-policy", customBaseDirectory: tempDir)
        let items = try (0..<3).map { index in
            let url = fileStorage.assetsDirectory.appendingPathComponent("keep-\(index).bin")
            FileManager.default.createFile(atPath: url.path, contents: nil)
            let handle = try FileHandle(forWritingTo: url)
            try handle.truncate(atOffset: 40 * 1024 * 1024)
            try handle.close()
            return ShelfFileItem(
                id: "keep-\(index)",
                name: url.lastPathComponent,
                sizeDescription: "40 MB",
                fileExtension: "bin",
                filePath: url.path,
                timestamp: Date(timeIntervalSinceNow: TimeInterval(index))
            )
        }
        fileStorage.saveIndex(items)

        let state = ShelfPluginState(storage: storage, fileStorage: fileStorage)

        #expect(Set(state.files.map(\.id)) == Set(["keep-0", "keep-1", "keep-2"]))
        for item in items {
            #expect(FileManager.default.fileExists(atPath: item.filePath!))
        }
    }

    @Test("Shelf quota never prunes entries outside its sandbox")
    @MainActor
    func quotaPolicyIgnoresExternalFiles() throws {
        let suiteName = "ShelfPolicyExternalQuota-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("shelf-policy-external-quota-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let storage = ScopedPluginStorage(pluginId: "shelf-policy", defaults: defaults)
        storage.setCodable(PurahRetentionPeriod.never, forKey: "retentionPeriod")
        storage.setCodable(PurahDiskQuota.mb100, forKey: "diskQuota")
        let fileStorage = PurahPluginFileStorage(pluginId: "shelf-policy", customBaseDirectory: tempDir)

        let externalURL = tempDir.appendingPathComponent("external-old.bin")
        FileManager.default.createFile(atPath: externalURL.path, contents: nil)
        let externalHandle = try FileHandle(forWritingTo: externalURL)
        try externalHandle.truncate(atOffset: 200 * 1024 * 1024)
        try externalHandle.close()

        let ownedURLs = try (0..<2).map { index in
            let url = fileStorage.assetsDirectory.appendingPathComponent("owned-\(index).bin")
            FileManager.default.createFile(atPath: url.path, contents: nil)
            let handle = try FileHandle(forWritingTo: url)
            try handle.truncate(atOffset: 80 * 1024 * 1024)
            try handle.close()
            return url
        }
        fileStorage.saveIndex([
            ShelfFileItem(
                id: "external",
                name: externalURL.lastPathComponent,
                sizeDescription: "200 MB",
                fileExtension: "bin",
                filePath: externalURL.path,
                timestamp: Date(timeIntervalSinceNow: -300)
            ),
            ShelfFileItem(
                id: "owned-older",
                name: ownedURLs[0].lastPathComponent,
                sizeDescription: "80 MB",
                fileExtension: "bin",
                filePath: ownedURLs[0].path,
                timestamp: Date(timeIntervalSinceNow: -200)
            ),
            ShelfFileItem(
                id: "owned-newer",
                name: ownedURLs[1].lastPathComponent,
                sizeDescription: "80 MB",
                fileExtension: "bin",
                filePath: ownedURLs[1].path,
                timestamp: Date(timeIntervalSinceNow: -100)
            )
        ])

        let state = ShelfPluginState(storage: storage, fileStorage: fileStorage)

        #expect(state.files.contains(where: { $0.id == "external" }))
        #expect(FileManager.default.fileExists(atPath: externalURL.path))
        #expect(!state.files.contains(where: { $0.id == "owned-older" }))
        #expect(state.files.contains(where: { $0.id == "owned-newer" }))
    }

    @Test("Shelf quota counts only bytes owned inside its sandbox")
    @MainActor
    func quotaPolicyDoesNotCountExternalFiles() throws {
        let suiteName = "ShelfPolicyExternalSize-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("shelf-policy-external-size-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let storage = ScopedPluginStorage(pluginId: "shelf-policy", defaults: defaults)
        storage.setCodable(PurahRetentionPeriod.never, forKey: "retentionPeriod")
        storage.setCodable(PurahDiskQuota.mb100, forKey: "diskQuota")
        let fileStorage = PurahPluginFileStorage(pluginId: "shelf-policy", customBaseDirectory: tempDir)

        let externalURL = tempDir.appendingPathComponent("external-large.bin")
        FileManager.default.createFile(atPath: externalURL.path, contents: nil)
        let externalHandle = try FileHandle(forWritingTo: externalURL)
        try externalHandle.truncate(atOffset: 200 * 1024 * 1024)
        try externalHandle.close()

        let ownedURL = fileStorage.assetsDirectory.appendingPathComponent("owned-small.bin")
        try Data("small".utf8).write(to: ownedURL)
        fileStorage.saveIndex([
            ShelfFileItem(
                id: "external",
                name: externalURL.lastPathComponent,
                sizeDescription: "200 MB",
                fileExtension: "bin",
                filePath: externalURL.path,
                timestamp: Date(timeIntervalSinceNow: -100)
            ),
            ShelfFileItem(
                id: "owned",
                name: ownedURL.lastPathComponent,
                sizeDescription: "5 bytes",
                fileExtension: "bin",
                filePath: ownedURL.path,
                timestamp: Date()
            )
        ])

        let state = ShelfPluginState(storage: storage, fileStorage: fileStorage)

        #expect(Set(state.files.map(\.id)) == Set(["external", "owned"]))
        #expect(FileManager.default.fileExists(atPath: externalURL.path))
        #expect(FileManager.default.fileExists(atPath: ownedURL.path))
    }

    @Test("Shelf retention removes external rows without deleting their originals")
    @MainActor
    func retentionPolicyLeavesExternalFilesOnDisk() throws {
        let suiteName = "ShelfPolicyExternalRetention-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("shelf-policy-external-retention-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let storage = ScopedPluginStorage(pluginId: "shelf-policy", defaults: defaults)
        let fileStorage = PurahPluginFileStorage(pluginId: "shelf-policy", customBaseDirectory: tempDir)
        let oldDate = Date(timeIntervalSinceNow: -8 * 86_400)
        let externalURL = tempDir.appendingPathComponent("external-keep.txt")
        let ownedURL = fileStorage.assetsDirectory.appendingPathComponent("owned-expired.txt")
        try Data("external".utf8).write(to: externalURL)
        try Data("owned".utf8).write(to: ownedURL)
        fileStorage.saveIndex([
            ShelfFileItem(
                id: "external",
                name: externalURL.lastPathComponent,
                sizeDescription: "8 bytes",
                fileExtension: "txt",
                filePath: externalURL.path,
                timestamp: oldDate
            ),
            ShelfFileItem(
                id: "owned",
                name: ownedURL.lastPathComponent,
                sizeDescription: "5 bytes",
                fileExtension: "txt",
                filePath: ownedURL.path,
                timestamp: oldDate
            )
        ])

        let state = ShelfPluginState(storage: storage, fileStorage: fileStorage)

        #expect(state.files.isEmpty)
        #expect(FileManager.default.fileExists(atPath: externalURL.path))
        #expect(!FileManager.default.fileExists(atPath: ownedURL.path))
    }
}
