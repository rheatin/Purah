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
    public var selectedFileIds: Set<String> = []
    public var lastSelectedFileId: String? = nil
    public let storage: any PurahPluginStorage
    public let fileStorage: PurahPluginFileStorage
    public var retentionPeriod: PurahRetentionPeriod
    public var diskQuota: PurahDiskQuota
    public var autoPrune: Bool
    public var autoRemoveOnDrag: Bool
    @ObservationIgnored private weak var boundStore: PurahWorkspaceStore?

    public var selectedFiles: [ShelfFileItem] {
        files.filter { selectedFileIds.contains($0.id) }
    }

    public func isSelected(id: String) -> Bool {
        selectedFileIds.contains(id)
    }

    public func toggleSelection(id: String) {
        if selectedFileIds.contains(id) {
            selectedFileIds.remove(id)
        } else if files.contains(where: { $0.id == id }) {
            selectedFileIds.insert(id)
        }
        lastSelectedFileId = id
    }

    public func selectSingle(id: String) {
        guard files.contains(where: { $0.id == id }) else { return }
        selectedFileIds = [id]
        lastSelectedFileId = id
    }

    public func selectRange(to id: String) {
        guard let targetIdx = files.firstIndex(where: { $0.id == id }) else { return }
        if let anchorId = lastSelectedFileId,
           let anchorIdx = files.firstIndex(where: { $0.id == anchorId }) {
            let lower = min(anchorIdx, targetIdx)
            let upper = max(anchorIdx, targetIdx)
            for idx in lower...upper {
                selectedFileIds.insert(files[idx].id)
            }
        } else {
            selectedFileIds.insert(id)
        }
        lastSelectedFileId = id
    }

    public func selectAll() {
        selectedFileIds = Set(files.map(\.id))
    }

    public func clearSelection() {
        selectedFileIds.removeAll()
        lastSelectedFileId = nil
    }

    public func updateMarqueeSelection(intersectingIds: Set<String>) {
        let validIds = Set(files.map(\.id))
        selectedFileIds = intersectingIds.intersection(validIds)
    }

    public func filesForDrag(startingFrom primaryFile: ShelfFileItem) -> [ShelfFileItem] {
        if selectedFileIds.contains(primaryFile.id) && selectedFileIds.count > 1 {
            return selectedFiles
        }
        return [primaryFile]
    }

    public func filesForBatchExport() -> [ShelfFileItem] {
        if !selectedFileIds.isEmpty {
            return selectedFiles
        }
        return files
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

        if let decoded = fileStorage.loadIndex([ShelfFileItem].self) {
            self.files = decoded
        } else if let saved = storage.codable(forKey: "stashedFiles", as: [ShelfFileItem].self) {
            self.files = saved
        } else {
            self.files = Self.defaultFiles()
        }
    }

    public func load() {
        if let decoded = fileStorage.loadIndex([ShelfFileItem].self) {
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

        fileStorage.saveIndex(files)
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

    private func uniqueAssetURL(for fileName: String) -> URL {
        try? FileManager.default.createDirectory(at: fileStorage.assetsDirectory, withIntermediateDirectories: true)
        let candidate = fileStorage.assetsDirectory.appendingPathComponent(fileName)
        if !FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }
        let baseName = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        let suffix = UUID().uuidString.prefix(4)
        let uniqueName = ext.isEmpty ? "\(baseName)_\(suffix)" : "\(baseName)_\(suffix).\(ext)"
        return fileStorage.assetsDirectory.appendingPathComponent(uniqueName)
    }

    /// Compresses the specified files (or `filesForBatchExport()` when nil) into a `.zip` archive
    /// inside `fileStorage.assetsDirectory`, adds the archive to `files`, and selects it.
    @discardableResult
    public func compressFilesToZip(filesToZip: [ShelfFileItem]? = nil) -> ShelfFileItem? {
        let targets = filesToZip ?? filesForBatchExport()
        guard !targets.isEmpty else { return nil }

        try? FileManager.default.createDirectory(at: fileStorage.assetsDirectory, withIntermediateDirectories: true)

        let zipName = targets.count == 1
            ? "\(targets[0].name).zip"
            : "Shelf_Archive_\(Int(Date().timeIntervalSince1970)).zip"
        let destZipURL = fileStorage.assetsDirectory.appendingPathComponent(zipName)
        try? FileManager.default.removeItem(at: destZipURL)

        var sourcePaths: [String] = []
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        for item in targets {
            if let resolved = item.resolvedURL, FileManager.default.fileExists(atPath: resolved.path) {
                sourcePaths.append(resolved.path)
            } else {
                let fallbackURL = tempDir.appendingPathComponent(item.name)
                if !FileManager.default.fileExists(atPath: fallbackURL.path) {
                    let placeholder = "Purah DropShelf placeholder file: \(item.name)\nSize: \(item.sizeDescription)\nCreated at: \(item.timestamp)"
                    try? placeholder.write(to: fallbackURL, atomically: true, encoding: .utf8)
                }
                if FileManager.default.fileExists(atPath: fallbackURL.path) {
                    sourcePaths.append(fallbackURL.path)
                }
            }
        }
        guard !sourcePaths.isEmpty else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-j", "-q", destZipURL.path] + sourcePaths
        try? process.run()
        process.waitUntilExit()

        if !FileManager.default.fileExists(atPath: destZipURL.path) {
            let fallbackProcess = Process()
            fallbackProcess.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            fallbackProcess.arguments = ["-r", "-q", destZipURL.path] + sourcePaths
            try? fallbackProcess.run()
            fallbackProcess.waitUntilExit()
        }

        guard FileManager.default.fileExists(atPath: destZipURL.path) else { return nil }

        addFile(url: destZipURL)
        let standardizedZipPath = destZipURL.standardizedFileURL.path
        if let newZipItem = files.first(where: {
            $0.filePath == standardizedZipPath || $0.name == destZipURL.lastPathComponent
        }) {
            selectSingle(id: newZipItem.id)
            return newZipItem
        }
        return nil
    }

    /// Writes dropped image data to `fileStorage.assetsDirectory` and stashes it on the shelf.
    @discardableResult
    public func addDroppedImageData(_ data: Data, suggestedName: String? = nil) -> ShelfFileItem? {
        guard !data.isEmpty else { return nil }
        try? FileManager.default.createDirectory(at: fileStorage.assetsDirectory, withIntermediateDirectories: true)

        let baseName: String
        if let suggestedName, !suggestedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let trimmed = suggestedName.trimmingCharacters(in: .whitespacesAndNewlines)
            baseName = (trimmed as NSString).pathExtension.isEmpty ? "\(trimmed).png" : trimmed
        } else {
            baseName = "Image_\(Int(Date().timeIntervalSince1970)).png"
        }

        let fileURL = uniqueAssetURL(for: baseName)
        guard (try? data.write(to: fileURL, options: .atomic)) != nil else { return nil }
        addFile(url: fileURL)
        let standardizedPath = fileURL.standardizedFileURL.path
        return files.first(where: { $0.filePath == standardizedPath })
    }

    /// Writes a dropped text snippet as a UTF-8 `.txt` file in `fileStorage.assetsDirectory` and stashes it.
    @discardableResult
    public func addDroppedTextSnippet(_ text: String) -> ShelfFileItem? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = text.data(using: .utf8) else { return nil }
        try? FileManager.default.createDirectory(at: fileStorage.assetsDirectory, withIntermediateDirectories: true)

        let baseName = "Snippet_\(Int(Date().timeIntervalSince1970)).txt"
        let fileURL = uniqueAssetURL(for: baseName)
        guard (try? data.write(to: fileURL, options: .atomic)) != nil else { return nil }
        addFile(url: fileURL)
        let standardizedPath = fileURL.standardizedFileURL.path
        return files.first(where: { $0.filePath == standardizedPath })
    }

    /// Writes a dropped web link as a standard macOS `.webloc` plist file in `fileStorage.assetsDirectory` and stashes it.
    @discardableResult
    public func addDroppedWebLink(_ url: URL) -> ShelfFileItem? {
        try? FileManager.default.createDirectory(at: fileStorage.assetsDirectory, withIntermediateDirectories: true)

        let hostPart = (url.host ?? "Link").replacingOccurrences(of: "/", with: "_")
        let baseName = "\(hostPart)_\(Int(Date().timeIntervalSince1970)).webloc"
        let fileURL = uniqueAssetURL(for: baseName)

        let escapedURL = url.absoluteString
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        let weblocPlist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        \t<key>URL</key>
        \t<string>\(escapedURL)</string>
        </dict>
        </plist>
        """
        guard let data = weblocPlist.data(using: .utf8),
              (try? data.write(to: fileURL, options: .atomic)) != nil else { return nil }
        addFile(url: fileURL)
        let standardizedPath = fileURL.standardizedFileURL.path
        return files.first(where: { $0.filePath == standardizedPath })
    }

    /// Removes the item from the shelf after it is dragged out if `autoRemoveOnDrag` is enabled
    /// and the item is not starred (`isFavorite == false`). Never deletes the user's original file on disk!
    ///
    /// Returns `true` when the item was actually removed.
    @discardableResult
    public func handleDragOutCompleted(id: String) -> Bool {
        guard autoRemoveOnDrag else { return false }
        guard let item = files.first(where: { $0.id == id }), !item.isFavorite else { return false }
        removeFile(id: id)
        return true
    }

    /// Removes a batch of items from the shelf after they are dragged out or exported if `autoRemoveOnDrag` is enabled,
    /// while strictly preserving any starred (`isFavorite == true`) items.
    public func handleBatchDragOutCompleted(ids: [String]) {
        guard autoRemoveOnDrag else { return }
        for id in ids {
            if let item = files.first(where: { $0.id == id }), !item.isFavorite {
                removeFile(id: id)
            }
            selectedFileIds.remove(id)
            if lastSelectedFileId == id {
                lastSelectedFileId = nil
            }
        }
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
            for id in invalidIds {
                selectedFileIds.remove(id)
                if lastSelectedFileId == id {
                    lastSelectedFileId = nil
                }
            }
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
        selectedFileIds.remove(id)
        if lastSelectedFileId == id {
            lastSelectedFileId = nil
        }
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
            selectedFileIds.remove(item.id)
            if lastSelectedFileId == item.id {
                lastSelectedFileId = nil
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
        selectedFileIds.removeAll()
        lastSelectedFileId = nil
        save()
        boundStore?._shelfFiles.removeAll()
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
