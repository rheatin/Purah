// Sources/PurahCore/Plugins/PluginStorageScanner.swift
import Foundation

/// Every directory the storage inspector may read.
///
/// Tests pass temporary roots; production uses `live`. Keeping the roots in one
/// value means no code below has to know how `Application Support/Purah` is
/// laid out and no test can accidentally walk the person's real shelf.
public struct PluginStorageRoots: Sendable {
    public var pluginsBase: URL
    public var clipboard: URL
    public var vitals: URL

    public init(pluginsBase: URL, clipboard: URL, vitals: URL) {
        self.pluginsBase = pluginsBase
        self.clipboard = clipboard
        self.vitals = vitals
    }

    public static var live: PluginStorageRoots {
        let pluginsBase = PurahPluginFileStorage.baseApplicationSupportDirectory
        let purahRoot = pluginsBase.deletingLastPathComponent()
        return PluginStorageRoots(
            pluginsBase: pluginsBase,
            clipboard: purahRoot.appendingPathComponent("Clipboard", isDirectory: true),
            vitals: purahRoot.appendingPathComponent("Vitals", isDirectory: true)
        )
    }
}

public struct PluginStoragePluginSpec: Sendable, Equatable {
    public let id: String
    public let name: String
    public let icon: String
    public let colorHex: String

    public init(id: String, name: String, icon: String, colorHex: String) {
        self.id = id
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
    }
}

public enum PluginStorageRowKind: Sendable, Equatable {
    case plugin(String)
    case clipboard
    case vitals
    case leftovers

    public var id: String {
        switch self {
        case .plugin(let id): return "plugin:\(id)"
        case .clipboard: return "app:clipboard"
        case .vitals: return "app:vitals"
        case .leftovers: return "app:leftovers"
        }
    }

    public var pluginId: String? {
        guard case .plugin(let id) = self else { return nil }
        return id
    }
}

public struct PluginStorageTarget: Sendable, Equatable {
    public let kind: PluginStorageRowKind
    public let rootURL: URL

    public var id: String { kind.id }

    public init(kind: PluginStorageRowKind, rootURL: URL) {
        self.kind = kind
        self.rootURL = rootURL
    }
}

public struct PluginStorageMeasurement: Sendable {
    public let target: PluginStorageTarget
    public let assetsBytes: Int64
    public let dataBytes: Int64
    public let cacheBytes: Int64
    public let dataLocations: [URL]
    public let dataContainerLocations: [URL]
    public let dataEntryLocations: [URL]
    public let cacheLocations: [URL]
    public let leftoverDirectories: [URL]

    public init(
        target: PluginStorageTarget,
        assetsBytes: Int64,
        dataBytes: Int64,
        cacheBytes: Int64,
        dataLocations: [URL],
        dataContainerLocations: [URL],
        dataEntryLocations: [URL],
        cacheLocations: [URL],
        leftoverDirectories: [URL]
    ) {
        self.target = target
        self.assetsBytes = assetsBytes
        self.dataBytes = dataBytes
        self.cacheBytes = cacheBytes
        self.dataLocations = dataLocations
        self.dataContainerLocations = dataContainerLocations
        self.dataEntryLocations = dataEntryLocations
        self.cacheLocations = cacheLocations
        self.leftoverDirectories = leftoverDirectories
    }
}

public enum PluginStorageScanner {
    public static func measure(
        pluginId: String,
        roots: PluginStorageRoots
    ) -> PluginStorageMeasurement? {
        guard PurahPluginFileStorage.isValidPluginId(pluginId) else { return nil }
        return measurePlugin(
            PluginStorageTarget(
                kind: .plugin(pluginId),
                rootURL: roots.pluginsBase.appendingPathComponent(pluginId, isDirectory: true)
            )
        )
    }

    public static func targets(
        plugins: [PluginStoragePluginSpec],
        roots: PluginStorageRoots
    ) -> [PluginStorageTarget] {
        plugins.map {
            PluginStorageTarget(
                kind: .plugin($0.id),
                rootURL: roots.pluginsBase.appendingPathComponent($0.id, isDirectory: true)
            )
        } + [
            PluginStorageTarget(kind: .clipboard, rootURL: roots.clipboard),
            PluginStorageTarget(kind: .vitals, rootURL: roots.vitals),
        ]
    }

    public static func scan(
        plugins: [PluginStoragePluginSpec],
        roots: PluginStorageRoots
    ) -> [PluginStorageMeasurement] {
        let pluginTargets = targets(plugins: plugins, roots: roots)
        let registeredIDs = Set(plugins.map(\.id))
        let leftovers = leftoverDirectories(
            in: roots.pluginsBase,
            registeredIDs: registeredIDs
        )
        let allTargets = pluginTargets + [
            PluginStorageTarget(kind: .leftovers, rootURL: roots.pluginsBase)
        ]
        return allTargets.map { target in
            switch target.kind {
            case .plugin:
                return measurePlugin(target)
            case .clipboard, .vitals:
                return PluginStorageMeasurement(
                    target: target,
                    assetsBytes: 0,
                    dataBytes: PurahPluginFileStorage.allocatedSize(of: target.rootURL),
                    cacheBytes: 0,
                    dataLocations: [target.rootURL],
                    dataContainerLocations: [target.rootURL],
                    dataEntryLocations: [],
                    cacheLocations: [],
                    leftoverDirectories: []
                )
            case .leftovers:
                return measureLeftovers(target, directories: leftovers)
            }
        }
    }

    public static func leftoverDirectories(
        in pluginsBase: URL,
        registeredIDs: Set<String>
    ) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: pluginsBase,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        )) ?? []
        return urls.filter { url in
            guard !registeredIDs.contains(url.lastPathComponent),
                  let values = try? url.resourceValues(forKeys: [.isDirectoryKey]) else {
                return false
            }
            return values.isDirectory == true
        }
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    public static func clearContents(of directories: [URL]) {
        let fileManager = FileManager.default
        for directory in directories {
            let contents = (try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            )) ?? []
            for url in contents {
                try? fileManager.removeItem(at: url)
            }
        }
    }

    public static func deleteData(containers: [URL], entries: [URL]) {
        clearContents(of: containers)
        let fileManager = FileManager.default
        for entry in entries {
            try? fileManager.removeItem(at: entry)
        }
    }

    private static func measurePlugin(_ target: PluginStorageTarget) -> PluginStorageMeasurement {
        let assets = target.rootURL.appendingPathComponent("assets", isDirectory: true)
        let data = target.rootURL.appendingPathComponent("data", isDirectory: true)
        let cache = target.rootURL.appendingPathComponent("cache", isDirectory: true)
        let rootEntries = rootDataEntries(in: target.rootURL)
        return PluginStorageMeasurement(
            target: target,
            assetsBytes: PurahPluginFileStorage.allocatedSize(of: assets),
            dataBytes: PurahPluginFileStorage.allocatedSize(of: data) +
                rootEntries.reduce(0) { $0 + PurahPluginFileStorage.allocatedSize(of: $1) },
            cacheBytes: PurahPluginFileStorage.allocatedSize(of: cache),
            dataLocations: [data] + rootEntries,
            dataContainerLocations: [data],
            dataEntryLocations: rootEntries,
            cacheLocations: [cache],
            leftoverDirectories: []
        )
    }

    private static func measureLeftovers(
        _ target: PluginStorageTarget,
        directories: [URL]
    ) -> PluginStorageMeasurement {
        let assets = directories.map { $0.appendingPathComponent("assets", isDirectory: true) }
        let data = directories.map { $0.appendingPathComponent("data", isDirectory: true) }
        let cache = directories.map { $0.appendingPathComponent("cache", isDirectory: true) }
        let rootEntries = directories.flatMap(rootDataEntries(in:))
        return PluginStorageMeasurement(
            target: target,
            assetsBytes: assets.reduce(0) { $0 + PurahPluginFileStorage.allocatedSize(of: $1) },
            dataBytes: data.reduce(0) { $0 + PurahPluginFileStorage.allocatedSize(of: $1) } +
                rootEntries.reduce(0) { $0 + PurahPluginFileStorage.allocatedSize(of: $1) },
            cacheBytes: cache.reduce(0) { $0 + PurahPluginFileStorage.allocatedSize(of: $1) },
            dataLocations: data + rootEntries,
            dataContainerLocations: data,
            dataEntryLocations: rootEntries,
            cacheLocations: cache,
            leftoverDirectories: directories
        )
    }

    /// Root-level files are plugin data too: `PurahDiskRepository` writes
    /// `index.json` there. Only the three managed directories are excluded.
    private static func rootDataEntries(in root: URL) -> [URL] {
        let managedNames: Set<String> = ["assets", "data", "cache"]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        )) ?? []
        let names = urls.compactMap { url -> String? in
            let name = url.lastPathComponent
            if managedNames.contains(name) {
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
                if values?.isDirectory == true { return nil }
            }
            return name
        }
        .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        return names.map { root.appendingPathComponent($0) }
    }
}
