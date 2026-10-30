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
        // "Missing" and "could not be read" are different answers. Collapsing
        // them let a transient read failure (a locked volume, a changed
        // container path) look like an empty collection, and the next insert
        // wrote the near-empty list over a perfectly good index.
        guard FileManager.default.fileExists(atPath: indexURL.path) else { return }
        guard let data = try? Data(contentsOf: indexURL) else {
            quarantineUnreadableIndex()
            return
        }
        guard let decoded = try? JSONDecoder().decode([Item].self, from: data) else {
            quarantineUnreadableIndex()
            return
        }
        self.items = decoded
    }

    /// Moves an index that cannot be decoded out of the way.
    ///
    /// Leaving it in place would mean the next `saveToDisk` writes the empty
    /// list over it, so one added field (or one launch of an older build)
    /// would silently erase the whole collection. A rename costs nothing and
    /// keeps the bytes recoverable.
    private func quarantineUnreadableIndex() {
        let stamp = Int(Date().timeIntervalSince1970)
        let backup = indexURL
            .deletingLastPathComponent()
            .appendingPathComponent("index.corrupt-\(stamp).json")
        do {
            try FileManager.default.moveItem(at: indexURL, to: backup)
            DiagnosticLogger.shared.warn(
                "Storage",
                "\(indexURL.lastPathComponent) could not be decoded; kept as \(backup.lastPathComponent)"
            )
        } catch {
            DiagnosticLogger.shared.warn(
                "Storage",
                "\(indexURL.lastPathComponent) could not be decoded and could not be moved aside: \(error.localizedDescription)"
            )
        }
    }

    public func saveToDisk() {
        // No `.prettyPrinted`: this is machine state, and indentation roughly
        // doubles every write and every later parse.
        if let data = try? JSONEncoder().encode(items) {
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
        return enforceQuota(maxBytes: maxBytes, autoPrune: shouldPrune, onRemoveAssociatedFiles: onRemoveAssociatedFiles)
    }

    /// Byte-budget form of `enforceQuota`, also used by tests so pruning can be
    /// exercised without writing hundreds of megabytes of fixture data.
    @discardableResult
    public func enforceQuota(
        maxBytes: Int64,
        autoPrune: Bool,
        onRemoveAssociatedFiles: ((Item) -> Void)? = nil
    ) -> Int {
        let shouldPrune = autoPrune
        var currentSize = storage.computeDiskUsageBytes()
        guard currentSize > maxBytes else { return 0 }

        var prunedCount = 0

        if shouldPrune {
            // Size is updated by subtraction, not by re-walking the folder.
            // `computeDiskUsageBytes` stats every file, so measuring once per
            // removed item made pruning quadratic in the collection size — a
            // collection 500 items over budget did 500 full walks.
            //
            // What a removal actually frees is the item's own files plus
            // whatever the index lost. Both are measured directly here, so the
            // loop still stops the moment the folder fits.
            while currentSize > maxBytes {
                guard let oldestIdx = items.indices
                    .filter({ !items[$0].isFavorite })
                    .min(by: { items[$0].timestamp < items[$1].timestamp }) else {
                    break // All remaining items are favorited; immune to pruning
                }

                let removed = items.remove(at: oldestIdx)
                prunedCount += 1
                let indexBytesBefore = Self.fileSize(at: indexURL)
                onRemoveAssociatedFiles?(removed)
                saveToDisk()
                let freedFiles = Self.bytesOnDisk(atPaths: removed.assetPaths)
                let freedIndex = indexBytesBefore - Self.fileSize(at: indexURL)
                currentSize = max(0, currentSize - freedFiles - freedIndex)
            }
        }

        if currentSize > maxBytes {
            let curMB = Double(currentSize) / (1024.0 * 1024.0)
            let maxMB = Double(maxBytes) / (1024.0 * 1024.0)
            onQuotaWarning?("⚠️ Storage exceeds \(Int(maxMB))MB (\(String(format: "%.1f", curMB))MB used)")
        }

        return prunedCount
    }

    private static func fileSize(at url: URL) -> Int64 {
        // `resourceValues` caches per URL instance, and this is called on the
        // same `indexURL` before and after the write: it reported the size from
        // before the save, so the freed bytes came out as zero.
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return Int64((attrs?[.size] as? NSNumber)?.int64Value ?? 0)
    }

    private static func bytesOnDisk(atPaths paths: [String]) -> Int64 {
        guard !paths.isEmpty else { return 0 }
        var total: Int64 = 0
        for path in paths {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
               let size = attrs[.size] as? Int64 {
                total += size
            }
        }
        return total
    }
}
