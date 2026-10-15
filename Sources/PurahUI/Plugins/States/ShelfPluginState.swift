// Sources/PurahUI/Plugins/States/ShelfPluginState.swift
import SwiftUI
import AppKit
import Foundation
import Observation
import PurahCore

@Observable
@MainActor
public final class ShelfPluginState: Sendable {
    public var files: [ShelfFileItem]
    public let storage: any PurahPluginStorage
    public let fileStorage: PurahPluginFileStorage
    public var retentionPeriod: PurahRetentionPeriod
    public var diskQuota: PurahDiskQuota
    public var autoPrune: Bool
    public var autoRemoveOnDrag: Bool
    @ObservationIgnored private weak var boundStore: PurahWorkspaceStore?

    public var shelfFiles: [ShelfFileItem] {
        get { files }
        set { files = newValue }
    }

    public init(
        storage: any PurahPluginStorage = ScopedPluginStorage(pluginId: "shelf"),
        fileStorage: PurahPluginFileStorage = PurahPluginFileStorage(pluginId: "shelf")
    ) {
        self.storage = storage
        self.fileStorage = fileStorage
        self.retentionPeriod = storage.codable(forKey: "retentionPeriod", as: PurahRetentionPeriod.self) ?? .days7
        self.diskQuota = storage.codable(forKey: "diskQuota", as: PurahDiskQuota.self) ?? .mb250
        self.autoPrune = storage.string(forKey: "autoPrune") != nil ? storage.bool(forKey: "autoPrune") : true
        self.autoRemoveOnDrag = storage.string(forKey: "autoRemoveOnDrag") != nil ? storage.bool(forKey: "autoRemoveOnDrag") : true

        let indexURL = fileStorage.dataDirectory.appendingPathComponent("index.json")
        if let data = try? Data(contentsOf: indexURL),
           let decoded = try? JSONDecoder().decode([ShelfFileItem].self, from: data) {
            self.files = decoded
        } else if let saved = storage.codable(forKey: "stashedFiles", as: [ShelfFileItem].self) {
            self.files = saved
        } else {
            self.files = Self.defaultFiles()
        }
    }

    public func load() {
        let indexURL = fileStorage.dataDirectory.appendingPathComponent("index.json")
        if let data = try? Data(contentsOf: indexURL),
           let decoded = try? JSONDecoder().decode([ShelfFileItem].self, from: data) {
            self.files = decoded
        } else if let saved = storage.codable(forKey: "stashedFiles", as: [ShelfFileItem].self) {
            self.files = saved
        }
        if let savedRetention = storage.codable(forKey: "retentionPeriod", as: PurahRetentionPeriod.self) {
            self.retentionPeriod = savedRetention
        }
        if let savedQuota = storage.codable(forKey: "diskQuota", as: PurahDiskQuota.self) {
            self.diskQuota = savedQuota
        }
        if storage.string(forKey: "autoPrune") != nil {
            self.autoPrune = storage.bool(forKey: "autoPrune")
        }
        if storage.string(forKey: "autoRemoveOnDrag") != nil {
            self.autoRemoveOnDrag = storage.bool(forKey: "autoRemoveOnDrag")
        }
    }

    public func save() {
        storage.setCodable(files, forKey: "stashedFiles")
        storage.setCodable(retentionPeriod, forKey: "retentionPeriod")
        storage.setCodable(diskQuota, forKey: "diskQuota")
        storage.set(autoPrune, forKey: "autoPrune")
        storage.set(autoRemoveOnDrag, forKey: "autoRemoveOnDrag")

        let indexURL = fileStorage.dataDirectory.appendingPathComponent("index.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        if let data = try? encoder.encode(files) {
            try? FileManager.default.createDirectory(at: fileStorage.dataDirectory, withIntermediateDirectories: true)
            try? data.write(to: indexURL, options: .atomic)
        }
    }

    public func addFile(url: URL) {
        let standardized = url.standardizedFileURL
        let targetPath = standardized.path

        if let existingIndex = files.firstIndex(where: {
            $0.filePath == targetPath || $0.resolvedURL?.standardizedFileURL.path == targetPath
        }) {
            var existingItem = files.remove(at: existingIndex)
            existingItem.timestamp = Date()
            files.insert(existingItem, at: 0)
            save()
            if let boundStore {
                if let boundIndex = boundStore._shelfFiles.firstIndex(where: {
                    $0.filePath == targetPath || $0.resolvedURL?.standardizedFileURL.path == targetPath
                }) {
                    var boundItem = boundStore._shelfFiles.remove(at: boundIndex)
                    boundItem.timestamp = Date()
                    boundStore._shelfFiles.insert(boundItem, at: 0)
                } else {
                    boundStore._shelfFiles.insert(existingItem, at: 0)
                }
            }
            return
        }

        let itemId = UUID().uuidString
        let name = standardized.lastPathComponent
        let ext = standardized.pathExtension
        let attr = try? FileManager.default.attributesOfItem(atPath: targetPath)
        let size = (attr?[.size] as? Int64) ?? 0
        let sizeDesc = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)

        let bookmark = try? standardized.bookmarkData(
            options: [.minimalBookmark],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        let item = ShelfFileItem(
            id: itemId,
            name: name,
            sizeDescription: sizeDesc,
            fileExtension: ext,
            filePath: targetPath,
            bookmarkData: bookmark,
            timestamp: Date(),
            isFavorite: false
        )
        files.insert(item, at: 0)
        save()
        boundStore?._shelfFiles.insert(item, at: 0)
    }

    public func addFileItem(_ item: ShelfFileItem) {
        files.insert(item, at: 0)
        save()
        boundStore?._shelfFiles.insert(item, at: 0)
    }

    /// Removes the item from the shelf after it is dragged out if `autoRemoveOnDrag` is enabled
    /// and the item is not starred (`isFavorite == false`). Never deletes the user's original file on disk!
    public func handleDragOutCompleted(id: String) {
        guard autoRemoveOnDrag else { return }
        guard let item = files.first(where: { $0.id == id }), !item.isFavorite else { return }
        removeFile(id: id)
    }

    /// Removes any item from the shelf whose referenced file no longer exists on disk.
    public func cleanupInvalidItems() {
        let invalidIds = files.filter { item in
            guard item.filePath != nil else { return false }
            let path = item.resolvedURL?.path ?? ""
            return !FileManager.default.fileExists(atPath: path)
        }.map { $0.id }

        if !invalidIds.isEmpty {
            files.removeAll { invalidIds.contains($0.id) }
            save()
            boundStore?._shelfFiles.removeAll { invalidIds.contains($0.id) }
        }
    }

    public func toggleFavorite(id: String) {
        guard let idx = files.firstIndex(where: { $0.id == id }) else { return }
        files[idx].isFavorite.toggle()
        save()
        if let boundIdx = boundStore?._shelfFiles.firstIndex(where: { $0.id == id }) {
            boundStore?._shelfFiles[boundIdx].isFavorite = files[idx].isFavorite
        }
    }

    public func removeFile(id: String) {
        if let item = files.first(where: { $0.id == id }), let path = item.filePath {
            if path.hasPrefix(fileStorage.baseDirectory.path) {
                try? FileManager.default.removeItem(atPath: path)
            }
        }
        files.removeAll { $0.id == id }
        save()
        boundStore?._shelfFiles.removeAll { $0.id == id }
    }

    /// Clears all non-starred stashed files, preserving items with isFavorite == true
    /// under the Star Protection Immunity Rule.
    public func clear() {
        let itemsToRemove = files.filter { !$0.isFavorite }
        for item in itemsToRemove {
            if let path = item.filePath, path.hasPrefix(fileStorage.baseDirectory.path) {
                try? FileManager.default.removeItem(atPath: path)
            }
        }
        files.removeAll { !$0.isFavorite }
        save()
        boundStore?._shelfFiles.removeAll { !$0.isFavorite }
    }

    /// Hard reset clearing all stashed files including favorites.
    public func clearAllIncludingFavorites() {
        for item in files {
            if let path = item.filePath, path.hasPrefix(fileStorage.baseDirectory.path) {
                try? FileManager.default.removeItem(atPath: path)
            }
        }
        files.removeAll()
        save()
        boundStore?._shelfFiles.removeAll()
    }

    /// Prunes expired non-starred items and enforces storage quota.
    public func pruneExpired(now: Date = Date()) {
        guard autoPrune else { return }
        let expiredItems = files.filter { item in
            !item.isFavorite && retentionPeriod.isExpired(timestamp: item.timestamp, now: now)
        }
        for item in expiredItems {
            if let path = item.filePath, path.hasPrefix(fileStorage.baseDirectory.path) {
                try? FileManager.default.removeItem(atPath: path)
            }
        }
        let expiredIds = Set(expiredItems.map { $0.id })
        files.removeAll { expiredIds.contains($0.id) }

        if let maxBytes = diskQuota.maxBytes, fileStorage.diskUsageBytes > maxBytes {
            let nonFavorites = files.filter { !$0.isFavorite }.sorted { $0.timestamp < $1.timestamp }
            for item in nonFavorites {
                if fileStorage.diskUsageBytes <= maxBytes { break }
                if let path = item.filePath, path.hasPrefix(fileStorage.baseDirectory.path) {
                    try? FileManager.default.removeItem(atPath: path)
                }
                files.removeAll { $0.id == item.id }
            }
        }
        save()
        if let boundStore {
            boundStore._shelfFiles = files
        }
    }

    public func mount(store: PurahWorkspaceStore) {
        self.boundStore = store
        if !store._shelfFiles.isEmpty && self.files.isEmpty {
            self.files = store._shelfFiles
        }
    }

    public func unmount(store: PurahWorkspaceStore) {
        save()
        if boundStore === store {
            boundStore = nil
        }
    }

    public static func defaultFiles() -> [ShelfFileItem] {
        [
            ShelfFileItem(name: "macOS_Workflow_Spec.pdf", sizeDescription: "2.4 MB", fileExtension: "pdf"),
            ShelfFileItem(name: "Architecture_Diagram.png", sizeDescription: "4.8 MB", fileExtension: "png")
        ]
    }
}
