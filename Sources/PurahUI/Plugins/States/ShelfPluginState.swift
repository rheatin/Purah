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
    }

    public func save() {
        storage.setCodable(files, forKey: "stashedFiles")
        storage.setCodable(retentionPeriod, forKey: "retentionPeriod")
        storage.setCodable(diskQuota, forKey: "diskQuota")
        storage.set(autoPrune, forKey: "autoPrune")

        let indexURL = fileStorage.dataDirectory.appendingPathComponent("index.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        if let data = try? encoder.encode(files) {
            try? FileManager.default.createDirectory(at: fileStorage.dataDirectory, withIntermediateDirectories: true)
            try? data.write(to: indexURL, options: .atomic)
        }
    }

    public func addFile(url: URL) {
        let itemId = UUID().uuidString
        let name = url.lastPathComponent
        let ext = url.pathExtension
        let attr = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attr?[.size] as? Int64) ?? 0
        let sizeDesc = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)

        var finalPath: String? = url.path
        if FileManager.default.fileExists(atPath: url.path) {
            if size <= 100_000_000 {
                let destURL = fileStorage.assetsDirectory.appendingPathComponent("\(itemId)_\(name)")
                try? FileManager.default.createDirectory(at: fileStorage.assetsDirectory, withIntermediateDirectories: true)
                if (try? FileManager.default.copyItem(at: url, to: destURL)) != nil {
                    finalPath = destURL.path
                }
            }
        }

        let item = ShelfFileItem(
            id: itemId,
            name: name,
            sizeDescription: sizeDesc,
            fileExtension: ext,
            filePath: finalPath,
            timestamp: Date(),
            isFavorite: false
        )
        files.append(item)
        save()
        boundStore?._shelfFiles.append(item)
    }

    public func addFileItem(_ item: ShelfFileItem) {
        files.append(item)
        save()
        boundStore?._shelfFiles.append(item)
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
