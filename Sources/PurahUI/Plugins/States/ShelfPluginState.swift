// Sources/PurahUI/Plugins/States/ShelfPluginState.swift
import SwiftUI
import AppKit
import Foundation
import Observation
import PurahCore

public struct ShelfIngestOutcome: Sendable, Equatable {
    public var itemIDs: [String] = []
    public var movedIDs: [String] = []
    public var fallbackURLs: [URL] = []
    public var failedURLs: [URL] = []

    public var didIngest: Bool { !itemIDs.isEmpty }

    public init(
        itemIDs: [String] = [],
        movedIDs: [String] = [],
        fallbackURLs: [URL] = [],
        failedURLs: [URL] = []
    ) {
        self.itemIDs = itemIDs
        self.movedIDs = movedIDs
        self.fallbackURLs = fallbackURLs
        self.failedURLs = failedURLs
    }
}

public struct ShelfUndoOutcome: Sendable, Equatable {
    public var restoredIDs: [String]
    public var failedIDs: [String]

    public init(restoredIDs: [String] = [], failedIDs: [String] = []) {
        self.restoredIDs = restoredIDs
        self.failedIDs = failedIDs
    }
}

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
    /// Injection seams keep file movement and Trash removal testable without
    /// touching the person's real files or Trash.
    @ObservationIgnored public var moveHandler: (URL, URL) throws -> Void
    @ObservationIgnored public var recycleHandler: (URL) throws -> Void
    @ObservationIgnored private weak var boundStore: PurahWorkspaceStore?

    public var selectedFiles: [ShelfFileItem] {
        files.filter { selectedFileIds.contains($0.id) }
    }

    /// Ownership is a path-component relation, not a string prefix:
    /// `/tmp/shelf-images-backup` is not inside `/tmp/shelf-images`.
    nonisolated static func isPath(_ path: String, inside baseDirectory: URL) -> Bool {
        let pathComponents = URL(fileURLWithPath: path).standardizedFileURL.pathComponents
        let baseComponents = baseDirectory.standardizedFileURL.pathComponents
        guard pathComponents.count > baseComponents.count else { return false }
        return pathComponents.prefix(baseComponents.count).elementsEqual(baseComponents)
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
        self.moveHandler = { source, destination in
            try FileManager.default.moveItem(at: source, to: destination)
        }
        self.recycleHandler = { url in
            var resultingURL: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
        }

        let hasAuthoritativeIndex: Bool
        if let decoded = fileStorage.loadIndex([ShelfFileItem].self) {
            self.files = decoded
            hasAuthoritativeIndex = true
        } else if let saved = storage.codable(forKey: "stashedFiles", as: [ShelfFileItem].self) {
            self.files = saved
            hasAuthoritativeIndex = true
        } else {
            self.files = []
            // A missing/corrupt index may still have live assets behind it.
            // Without a decoded reference list, deleting "unreferenced" files
            // could destroy the very content the index was meant to describe.
            hasAuthoritativeIndex = false
        }
        if hasAuthoritativeIndex {
            cleanupOrphanedAssets()
            if enforceStoragePolicies() {
                persistFiles()
            }
        }
    }

    public func load() {
        let hasAuthoritativeIndex: Bool
        if let decoded = fileStorage.loadIndex([ShelfFileItem].self) {
            self.files = decoded
            hasAuthoritativeIndex = true
        } else if let saved = storage.codable(forKey: "stashedFiles", as: [ShelfFileItem].self) {
            self.files = saved
            hasAuthoritativeIndex = true
        } else {
            hasAuthoritativeIndex = false
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
        if hasAuthoritativeIndex {
            cleanupOrphanedAssets()
            if enforceStoragePolicies() {
                persistFiles()
            }
        }
    }

    public func save() {
        storage.setCodable(retentionPeriod, forKey: "retentionPeriod")
        storage.setCodable(diskQuota, forKey: "diskQuota")
        storage.set(autoPrune, forKey: "autoPrune")
        storage.set(autoRemoveOnDrag, forKey: "autoRemoveOnDrag")

        enforceStoragePolicies()
        persistFiles()
    }

    private func persistFiles() {
        storage.setCodable(files, forKey: "stashedFiles")
        fileStorage.saveIndex(files)
    }

    /// Applies the retention and quota controls shown in Settings.
    ///
    /// The removal pass deliberately does not call `save()`: `save()` invokes
    /// this method after writing the settings, and a recursive save would keep
    /// walking the same directory on every deleted item.
    @discardableResult
    public func enforceStoragePolicies(now: Date = Date()) -> Bool {
        // A moved file is the person's only copy, unlike the cache-like files
        // Purah creates. Exclude it from both retention and quota accounting.
        let policyCandidates = files.filter { $0.ingestMode != .moved }
        var sizes: [String: Int64] = [:]
        for item in policyCandidates {
            sizes[item.id] = ownedBytes(of: item)
        }
        var totalBytes = sizes.values.reduce(Int64(0), +)
        var idsToRemove = Set(
            policyCandidates
                .filter { !$0.isFavorite && retentionPeriod.isExpired(timestamp: $0.timestamp, now: now) }
                .map(\.id)
        )
        for id in idsToRemove {
            totalBytes -= sizes[id] ?? 0
        }

        if autoPrune, let maxBytes = diskQuota.maxBytes, totalBytes > maxBytes {
            let oldestFirst = policyCandidates
                .filter {
                    !$0.isFavorite
                        && !idsToRemove.contains($0.id)
                        && (sizes[$0.id] ?? 0) > 0
                }
                .sorted {
                    $0.timestamp == $1.timestamp ? $0.id < $1.id : $0.timestamp < $1.timestamp
                }
            for item in oldestFirst {
                guard totalBytes > maxBytes else { break }
                idsToRemove.insert(item.id)
                totalBytes -= sizes[item.id] ?? 0
            }
        }

        guard !idsToRemove.isEmpty else { return false }

        for item in files where idsToRemove.contains(item.id) {
            if let path = ownedPath(of: item) {
                try? FileManager.default.removeItem(atPath: path)
            }
            selectedFileIds.remove(item.id)
            if lastSelectedFileId == item.id {
                lastSelectedFileId = nil
            }
        }
        files.removeAll { idsToRemove.contains($0.id) }
        boundStore?._shelfFiles.removeAll { idsToRemove.contains($0.id) }
        return true
    }

    /// Only files inside the shelf sandbox can reduce disk usage when their
    /// row is pruned. Most stashed files still live at their original path.
    private func ownedPath(of item: ShelfFileItem) -> String? {
        for path in [item.filePath, item.resolvedURL?.path].compactMap({ $0 }) {
            if Self.isPath(path, inside: fileStorage.baseDirectory) {
                return URL(fileURLWithPath: path).standardizedFileURL.path
            }
        }
        return nil
    }

    private func ownedBytes(of item: ShelfFileItem) -> Int64 {
        guard let path = ownedPath(of: item),
              let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attributes[.size] as? NSNumber else {
            return 0
        }
        return max(size.int64Value, 0)
    }

    @discardableResult
    public func addFile(url: URL) -> ShelfFileItem? {
        addFile(url: url, mode: .link)
    }

    @discardableResult
    public func addFile(url: URL, mode: ShelfIngestMode) -> ShelfFileItem? {
        let result = ingestFile(url: url, mode: mode)
        if let item = result.item {
            persistFiles()
            boundStore?._shelfFiles = files
            return item
        }
        return nil
    }

    /// Ingests a drop as one transaction: one persistence pass and one store
    /// mirror update, regardless of how many URLs arrived together.
    public func ingest(urls: [URL], mode: ShelfIngestMode) -> ShelfIngestOutcome {
        var outcome = ShelfIngestOutcome()
        for url in urls {
            let standardized = url.standardizedFileURL
            let result = ingestFile(url: standardized, mode: mode)
            guard let item = result.item else {
                outcome.failedURLs.append(standardized)
                continue
            }
            outcome.itemIDs.append(item.id)
            if item.ingestMode == .moved {
                outcome.movedIDs.append(item.id)
            }
            if result.fellBackToLink {
                outcome.fallbackURLs.append(standardized)
            }
        }

        if !outcome.itemIDs.isEmpty {
            persistFiles()
            boundStore?._shelfFiles = files
        }
        return outcome
    }

    private struct FileIngestResult {
        let item: ShelfFileItem?
        let fellBackToLink: Bool
    }

    private func ingestFile(url: URL, mode: ShelfIngestMode) -> FileIngestResult {
        let source = url.standardizedFileURL
        let sourcePath = source.path
        let existingIndex = files.firstIndex(where: {
            $0.filePath == sourcePath || $0.resolvedURL?.standardizedFileURL.path == sourcePath
        })

        if mode == .link || mode == .owned {
            if let existingIndex {
                files[existingIndex].timestamp = Date()
                let item = files.remove(at: existingIndex)
                files.insert(item, at: 0)
                return FileIngestResult(item: item, fellBackToLink: false)
            }
            let item = makeFileItem(url: source, mode: mode, originPath: nil)
            files.insert(item, at: 0)
            return FileIngestResult(item: item, fellBackToLink: false)
        }

        // A shelf item dropped back onto its own shelf is already where it
        // belongs. Preserve its existing mode, or treat a previously unknown
        // sandbox file as shelf-owned rather than pretending it was moved.
        if Self.isPath(sourcePath, inside: fileStorage.baseDirectory) {
            if let existingIndex {
                files[existingIndex].timestamp = Date()
                let item = files.remove(at: existingIndex)
                files.insert(item, at: 0)
                return FileIngestResult(item: item, fellBackToLink: false)
            }
            let item = makeFileItem(url: source, mode: .owned, originPath: nil)
            files.insert(item, at: 0)
            return FileIngestResult(item: item, fellBackToLink: false)
        }

        let destination = uniqueAssetURL(for: source.lastPathComponent)
        do {
            try moveHandler(source, destination)
            let preserved = existingIndex.map { files[$0] }
            let item = makeFileItem(
                url: destination,
                mode: .moved,
                originPath: sourcePath,
                id: preserved?.id ?? UUID().uuidString,
                isFavorite: preserved?.isFavorite ?? false
            )
            replaceOrInsert(item, existingIndex: existingIndex)
            return FileIngestResult(item: item, fellBackToLink: false)
        } catch {
            // The move failed, but the original is still the safest thing to
            // keep. A link row is lossless; a missing file is not.
            guard FileManager.default.fileExists(atPath: source.path) else {
                return FileIngestResult(item: nil, fellBackToLink: false)
            }
            let preserved = existingIndex.map { files[$0] }
            let item = makeFileItem(
                url: source,
                mode: .link,
                originPath: nil,
                id: preserved?.id ?? UUID().uuidString,
                isFavorite: preserved?.isFavorite ?? false
            )
            replaceOrInsert(item, existingIndex: existingIndex)
            return FileIngestResult(item: item, fellBackToLink: true)
        }
    }

    private func makeFileItem(
        url: URL,
        mode: ShelfIngestMode,
        originPath: String?,
        id: String = UUID().uuidString,
        isFavorite: Bool = false
    ) -> ShelfFileItem {
        let standardized = url.standardizedFileURL
        let attr = try? FileManager.default.attributesOfItem(atPath: standardized.path)
        let size = (attr?[.size] as? Int64) ?? 0
        let bookmark = try? standardized.bookmarkData(
            options: [.minimalBookmark],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        return ShelfFileItem(
            id: id,
            name: standardized.lastPathComponent,
            sizeDescription: ByteCountFormatter.string(fromByteCount: size, countStyle: .file),
            fileExtension: standardized.pathExtension,
            filePath: standardized.path,
            bookmarkData: bookmark,
            timestamp: Date(),
            isFavorite: isFavorite,
            ingestMode: mode,
            originPath: originPath
        )
    }

    private func replaceOrInsert(_ item: ShelfFileItem, existingIndex: Int?) {
        if let existingIndex {
            files.remove(at: existingIndex)
        }
        files.insert(item, at: 0)
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

        guard let zipPath = ProcessLaunchSanitizer.executablePath("/usr/bin/zip") else {
            return nil
        }
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
        process.executableURL = URL(fileURLWithPath: zipPath)
        process.arguments = ProcessLaunchSanitizer.argumentList(
            ["-j", "-q", destZipURL.path] + sourcePaths
        )
        try? process.run()
        process.waitUntilExit()

        if !FileManager.default.fileExists(atPath: destZipURL.path) {
            let fallbackProcess = Process()
            fallbackProcess.executableURL = URL(fileURLWithPath: zipPath)
            fallbackProcess.arguments = ProcessLaunchSanitizer.argumentList(
                ["-r", "-q", destZipURL.path] + sourcePaths
            )
            try? fallbackProcess.run()
            fallbackProcess.waitUntilExit()
        }

        guard FileManager.default.fileExists(atPath: destZipURL.path) else { return nil }

        addFile(url: destZipURL, mode: .owned)
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
        addFile(url: fileURL, mode: .owned)
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
        addFile(url: fileURL, mode: .owned)
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
        addFile(url: fileURL, mode: .owned)
        let standardizedPath = fileURL.standardizedFileURL.path
        return files.first(where: { $0.filePath == standardizedPath })
    }

    /// Removes the item from the shelf after it is dragged out if `autoRemoveOnDrag` is enabled
    /// and the item is not starred (`isFavorite == false`).
    ///
    /// Shelf-owned files stay on disk for the receiver to finish reading. They
    /// become orphaned assets and are cleaned up on a later launch.
    ///
    /// Returns `true` when the item was actually removed.
    @discardableResult
    public func handleDragOutCompleted(id: String) -> Bool {
        guard autoRemoveOnDrag else { return false }
        guard let item = files.first(where: { $0.id == id }), !item.isFavorite else { return false }
        // A moved file is the person's only copy: dropping the row would let the
        // orphan sweep unlink it for good, so it is never auto-removed.
        guard item.ingestMode != .moved else { return false }
        removeFile(id: id, deletingOwnedFile: false)
        return true
    }

    /// Removes a batch of items from the shelf after they are dragged out or exported if `autoRemoveOnDrag` is enabled,
    /// while strictly preserving any starred (`isFavorite == true`) items.
    public func handleBatchDragOutCompleted(ids: [String]) {
        guard autoRemoveOnDrag else { return }
        for id in ids {
            if let item = files.first(where: { $0.id == id }), !item.isFavorite {
                // Moved originals stay put for the same reason as above: the
                // row is the only thing keeping their file from the orphan sweep.
                if item.ingestMode != .moved {
                    removeFile(id: id, deletingOwnedFile: false)
                }
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
            guard item.ingestMode != .moved else { return false }
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
        removeFile(id: id, deletingOwnedFile: true)
    }

    private func removeFile(id: String, deletingOwnedFile: Bool) {
        if deletingOwnedFile, let item = files.first(where: { $0.id == id }) {
            guard deleteStoredContent(for: item) else {
                // The row stays visible, so silence would read as a dead button.
                boundStore?.onCapacityWarningToast?("dropshelf.deleteFailed".localized)
                return
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
        var removedIDs: Set<String> = []
        for item in itemsToRemove {
            guard deleteStoredContent(for: item) else { continue }
            removedIDs.insert(item.id)
            selectedFileIds.remove(item.id)
            if lastSelectedFileId == item.id {
                lastSelectedFileId = nil
            }
        }
        files.removeAll { removedIDs.contains($0.id) }
        save()
        boundStore?._shelfFiles = files
    }

    /// Hard reset clearing all stashed files including favorites.
    public func clearAllIncludingFavorites() {
        var removedIDs: Set<String> = []
        for item in files {
            guard deleteStoredContent(for: item) else { continue }
            removedIDs.insert(item.id)
        }
        files.removeAll { removedIDs.contains($0.id) }
        selectedFileIds.subtract(removedIDs)
        if let lastSelectedFileId, removedIDs.contains(lastSelectedFileId) {
            self.lastSelectedFileId = nil
        }
        save()
        boundStore?._shelfFiles = files
    }

    /// Puts moved originals back where they came from. A missing destination
    /// directory or an occupied original path refuses that item instead of
    /// overwriting another file.
    public func undoMove(itemIDs: [String]) -> ShelfUndoOutcome {
        var outcome = ShelfUndoOutcome()
        for id in itemIDs {
            // An id that is no longer here was already restored (or is already
            // gone), so a second tap on Undo is skipped, not reported as a failure.
            guard let item = files.first(where: { $0.id == id }) else { continue }
            guard item.ingestMode == .moved,
                  let sandboxPath = ownedPath(of: item),
                  let originPath = item.originPath else {
                outcome.failedIDs.append(id)
                continue
            }

            let source = URL(fileURLWithPath: sandboxPath).standardizedFileURL
            let destination = URL(fileURLWithPath: originPath).standardizedFileURL
            let originDirectory = destination.deletingLastPathComponent()
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: originDirectory.path, isDirectory: &isDirectory),
                  isDirectory.boolValue,
                  !FileManager.default.fileExists(atPath: destination.path) else {
                outcome.failedIDs.append(id)
                continue
            }

            do {
                try moveHandler(source, destination)
                outcome.restoredIDs.append(id)
            } catch {
                outcome.failedIDs.append(id)
            }
        }

        let restored = Set(outcome.restoredIDs)
        if !restored.isEmpty {
            files.removeAll { restored.contains($0.id) }
            selectedFileIds.subtract(restored)
            if let lastSelectedFileId, restored.contains(lastSelectedFileId) {
                self.lastSelectedFileId = nil
            }
            persistFiles()
            boundStore?._shelfFiles = files
        }
        return outcome
    }

    /// Returns false when a moved original could not be recycled, so its row
    /// stays visible rather than becoming an orphan the person cannot find.
    private func deleteStoredContent(for item: ShelfFileItem) -> Bool {
        switch item.ingestMode {
        case .moved:
            guard let path = ownedPath(of: item) else { return false }
            guard FileManager.default.fileExists(atPath: path) else { return true }
            do {
                try recycleHandler(URL(fileURLWithPath: path))
                return true
            } catch {
                return false
            }
        case .owned:
            if let path = ownedPath(of: item) {
                try? FileManager.default.removeItem(atPath: path)
            }
            return true
        case .link:
            // Rows written before ingestMode existed used the same path-based
            // ownership rule. A legacy link inside the sandbox is still ours.
            if let path = ownedPath(of: item) {
                try? FileManager.default.removeItem(atPath: path)
            }
            return true
        }
    }

    public func mount(store: PurahWorkspaceStore) {
        self.boundStore = store
        // The persisted plugin index is authoritative. The store field is a
        // compatibility mirror; copying a non-empty mirror back over an empty
        // shelf revived deleted rows.
        store._shelfFiles = files
    }

    public func unmount(store: PurahWorkspaceStore) {
        save()
        if boundStore === store {
            boundStore = nil
        }
    }

    /// Removes assets that no shelf row references and that are old enough
    /// that no drag receiver can still be reading them.
    private func cleanupOrphanedAssets(olderThan maxAge: TimeInterval = 86_400) {
        let fm = FileManager.default
        let assets = fileStorage.assetsDirectory
        guard let urls = try? fm.contentsOfDirectory(
            at: assets,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let referencedPaths = Set(files.flatMap { item -> [String] in
            var paths: [String] = []
            if let path = item.filePath {
                paths.append(URL(fileURLWithPath: path).standardizedFileURL.path)
            }
            if let resolved = item.resolvedURL {
                paths.append(resolved.standardizedFileURL.path)
            }
            return paths
        })

        let cutoff = Date().addingTimeInterval(-maxAge)
        for url in urls {
            let path = url.standardizedFileURL.path
            guard !referencedPaths.contains(path) else { continue }
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modified = values.contentModificationDate,
                  modified < cutoff else { continue }
            try? fm.removeItem(at: url)
        }
    }
}
