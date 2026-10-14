// Tests/PurahCoreTests/PurahStorageEngineTests.swift
import Testing
import Foundation
@testable import PurahCore

struct MockStorableItem: PurahStorableItem, Equatable {
    let id: String
    let title: String
    let timestamp: Date
    var isFavorite: Bool
}

@Suite("Purah Storage Engine & Disk Repository Tests")
@MainActor
struct PurahStorageEngineTests {
    @Test("PurahPluginFileStorage creates isolated sandbox and computes disk usage")
    func testFileStorageSandboxCreation() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("purah_storage_test_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileStorage = PurahPluginFileStorage(pluginId: "test-plugin", customBaseDirectory: tempDir)
        #expect(FileManager.default.fileExists(atPath: fileStorage.dataDirectory.path))
        #expect(FileManager.default.fileExists(atPath: fileStorage.cacheDirectory.path))

        // Write a test data file (10 KB)
        let sampleData = Data(repeating: 0x41, count: 10240)
        let fileURL = fileStorage.dataDirectory.appendingPathComponent("sample.bin")
        try? sampleData.write(to: fileURL)

        #expect(fileStorage.computeDiskUsageBytes() >= 10240)
        #expect(fileStorage.diskUsageFormatted.contains("KB"))

        // Clear all excluding the sample file
        fileStorage.clearAll(excluding: [fileURL])
        #expect(FileManager.default.fileExists(atPath: fileURL.path))

        // Clear all without exclusions
        fileStorage.clearAll()
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test("PurahDiskRepository preserves pinned items against expiration cleanup and quota pruning")
    func testDiskRepositoryPinImmunityAndQuota() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("purah_repo_test_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let storage = PurahPluginFileStorage(pluginId: "repo-plugin", customBaseDirectory: tempDir)
        let repo = PurahDiskRepository<MockStorableItem>(
            pluginId: "repo-plugin",
            customStorage: storage,
            retentionPeriod: .never,
            diskQuota: .mb100
        )

        let now = Date()
        let freshItem = MockStorableItem(id: "item-1", title: "Fresh", timestamp: now, isFavorite: false)
        let oldUnstarred = MockStorableItem(id: "item-2", title: "Old Unstarred", timestamp: now.addingTimeInterval(-86400 * 10), isFavorite: false)
        let oldStarred = MockStorableItem(id: "item-3", title: "Old Starred", timestamp: now.addingTimeInterval(-86400 * 10), isFavorite: true)

        repo.append(freshItem)
        repo.append(oldUnstarred)
        repo.append(oldStarred)
        #expect(repo.items.count == 3)

        // Verify Reordering
        repo.moveItem(from: 0, to: 2)
        #expect(repo.items[2].id == freshItem.id)

        // Verify Star Toggling
        repo.toggleFavorite(id: "item-1")
        #expect(repo.items.first(where: { $0.id == "item-1" })?.isFavorite == true)
        repo.toggleFavorite(id: "item-1")
        #expect(repo.items.first(where: { $0.id == "item-1" })?.isFavorite == false)

        // Verify Expiration: with 7 days retention, oldUnstarred purged, oldStarred strictly immune!
        repo.retentionPeriod = .sevenDays
        var removedIds: [String] = []
        let removedCount = repo.cleanExpired(retention: .sevenDays, now: now) { item in
            removedIds.append(item.id)
        }
        #expect(removedCount == 1)
        #expect(removedIds == ["item-2"])
        #expect(repo.items.contains { $0.id == "item-1" })
        #expect(repo.items.contains { $0.id == "item-3" }, "Starred item MUST be strictly immune to expiration cleanup")

        // Reload from disk to verify atomic JSON persistence
        let reloadedRepo = PurahDiskRepository<MockStorableItem>(
            pluginId: "repo-plugin",
            customStorage: storage,
            retentionPeriod: .never
        )
        #expect(reloadedRepo.items.count == 2)
        #expect(reloadedRepo.items.contains { $0.id == "item-3" && $0.isFavorite })
    }
}
