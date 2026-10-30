// Sources/PurahCore/Storage/PurahPluginFileStorage.swift
import Foundation
import AppKit

/// Standardized isolated disk storage sandbox for Purah plugins.
/// Allocates a dedicated directory in Application Support with separate data and cache subdirectories,
/// disk usage telemetry, and Finder reveal capabilities.
public struct PurahPluginFileStorage: Sendable {
    public let pluginId: String
    public let rootDirectory: URL
    public let dataDirectory: URL
    public let cacheDirectory: URL

    public var baseDirectory: URL { rootDirectory }

    public var assetsDirectory: URL {
        let dir = rootDirectory.appendingPathComponent("assets", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static let baseApplicationSupportDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return appSupport.appendingPathComponent("Purah/Plugins", isDirectory: true)
    }()

    /// Where a test build writes instead of the user's real sandbox.
    ///
    /// Tests construct plugin state with the default argument all over the
    /// suite (`ScopedPluginStorage`, `NotesPluginState()`, …), and each one
    /// creates a directory. Pointing the default at a throwaway tree keeps a
    /// test run from littering `~/Library/Application Support/Purah/Plugins`
    /// with hundreds of `*_test_<uuid>` folders — which it demonstrably did.
    ///
    /// A test may still pass an explicit `customBaseDirectory` to get its own
    /// isolated location; only the default is redirected.
    public static var testBaseDirectory: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("purah-tests", isDirectory: true)
            .appendingPathComponent("Plugins", isDirectory: true)
    }

    /// Whether the current process is a test run.
    ///
    /// Duplicated from `PurahWorkspaceStore.isTestingEnvironment` on purpose:
    /// that property is `@MainActor`-isolated and this type is constructed from
    /// nonisolated contexts. Keeping storage independent of the UI-facing store
    /// also means a storage unit test does not drag the whole store with it.
    public static var isRunningTests: Bool {
        NSClassFromString("XCTest") != nil ||
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
        ProcessInfo.processInfo.arguments.contains(where: {
            $0.contains("swiftpm-testing-helper") || $0.contains("xctest")
        })
    }

    public init(pluginId: String, customBaseDirectory: URL? = nil) {
        self.pluginId = pluginId
        let base = customBaseDirectory
            ?? (Self.isRunningTests ? Self.testBaseDirectory : Self.baseApplicationSupportDirectory)
        let root = base.appendingPathComponent(pluginId, isDirectory: true)
        self.rootDirectory = root
        self.dataDirectory = root.appendingPathComponent("data", isDirectory: true)
        self.cacheDirectory = root.appendingPathComponent("cache", isDirectory: true)

        try? FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    /// Recursively computes total disk size of the plugin sandbox directory in bytes.
    public func computeDiskUsageBytes() -> Int64 {
        size(of: rootDirectory)
    }

    /// Bytes held by one directory, recursively. The diagnostics page asks for
    /// `data/` and `cache/` separately, because "this can be cleared freely" and
    /// "this is the user's notes" must never be shown as one number.
    public func size(of directory: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        // The enumerator already prefetched the size; asking the file system
        // again for each one doubled the syscalls on this path.
        for case let fileURL as URL in enumerator {
            if let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
               let size = values.fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    public var dataUsageBytes: Int64 { size(of: dataDirectory) }
    public var cacheUsageBytes: Int64 { size(of: cacheDirectory) }

    /// Empties `cache/` only. Nothing here is the person's content: it is
    /// regenerable, which is exactly what makes it safe to offer as one click.
    public func clearCache() {
        let fm = FileManager.default
        let contents = (try? fm.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)) ?? []
        for url in contents {
            try? fm.removeItem(at: url)
        }
    }

    /// Empties `data/`. This is the notes, the clipboard history, the stash —
    /// destructive, and never reachable without a confirmation.
    public func clearData() {
        let fm = FileManager.default
        let contents = (try? fm.contentsOfDirectory(at: dataDirectory, includingPropertiesForKeys: nil)) ?? []
        for url in contents {
            try? fm.removeItem(at: url)
        }
    }

    /// Contents of `data/index.json`, or nil when it is missing or unusable.
    ///
    /// The notes and shelf collections both keep their list there; one reader
    /// and one writer mean a change to the file name or encoding cannot land in
    /// only half the app.
    ///
    /// An index that cannot be decoded is renamed out of the way first. Callers
    /// treat `nil` as "nothing saved yet" and write their seed collection on
    /// the next save, so leaving the file in place let one added field — or one
    /// launch of an older build — replace the whole collection with a single
    /// starter document. `PurahDiskRepository` already keeps its index this way.
    public func loadIndex<T: Decodable>(_ type: [T].Type = [T].self) -> [T]? {
        let url = dataDirectory.appendingPathComponent("index.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url) else {
            quarantineIndex(url, reason: "could not be read")
            return nil
        }
        do {
            return try JSONDecoder().decode([T].self, from: data)
        } catch {
            quarantineIndex(url, reason: "could not be decoded")
            return nil
        }
    }

    private func quarantineIndex(_ url: URL, reason: String) {
        let stamp = Int(Date().timeIntervalSince1970)
        let backup = url.deletingLastPathComponent().appendingPathComponent("index.corrupt-\(stamp).json")
        guard (try? FileManager.default.moveItem(at: url, to: backup)) != nil else { return }
        DiagnosticLogger.shared.warn(
            "Storage",
            "\(url.lastPathComponent) \(reason); kept as \(backup.lastPathComponent)"
        )
    }

    public func saveIndex<T: Encodable>(_ items: [T]) {
        let url = dataDirectory.appendingPathComponent("index.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(items) else { return }
        try? FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    /// Human-readable formatted string of the current disk usage.
    public var diskUsageFormatted: String {
        Self.format(computeDiskUsageBytes())
    }

    /// One spelling of a byte count for the whole app: KB below a megabyte,
    /// and never "0 KB" for an empty directory.
    public static func format(_ size: Int64) -> String {
        guard size > 0 else { return "0 KB" }
        let mb = Double(size) / (1024.0 * 1024.0)
        if mb >= 1.0 {
            return String(format: "%.1f MB", mb)
        }
        return "\(max(size / 1024, 1)) KB"
    }

    /// Reveals the plugin sandbox directory in macOS Finder.
    @MainActor
    public func openInFinder() {
        NSWorkspace.shared.selectFile(rootDirectory.path, inFileViewerRootedAtPath: "")
    }

    /// Clears data and cache directories while preserving any specified essential files.
    public func clearAll(excluding: Set<URL> = []) {
        let fm = FileManager.default
        let standardExcluding = Set(excluding.map(\.standardizedFileURL.path))
        let contents = (try? fm.contentsOfDirectory(at: dataDirectory, includingPropertiesForKeys: nil)) ?? []
        for url in contents where !standardExcluding.contains(url.standardizedFileURL.path) {
            try? fm.removeItem(at: url)
        }
        let cacheContents = (try? fm.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)) ?? []
        for url in cacheContents where !standardExcluding.contains(url.standardizedFileURL.path) {
            try? fm.removeItem(at: url)
        }
    }
}
