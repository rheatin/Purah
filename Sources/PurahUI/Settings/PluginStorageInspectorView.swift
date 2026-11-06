// Sources/PurahUI/Settings/PluginStorageInspectorView.swift
import SwiftUI
import AppKit
import PurahCore

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

enum PluginStorageFocus {
    static func rowID(forPluginId pluginId: String) -> String {
        "storage-pod:\(pluginId)"
    }

    static func rowID(for kind: PluginStorageRowKind) -> String {
        switch kind {
        case .plugin(let id):
            return rowID(forPluginId: id)
        case .clipboard, .vitals, .leftovers:
            return "storage-row:\(kind.id)"
        }
    }
}

/// The storage page joins plugin-owned sandboxes with the two app-level stores
/// that were previously missing from the totals.
public struct PluginStorageInspectorView: View {
    @State private var rows: [PluginStorageRow] = []
    @State private var pendingDeletion: PendingStorageDeletion?
    @State private var reloadTask: Task<Void, Never>?
    @State private var flashingPluginId: String?
    @State private var focusTask: Task<Void, Never>?

    private let roots: PluginStorageRoots
    private let injectedPlugins: [PluginStoragePluginSpec]?
    private let focusedPluginId: String?
    private let focusNonce: Int

    private var palette: ThemePalette { ThemeManager.shared.palette }

    public init(
        focusedPluginId: String? = nil,
        focusNonce: Int = 0
    ) {
        self.init(
            roots: .live,
            plugins: nil,
            focusedPluginId: focusedPluginId,
            focusNonce: focusNonce
        )
    }

    public init(
        roots: PluginStorageRoots,
        focusedPluginId: String? = nil,
        focusNonce: Int = 0
    ) {
        self.init(
            roots: roots,
            plugins: nil,
            focusedPluginId: focusedPluginId,
            focusNonce: focusNonce
        )
    }

    init(
        roots: PluginStorageRoots,
        plugins: [PluginStoragePluginSpec]?,
        focusedPluginId: String? = nil,
        focusNonce: Int = 0
    ) {
        self.roots = roots
        self.injectedPlugins = plugins
        self.focusedPluginId = focusedPluginId
        self.focusNonce = focusNonce
    }

    private var totalAssets: Int64? { total(\.assetsBytes) }
    private var totalData: Int64? { total(\.dataBytes) }
    private var totalCache: Int64? { total(\.cacheBytes) }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Label("diagnostics.cache.title".localized, systemImage: "internaldrive")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(palette.style == .native ? Color.primary : .white)

                Spacer()

                Text(summaryText)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)

                Button {
                    reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .help("help.refresh".localized)
                .accessibilityLabel("help.refresh".localized)

                Button {
                    clearAllCaches()
                } label: {
                    Text("diagnostics.cache.clearAll".localized)
                        .font(.system(size: 9.5, weight: .semibold))
                }
                .buttonStyle(.tactile)
                .disabled((totalCache ?? 0) == 0)
                .opacity((totalCache ?? 0) == 0 ? 0.4 : 1)
            }

            columnHeader

            VStack(spacing: 4) {
                ForEach(rows) { row in
                    rowView(row)
                }
            }

            Text("diagnostics.cache.assetsCaption".localized)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .padding(10)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(palette.borderColor.opacity(0.3), lineWidth: 1)
        )
        .onAppear {
            reload()
            focusPluginIfNeeded()
        }
        .onChange(of: focusNonce) { _, _ in
            focusPluginIfNeeded()
        }
        .onDisappear {
            reloadTask?.cancel()
            reloadTask = nil
            focusTask?.cancel()
            focusTask = nil
        }
        .confirmationDialog(
            pendingDeletion?.title ?? "",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(deleteButtonTitle(for: pendingDeletion), role: .destructive) {
                if let deletion = pendingDeletion {
                    perform(deletion.action)
                    reload()
                }
                pendingDeletion = nil
            }
            Button("common.cancel".localized, role: .cancel) { pendingDeletion = nil }
        }
    }

    private var columnHeader: some View {
        HStack(spacing: StorageInspectorLayout.spacing) {
            Color.clear.frame(width: StorageInspectorLayout.iconWidth, height: 1)
            Color.clear.frame(width: 1, height: 1)

            Spacer(minLength: 6)

            Text("diagnostics.cache.column.assets".localized)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: StorageInspectorLayout.valueWidth, alignment: .trailing)
            Text("· \("diagnostics.cache.column.data".localized)")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: StorageInspectorLayout.valueWidth, alignment: .trailing)
            Text("· \("diagnostics.cache.column.cache".localized)")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: StorageInspectorLayout.valueWidth, alignment: .trailing)

            Color.clear.frame(
                width: StorageInspectorLayout.trailingControlWidth,
                height: 1
            )
            Color.clear.frame(
                width: StorageInspectorLayout.trailingControlWidth,
                height: 1
            )
        }
        .padding(.horizontal, StorageInspectorLayout.horizontalPadding)
    }

    private func rowView(_ row: PluginStorageRow) -> some View {
        let isFlashing = flashingPluginId == row.kind.pluginId

        return HStack(spacing: StorageInspectorLayout.spacing) {
            Image(systemName: row.icon)
                .font(.system(size: 11))
                .foregroundColor(row.color)
                .frame(width: StorageInspectorLayout.iconWidth)

            Text(row.name)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer(minLength: 6)

            storageValue(row.assetsBytes)
            storageValue(row.dataBytes)
            storageValue(row.cacheBytes)

            Button {
                NSWorkspace.shared.selectFile(row.revealURL.path, inFileViewerRootedAtPath: "")
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 10))
                    .frame(
                        width: StorageInspectorLayout.trailingControlWidth,
                        height: StorageInspectorLayout.trailingControlWidth
                    )
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .help("diagnostics.cache.reveal".localized)
            .accessibilityLabel("diagnostics.cache.reveal".localized)

            Menu {
                rowMenu(row)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 11))
                    .frame(
                        width: StorageInspectorLayout.trailingControlWidth,
                        height: StorageInspectorLayout.trailingControlWidth
                    )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .frame(
                width: StorageInspectorLayout.trailingControlWidth,
                height: StorageInspectorLayout.trailingControlWidth
            )
            .foregroundColor(.secondary)
            .help("diagnostics.cache.actions".localized)
            .opacity(rowHasMenuActions(row) ? 1 : 0)
            .allowsHitTesting(rowHasMenuActions(row))
        }
        .padding(.horizontal, StorageInspectorLayout.horizontalPadding)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(
                    isFlashing
                        ? palette.primaryAccent.opacity(0.14)
                        : Color.primary.opacity(0.025)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(
                    isFlashing
                        ? palette.primaryAccent.opacity(0.55)
                        : Color.clear,
                    lineWidth: 1
                )
        )
        .id(PluginStorageFocus.rowID(for: row.kind))
    }

    private func storageValue(_ bytes: Int64?) -> some View {
        Text(bytes.map(PurahPluginFileStorage.format) ?? "…")
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundColor(.secondary)
            .frame(width: StorageInspectorLayout.valueWidth, alignment: .trailing)
    }

    @ViewBuilder
    private func rowMenu(_ row: PluginStorageRow) -> some View {
        if (row.cacheBytes ?? 0) > 0 {
            Button {
                PluginStorageScanner.clearContents(of: row.cacheLocations)
                reload()
            } label: {
                Label("diagnostics.cache.clearCache".localized, systemImage: "trash")
            }
        }

        if (row.dataBytes ?? 0) > 0 {
            Button(role: .destructive) {
                pendingDeletion = PendingStorageDeletion(
                    title: PluginStorageConfirmationCopy.title(for: row.kind, name: row.name),
                    action: .data(
                        containers: row.dataContainerLocations,
                        entries: row.dataEntryLocations
                    )
                )
            } label: {
                Label("diagnostics.cache.deleteData".localized, systemImage: "trash.slash")
            }
        }

        if row.kind == .leftovers, !row.leftoverDirectories.isEmpty {
            Button(role: .destructive) {
                pendingDeletion = PendingStorageDeletion(
                    title: String(
                        format: "diagnostics.cache.confirmLeftovers".localized,
                        Int64(row.leftoverDirectories.count)
                    ),
                    action: .removeDirectories(row.leftoverDirectories)
                )
            } label: {
                Label("diagnostics.cache.deleteLeftovers".localized, systemImage: "trash.slash")
            }
        }
    }

    private func rowHasMenuActions(_ row: PluginStorageRow) -> Bool {
        (row.cacheBytes ?? 0) > 0 ||
        (row.dataBytes ?? 0) > 0 ||
        (row.kind == .leftovers && !row.leftoverDirectories.isEmpty)
    }

    private var summaryText: String {
        String(
            format: "diagnostics.cache.summary".localized,
            formattedTotal(totalAssets),
            formattedTotal(totalData),
            formattedTotal(totalCache)
        )
    }

    private func formattedTotal(_ value: Int64?) -> String {
        value.map(PurahPluginFileStorage.format) ?? "…"
    }

    private func total(_ keyPath: KeyPath<PluginStorageRow, Int64?>) -> Int64? {
        guard !rows.isEmpty else { return nil }
        var total: Int64 = 0
        for row in rows {
            guard let value = row[keyPath: keyPath] else { return nil }
            total += value
        }
        return total
    }

    private func deleteButtonTitle(for deletion: PendingStorageDeletion?) -> String {
        guard let deletion else { return "diagnostics.cache.deleteData".localized }
        switch deletion.action {
        case .removeDirectories:
            return "diagnostics.cache.deleteLeftovers".localized
        case .data:
            return "diagnostics.cache.deleteData".localized
        }
    }

    private func perform(_ action: StorageDeletionAction) {
        switch action {
        case .data(let containers, let entries):
            PluginStorageScanner.deleteData(containers: containers, entries: entries)
        case .removeDirectories(let urls):
            let fileManager = FileManager.default
            for url in urls {
                try? fileManager.removeItem(at: url)
            }
        }
    }

    private func clearAllCaches() {
        PluginStorageScanner.clearContents(of: rows.flatMap(\.cacheLocations))
        reload()
    }

    private func focusPluginIfNeeded() {
        guard let focusedPluginId,
              rows.contains(where: { $0.kind.pluginId == focusedPluginId }) else {
            return
        }

        focusTask?.cancel()
        withAnimation(PurahMotionPolicy.surface) {
            flashingPluginId = focusedPluginId
        }

        focusTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(PurahMotionPolicy.surface) {
                if flashingPluginId == focusedPluginId {
                    flashingPluginId = nil
                }
            }
        }
    }

    private func reload() {
        guard reloadTask == nil else { return }

        let plugins = injectedPlugins ?? PluginRegistry.shared.allPlugins.map {
            PluginStoragePluginSpec(
                id: $0.manifest.id,
                name: $0.manifest.displayName,
                icon: $0.manifest.systemIcon,
                colorHex: $0.manifest.defaultColorHex
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        let targets = PluginStorageScanner.targets(plugins: plugins, roots: roots)
        rows = targets.map { makeRow(for: $0, plugins: plugins, measurement: nil) }

        let roots = roots
        reloadTask = Task { @MainActor in
            let worker = Task.detached(priority: .utility) {
                PluginStorageScanner.scan(plugins: plugins, roots: roots)
            }
            let measurements = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard !Task.isCancelled else { return }

            let byID = Dictionary(uniqueKeysWithValues: measurements.map { ($0.target.id, $0) })
            rows = targets.compactMap { target in
                guard let measurement = byID[target.id] else { return nil }
                return makeRow(for: target, plugins: plugins, measurement: measurement)
            }

            if let leftovers = measurements.first(where: { $0.target.kind == .leftovers }),
               !leftovers.leftoverDirectories.isEmpty {
                rows.append(
                    makeRow(for: leftovers.target, plugins: plugins, measurement: leftovers)
                )
            }
            reloadTask = nil
        }
    }

    private func makeRow(
        for target: PluginStorageTarget,
        plugins: [PluginStoragePluginSpec],
        measurement: PluginStorageMeasurement?
    ) -> PluginStorageRow {
        let presentation: (name: String, icon: String, colorHex: String, revealURL: URL)
        switch target.kind {
        case .plugin(let id):
            let plugin = plugins.first(where: { $0.id == id })
            presentation = (
                plugin?.name ?? id,
                plugin?.icon ?? "puzzlepiece.extension",
                plugin?.colorHex ?? "#8E8E93",
                target.rootURL
            )
        case .clipboard:
            presentation = (
                "diagnostics.cache.clipboardHistory".localized,
                "doc.on.clipboard.fill",
                "#64D2FF",
                roots.clipboard
            )
        case .vitals:
            presentation = (
                "diagnostics.cache.vitals".localized,
                "waveform.path.ecg",
                "#FF375F",
                roots.vitals
            )
        case .leftovers:
            presentation = (
                "diagnostics.cache.leftovers".localized,
                "shippingbox.fill",
                "#8E8E93",
                roots.pluginsBase
            )
        }

        return PluginStorageRow(
            id: target.id,
            kind: target.kind,
            name: presentation.name,
            icon: presentation.icon,
            color: Color(hex: presentation.colorHex),
            revealURL: presentation.revealURL,
            assetsBytes: measurement?.assetsBytes,
            dataBytes: measurement?.dataBytes,
            cacheBytes: measurement?.cacheBytes,
            dataLocations: measurement?.dataLocations ?? [],
            dataContainerLocations: measurement?.dataContainerLocations ?? [],
            dataEntryLocations: measurement?.dataEntryLocations ?? [],
            cacheLocations: measurement?.cacheLocations ?? [],
            leftoverDirectories: measurement?.leftoverDirectories ?? []
        )
    }
}

private enum StorageInspectorLayout {
    static let spacing: CGFloat = 7
    static let iconWidth: CGFloat = 14
    static let valueWidth: CGFloat = 62
    static let trailingControlWidth: CGFloat = 18
    static let horizontalPadding: CGFloat = 8
}

struct PluginStoragePluginSpec: Sendable, Equatable {
    let id: String
    let name: String
    let icon: String
    let colorHex: String
}

enum PluginStorageRowKind: Sendable, Equatable {
    case plugin(String)
    case clipboard
    case vitals
    case leftovers

    var id: String {
        switch self {
        case .plugin(let id): return "plugin:\(id)"
        case .clipboard: return "app:clipboard"
        case .vitals: return "app:vitals"
        case .leftovers: return "app:leftovers"
        }
    }

    var pluginId: String? {
        guard case .plugin(let id) = self else { return nil }
        return id
    }
}

enum PluginStorageConfirmationCopy {
    @MainActor
    static func title(for kind: PluginStorageRowKind, name: String) -> String {
        switch kind {
        case .clipboard:
            return "diagnostics.cache.confirmClipboard".localized
        case .vitals:
            return "diagnostics.cache.confirmVitals".localized
        case .plugin, .leftovers:
            return String(
                format: "diagnostics.cache.confirmData".localized,
                name
            )
        }
    }
}

struct PluginStorageTarget: Sendable, Equatable {
    let kind: PluginStorageRowKind
    let rootURL: URL

    var id: String { kind.id }
}

struct PluginStorageMeasurement: Sendable {
    let target: PluginStorageTarget
    let assetsBytes: Int64
    let dataBytes: Int64
    let cacheBytes: Int64
    let dataLocations: [URL]
    let dataContainerLocations: [URL]
    let dataEntryLocations: [URL]
    let cacheLocations: [URL]
    let leftoverDirectories: [URL]
}

enum PluginStorageScanner {
    static func measure(
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

    static func targets(
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

    static func scan(
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

    static func leftoverDirectories(
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

    static func clearContents(of directories: [URL]) {
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

    static func deleteData(containers: [URL], entries: [URL]) {
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

private struct PluginStorageRow: Identifiable {
    let id: String
    let kind: PluginStorageRowKind
    let name: String
    let icon: String
    let color: Color
    let revealURL: URL
    let assetsBytes: Int64?
    let dataBytes: Int64?
    let cacheBytes: Int64?
    let dataLocations: [URL]
    let dataContainerLocations: [URL]
    let dataEntryLocations: [URL]
    let cacheLocations: [URL]
    let leftoverDirectories: [URL]
}

private struct PendingStorageDeletion {
    let title: String
    let action: StorageDeletionAction
}

private enum StorageDeletionAction {
    case data(containers: [URL], entries: [URL])
    case removeDirectories([URL])
}
