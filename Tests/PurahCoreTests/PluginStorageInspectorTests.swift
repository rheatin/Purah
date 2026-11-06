import Foundation
import Testing
@testable import PurahCore
@testable import PurahUI

@Suite("Plugin Storage Inspector")
struct PluginStorageInspectorTests {
    @Test("Allocated bytes are split into disjoint assets, data and cache buckets")
    func allocatedBucketsAreDisjoint() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let storage = PurahPluginFileStorage(
            pluginId: "storage-buckets",
            customBaseDirectory: root.appendingPathComponent("Plugins", isDirectory: true)
        )
        let assetsFile = storage.assetsDirectory.appendingPathComponent("shelf-move.bin")
        let dataFile = storage.dataDirectory.appendingPathComponent("index.json")
        let cacheFile = storage.cacheDirectory.appendingPathComponent("thumbnail.bin")
        try writeBytes(4_096, to: assetsFile)
        try writeBytes(4_096, to: dataFile)
        try writeBytes(4_096, to: cacheFile)

        let expectedAssets = try allocatedBytes(of: assetsFile)
        let expectedData = try allocatedBytes(of: dataFile)
        let expectedCache = try allocatedBytes(of: cacheFile)

        #expect(expectedAssets > 0)
        #expect(storage.size(of: storage.assetsDirectory) == expectedAssets)
        #expect(storage.size(of: storage.dataDirectory) == expectedData)
        #expect(storage.size(of: storage.cacheDirectory) == expectedCache)
        #expect(storage.assetsUsageBytes == expectedAssets)
        #expect(storage.dataUsageBytes == expectedData)
        #expect(storage.cacheUsageBytes == expectedCache)

        let roots = PluginStorageRoots(
            pluginsBase: root.appendingPathComponent("Plugins", isDirectory: true),
            clipboard: root.appendingPathComponent("Clipboard", isDirectory: true),
            vitals: root.appendingPathComponent("Vitals", isDirectory: true)
        )
        let measured = try #require(
            PluginStorageScanner.scan(
                plugins: [
                    PluginStoragePluginSpec(
                        id: "storage-buckets",
                        name: "Storage Buckets",
                        icon: "externaldrive",
                        colorHex: "#0A84FF"
                    )
                ],
                roots: roots
            ).first(where: { $0.target.kind == .plugin("storage-buckets") })
        )
        #expect(measured.assetsBytes == expectedAssets)
        #expect(measured.dataBytes == expectedData)
        #expect(measured.cacheBytes == expectedCache)
    }

    @Test("A sparse file is measured by allocation, not by its logical size")
    func sparseFileUsesAllocatedSize() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let directory = root.appendingPathComponent("sparse", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("mostly-empty.bin")
        try Data([0x50]).write(to: file)

        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: 64 * 1024 * 1024)
        try handle.close()

        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        let logicalSize = try #require((attributes[.size] as? NSNumber)?.int64Value)
        let storage = PurahPluginFileStorage(
            pluginId: "sparse-check",
            customBaseDirectory: root
        )

        #expect(storage.size(of: directory) < logicalSize)
    }

    @Test("Leftover discovery returns only unregistered plugin directories")
    func leftoverDiscovery() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let pluginsBase = root.appendingPathComponent("Plugins", isDirectory: true)
        for name in ["calendar", "old-alpha", "old-beta"] {
            try FileManager.default.createDirectory(
                at: pluginsBase.appendingPathComponent(name, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
        try Data("not a plugin".utf8).write(
            to: pluginsBase.appendingPathComponent("notes.txt")
        )

        let leftovers = PluginStorageScanner.leftoverDirectories(
            in: pluginsBase,
            registeredIDs: ["calendar"]
        )
        #expect(leftovers.map(\.lastPathComponent) == ["old-alpha", "old-beta"])
    }

    @Test("Clipboard and Vitals rows report bytes from their injected roots")
    func appLevelRowsUseInjectedRoots() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let pluginsBase = root.appendingPathComponent("Plugins", isDirectory: true)
        let clipboard = root.appendingPathComponent("Clipboard", isDirectory: true)
        let vitals = root.appendingPathComponent("Vitals", isDirectory: true)
        try FileManager.default.createDirectory(at: pluginsBase, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: clipboard, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: vitals, withIntermediateDirectories: true)

        let clipboardFile = clipboard.appendingPathComponent("images/one.png")
        let vitalsFile = vitals.appendingPathComponent("vitals_history.json")
        try writeBytes(4_096, to: clipboardFile)
        try writeBytes(8_192, to: vitalsFile)

        let measured = PluginStorageScanner.scan(
            plugins: [],
            roots: PluginStorageRoots(
                pluginsBase: pluginsBase,
                clipboard: clipboard,
                vitals: vitals
            )
        )
        let clipboardRow = try #require(measured.first(where: { $0.target.kind == .clipboard }))
        let vitalsRow = try #require(measured.first(where: { $0.target.kind == .vitals }))

        #expect(clipboardRow.assetsBytes == 0)
        #expect(clipboardRow.cacheBytes == 0)
        #expect(clipboardRow.dataBytes == (try allocatedBytes(of: clipboardFile)))
        #expect(clipboardRow.dataLocations == [clipboard])

        #expect(vitalsRow.assetsBytes == 0)
        #expect(vitalsRow.cacheBytes == 0)
        #expect(vitalsRow.dataBytes == (try allocatedBytes(of: vitalsFile)))
        #expect(vitalsRow.dataLocations == [vitals])
    }

    @Test("Clearing data leaves assets untouched")
    func clearDataPreservesAssets() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let storage = PurahPluginFileStorage(
            pluginId: "clear-data-check",
            customBaseDirectory: root
        )
        let asset = storage.assetsDirectory.appendingPathComponent("only-copy.bin")
        let data = storage.dataDirectory.appendingPathComponent("index.json")
        try writeBytes(4_096, to: asset)
        try writeBytes(4_096, to: data)

        storage.clearData()

        #expect(FileManager.default.fileExists(atPath: asset.path))
        #expect(!FileManager.default.fileExists(atPath: data.path))
        #expect(storage.assetsUsageBytes > 0)
    }

    @Test("Root entries count as data and can be deleted without touching assets")
    func rootEntriesAreDataButNeverAssets() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let pluginsBase = root.appendingPathComponent("Plugins", isDirectory: true)
        let storage = PurahPluginFileStorage(
            pluginId: "root-data-check",
            customBaseDirectory: pluginsBase
        )
        let rootIndex = storage.rootDirectory.appendingPathComponent("index.json")
        let asset = storage.assetsDirectory.appendingPathComponent("keep.bin")
        try writeBytes(4_096, to: rootIndex)
        try writeBytes(4_096, to: asset)

        let measured = try #require(
            PluginStorageScanner.scan(
                plugins: [
                    PluginStoragePluginSpec(
                        id: "root-data-check",
                        name: "Root Data Check",
                        icon: "externaldrive",
                        colorHex: "#0A84FF"
                    )
                ],
                roots: PluginStorageRoots(
                    pluginsBase: pluginsBase,
                    clipboard: root.appendingPathComponent("Clipboard", isDirectory: true),
                    vitals: root.appendingPathComponent("Vitals", isDirectory: true)
                )
            ).first(where: { $0.target.kind == .plugin("root-data-check") })
        )

        #expect(measured.assetsBytes == (try allocatedBytes(of: asset)))
        let expectedRootData = try allocatedBytes(of: rootIndex)
        #expect(
            measured.dataBytes == expectedRootData,
            "data=\(measured.dataBytes), root=\(expectedRootData), entries=\(measured.dataEntryLocations)"
        )
        #expect(measured.dataLocations.contains(rootIndex))
        #expect(measured.dataEntryLocations == [rootIndex])
        #expect(!measured.dataEntryLocations.contains(storage.assetsDirectory))

        PluginStorageScanner.deleteData(
            containers: measured.dataContainerLocations,
            entries: measured.dataEntryLocations
        )

        #expect(!FileManager.default.fileExists(atPath: rootIndex.path))
        #expect(FileManager.default.fileExists(atPath: asset.path))
        #expect(FileManager.default.fileExists(atPath: storage.dataDirectory.path))
        #expect(FileManager.default.fileExists(atPath: storage.cacheDirectory.path))
    }

    @Test("Delete confirmations use the consequence for each row kind")
    @MainActor
    func deleteConfirmationCopy() {
        let localization = LocalizationManager.shared
        let savedLanguage = localization.currentLanguage
        defer { localization.currentLanguage = savedLanguage }
        localization.currentLanguage = .english

        #expect(
            PluginStorageConfirmationCopy.title(for: .clipboard, name: "Clipboard")
                == "Delete clipboard history and its images? They cannot be recovered."
        )
        #expect(
            PluginStorageConfirmationCopy.title(for: .vitals, name: "Vitals history")
                == "Delete the vitals history? The charts start over and the old data cannot be recovered."
        )
        #expect(
            PluginStorageConfirmationCopy.title(for: .plugin("notes"), name: "Notes")
                == "Delete all data for Notes? Notes, history and saved items in it cannot be recovered."
        )
    }

    @Test("Only a matching plugin row flashes")
    func storageRowFlashingPredicate() {
        #expect(!PluginStorageFocus.isFlashing(focusedPluginId: nil, kind: .clipboard))
        #expect(!PluginStorageFocus.isFlashing(focusedPluginId: nil, kind: .plugin("notes")))
        #expect(PluginStorageFocus.isFlashing(focusedPluginId: "notes", kind: .plugin("notes")))
        #expect(!PluginStorageFocus.isFlashing(focusedPluginId: "notes", kind: .plugin("calendar")))
        #expect(!PluginStorageFocus.isFlashing(focusedPluginId: "notes", kind: .vitals))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("purah-storage-inspector-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeBytes(_ count: Int, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(repeating: 0xA5, count: count).write(to: url)
    }

    private func allocatedBytes(of url: URL) throws -> Int64 {
        let values = try url.resourceValues(
            forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey]
        )
        return Int64(try #require(
            values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize
        ))
    }
}
