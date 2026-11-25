// Sources/PurahUI/Settings/PluginStorageInspectorView.swift
import SwiftUI
import AppKit
import PurahCore

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

    static func isFlashing(focusedPluginId: String?, kind: PluginStorageRowKind) -> Bool {
        guard let focusedPluginId,
              let pluginId = kind.pluginId else { return false }
        return focusedPluginId == pluginId
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
    private let store: PurahWorkspaceStore?
    private let onMeasurements: (([PluginStorageMeasurement]) -> Void)?

    private var palette: ThemePalette { ThemeManager.shared.palette }

    public init(
        store: PurahWorkspaceStore? = nil,
        focusedPluginId: String? = nil,
        focusNonce: Int = 0
    ) {
        self.init(
            roots: .live,
            plugins: nil,
            store: store,
            focusedPluginId: focusedPluginId,
            focusNonce: focusNonce,
            onMeasurements: nil
        )
    }

    public init(
        roots: PluginStorageRoots,
        store: PurahWorkspaceStore? = nil,
        focusedPluginId: String? = nil,
        focusNonce: Int = 0
    ) {
        self.init(
            roots: roots,
            plugins: nil,
            store: store,
            focusedPluginId: focusedPluginId,
            focusNonce: focusNonce,
            onMeasurements: nil
        )
    }

    init(
        roots: PluginStorageRoots,
        plugins: [PluginStoragePluginSpec]?,
        store: PurahWorkspaceStore? = nil,
        focusedPluginId: String? = nil,
        focusNonce: Int = 0,
        onMeasurements: (([PluginStorageMeasurement]) -> Void)? = nil
    ) {
        self.roots = roots
        self.injectedPlugins = plugins
        self.store = store
        self.focusedPluginId = focusedPluginId
        self.focusNonce = focusNonce
        self.onMeasurements = onMeasurements
    }

    private var totalAssets: Int64? { total(\.assetsBytes) }
    private var totalData: Int64? { total(\.dataBytes) }
    private var totalCache: Int64? { total(\.cacheBytes) }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(summaryText)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)

                Spacer()

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
        .padding(12)
        .background(palette.surfaceBackground)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(palette.borderColor.opacity(0.4), lineWidth: 1)
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
        let isFlashing = PluginStorageFocus.isFlashing(
            focusedPluginId: flashingPluginId,
            kind: row.kind
        )

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

            if let pluginId = row.kind.pluginId,
               let pkgPath = PluginDynamicLoader.shared.installedPackagePath(for: pluginId),
               FileManager.default.fileExists(atPath: pkgPath) {
                Button {
                    rebuildPackage(at: pkgPath, pluginId: pluginId)
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 10))
                        .frame(
                            width: StorageInspectorLayout.trailingControlWidth,
                            height: StorageInspectorLayout.trailingControlWidth
                        )
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                .help("Rebuild or update plugin from source package")
                .accessibilityLabel("Rebuild or update plugin from source package")
            }

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
        if let pluginId = row.kind.pluginId,
           let pkgPath = PluginDynamicLoader.shared.installedPackagePath(for: pluginId),
           FileManager.default.fileExists(atPath: pkgPath) {
            Button {
                rebuildPackage(at: pkgPath, pluginId: pluginId)
            } label: {
                Label("Rebuild / Update", systemImage: "arrow.triangle.2.circlepath")
            }
        }

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
        (row.kind == .leftovers && !row.leftoverDirectories.isEmpty) ||
        (row.kind.pluginId.flatMap { PluginDynamicLoader.shared.installedPackagePath(for: $0) } != nil)
    }

    private func rebuildPackage(at pkgPath: String, pluginId: String) {
        Task { @MainActor in
            _ = try? await ExternalPluginWorkflowCoordinator.shared.rebuildFromSource(
                packagePath: pkgPath,
                pullUpdates: true,
                store: store
            )
            reload()
        }
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
                // Recycle, never unlink: an uninstalled plugin's folder can still
                // hold a shelf item ingested in Move mode — the only copy there is.
                // A failure leaves the folder in place, so nothing is lost silently.
                var resultingURL: NSURL?
                try? fileManager.trashItem(at: url, resultingItemURL: &resultingURL)
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
            onMeasurements?(measurements)
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
