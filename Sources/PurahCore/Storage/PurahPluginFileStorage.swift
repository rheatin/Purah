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

    public static let baseApplicationSupportDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return appSupport.appendingPathComponent("Purah/Plugins", isDirectory: true)
    }()

    public init(pluginId: String, customBaseDirectory: URL? = nil) {
        self.pluginId = pluginId
        let base = customBaseDirectory ?? Self.baseApplicationSupportDirectory
        let root = base.appendingPathComponent(pluginId, isDirectory: true)
        self.rootDirectory = root
        self.dataDirectory = root.appendingPathComponent("data", isDirectory: true)
        self.cacheDirectory = root.appendingPathComponent("cache", isDirectory: true)

        try? FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    /// Recursively computes total disk size of the plugin sandbox directory in bytes.
    public func computeDiskUsageBytes() -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: rootDirectory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
               let size = attrs[.size] as? Int64 {
                total += size
            }
        }
        return total
    }

    /// Human-readable formatted string of the current disk usage.
    public var diskUsageFormatted: String {
        let size = computeDiskUsageBytes()
        let mb = Double(size) / (1024.0 * 1024.0)
        if mb >= 1.0 {
            return String(format: "%.1f MB", mb)
        } else {
            let kb = max(size / 1024, 1)
            return "\(kb) KB"
        }
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
