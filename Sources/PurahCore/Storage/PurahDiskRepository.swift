// Sources/PurahCore/Storage/PurahDiskRepository.swift
import Foundation

/// Generic atomic disk repository for collections of PurahStorableItems.
/// Provides automatic JSON persistence, expiration cleanup, disk quota pruning,
/// and strict pin protection (pinned items are immune to auto-cleanup).
@MainActor
public final class PurahDiskRepository<Item: PurahStorableItem>: Sendable {
    public let storage: PurahPluginFileStorage
    public let indexURL: URL
    public private(set) var items: [Item] = []

    public var retentionPeriod: PurahRetentionPeriod = .sevenDays
    public var diskQuota: PurahDiskQuota = .mb500
    public var autoPruneOnQuota: Bool = true
    public var onQuotaWarning: ((String) -> Void)?

    public init(
        pluginId: String,
        customStorage: PurahPluginFileStorage? = nil,
        retentionPeriod: PurahRetentionPeriod = .sevenDays,
        diskQuota: PurahDiskQuota = .mb500,
        autoPruneOnQuota: Bool = true
    ) {
        let fileStorage = customStorage ?? PurahPluginFileStorage(pluginId: pluginId)
        self.storage = fileStorage
        self.indexURL = fileStorage.rootDirectory.appendingPathComponent("index.json")
        self.retentionPeriod = retentionPeriod
        self.diskQuota = diskQuota
        self.autoPruneOnQuota = autoPruneOnQuota
        loadFromDisk()
    }

    public func loadFromDisk() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([Item].self, from: data) else {
            return
        }
        self.items = decoded
    }

    public func saveToDisk() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        if let data = try? encoder.encode(items) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }

    public func insert(_ item: Item, at index: Int = 0) {
        items.insert(item, at: index)
        cleanExpired()
        enforceQuota()
        saveToDisk()
    }

    public func append(_ item: Item) {
        items.append(item)
        cleanExpired()
        enforceQuota()
        saveToDisk()
    }

    public func update(_ item: Item) {
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx] = item
            saveToDisk()
        } else {
            insert(item)
        }
    }

    public func toggleFavorite(id: String) {
        if let idx = items.firstIndex(where: { $0.id == id }) {
            items[idx].isFavorite.toggle()
            saveToDisk()
        }
    }

    public func togglePin(id: String) {
        toggleFavorite(id: id)
    }

    public func moveItem(from sourceIndex: Int, to destinationIndex: Int) {
        guard items.indices.contains(sourceIndex),
              items.indices.contains(destinationIndex),
              sourceIndex != destinationIndex else { return }
        let item = items.remove(at: sourceIndex)
        items.insert(item, at: destinationIndex)
        saveToDisk()
    }

    public func remove(id: String, onRemoveAssociatedFiles: ((Item) -> Void)? = nil) {
        if let idx = items.firstIndex(where: { $0.id == id }) {
            let removed = items.remove(at: idx)
            onRemoveAssociatedFiles?(removed)
            saveToDisk()
        }
    }

    public func clearAll(keepFavorites: Bool = true, onRemoveAssociatedFiles: ((Item) -> Void)? = nil) {
        let toRemove = keepFavorites ? items.filter { !$0.isFavorite } : items
        for item in toRemove {
            onRemoveAssociatedFiles?(item)
        }
        items = keepFavorites ? items.filter(\.isFavorite) : []
        saveToDisk()
    }

    public func clearAll(keepPinned: Bool) {
        clearAll(keepFavorites: keepPinned, onRemoveAssociatedFiles: nil)
    }

    @discardableResult
    public func cleanExpired(
        retention: PurahRetentionPeriod? = nil,
        now: Date = Date(),
        onRemoveAssociatedFiles: ((Item) -> Void)? = nil
    ) -> Int {
        let period = retention ?? self.retentionPeriod
        guard period != .never else { return 0 }

        var removedCount = 0
        var kept: [Item] = []

        for item in items {
            // STRICT STAR IMMUNITY: Favorited items are never deleted by expiration cleanup
            if item.isFavorite {
                kept.append(item)
            } else if period.isExpired(timestamp: item.timestamp, now: now) {
                removedCount += 1
                onRemoveAssociatedFiles?(item)
            } else {
                kept.append(item)
            }
        }

        if removedCount > 0 {
            items = kept
            saveToDisk()
        }
        return removedCount
    }

    @discardableResult
    public func enforceQuota(
        quota: PurahDiskQuota? = nil,
        autoPrune: Bool? = nil,
        onRemoveAssociatedFiles: ((Item) -> Void)? = nil
    ) -> Int {
        let activeQuota = quota ?? self.diskQuota
        let shouldPrune = autoPrune ?? self.autoPruneOnQuota
        guard let maxBytes = activeQuota.maxBytes else { return 0 }

        var currentSize = storage.computeDiskUsageBytes()
        guard currentSize > maxBytes else { return 0 }

        var prunedCount = 0

        if shouldPrune {
            while currentSize > maxBytes {
                guard let oldestIdx = items.indices
                    .filter({ !items[$0].isFavorite })
                    .min(by: { items[$0].timestamp < items[$1].timestamp }) else {
                    break // All remaining items are favorited; immune to pruning
                }

                let removed = items.remove(at: oldestIdx)
                prunedCount += 1
                onRemoveAssociatedFiles?(removed)
                currentSize = storage.computeDiskUsageBytes()
            }

            if prunedCount > 0 {
                saveToDisk()
            }
        }

        if currentSize > maxBytes {
            let curMB = Double(currentSize) / (1024.0 * 1024.0)
            let maxMB = Double(maxBytes) / (1024.0 * 1024.0)
            onQuotaWarning?("⚠️ Storage exceeds \(Int(maxMB))MB (\(String(format: "%.1f", curMB))MB used)")
        }

        return prunedCount
    }
}
