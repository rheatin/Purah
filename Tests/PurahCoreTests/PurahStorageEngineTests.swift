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

    /// Quota pruning must stop as soon as the folder fits again.
    ///
    /// The loop used to re-measure disk usage only through `computeDiskUsageBytes`
    /// *before* the index was rewritten, so the measured size never shrank and
    /// every non-favourite item (and its files) was pruned.
    @Test("Quota pruning stops at the quota instead of deleting everything")
    func testQuotaPruningStopsAtQuota() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("purah_quota_test_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let storage = PurahPluginFileStorage(pluginId: "quota-plugin", customBaseDirectory: tempDir)
        let repo = PurahDiskRepository<MockStorableItem>(
            pluginId: "quota-plugin",
            customStorage: storage,
            retentionPeriod: .never,
            diskQuota: .mb500
        )

        // Each item is padded so the folder clearly exceeds the byte budget.
        let now = Date()
        for index in 0..<8 {
            let padding = String(repeating: "x", count: 20_000)
            repo.append(MockStorableItem(
                id: "item-\(index)",
                title: padding,
                timestamp: now.addingTimeInterval(Double(-index)),
                isFavorite: false
            ))
        }
        #expect(repo.items.count == 8)

        let budget = storage.computeDiskUsageBytes() / 2
        let pruned = repo.enforceQuota(maxBytes: budget, autoPrune: true)

        #expect(pruned > 0, "the fixture must exceed the budget")
        #expect(pruned < 8, "pruning must stop once the folder fits, not delete every item")
        #expect(!repo.items.isEmpty)
        #expect(storage.computeDiskUsageBytes() <= budget,
                "the folder must be back under budget after pruning")
    }

    @Test("Quota pruning never removes starred items")
    func testQuotaPruningKeepsStarredItems() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("purah_quota_star_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let storage = PurahPluginFileStorage(pluginId: "quota-star-plugin", customBaseDirectory: tempDir)
        let repo = PurahDiskRepository<MockStorableItem>(
            pluginId: "quota-star-plugin",
            customStorage: storage,
            retentionPeriod: .never,
            diskQuota: .mb500
        )

        let now = Date()
        for index in 0..<6 {
            let padding = String(repeating: "x", count: 20_000)
            repo.append(MockStorableItem(
                id: "item-\(index)",
                title: padding,
                timestamp: now.addingTimeInterval(Double(-index)),
                isFavorite: index == 5
            ))
        }

        _ = repo.enforceQuota(maxBytes: storage.computeDiskUsageBytes() / 2, autoPrune: true)

        #expect(repo.items.contains { $0.id == "item-5" && $0.isFavorite },
                "the Star Protection Immunity Rule must survive quota pruning")
    }
}
