import SwiftUI
import AppKit
import PurahCore
import UniformTypeIdentifiers

public struct DropShelfPlugin: PurahPodPlugin {
    public nonisolated let manifest = PurahPluginManifest(
        id: "shelf",
        displayName: "Drop Shelf",
        systemIcon: "tray.and.arrow.down.fill",
        author: "Project Purah",
        version: "0.1.0",
        description: "Transient holding area for dragged files and assets",
        defaultEdge: .left,
        preferredZone: .quickFlick,
        ergonomicWeight: 35.0,
        minLengthRatio: 0.16,
        defaultColorHex: "#BF5AF2",
        permissions: [.fileSystem]
    )

    public let state: ShelfPluginState

    public init(state: ShelfPluginState = ShelfPluginState()) {
        self.state = state
    }

    public func makeRailBarView(context: PurahPluginContext) -> AnyView {
        AnyView(
            RailBarAmbientView(
                type: .shelf,
                hasContent: !state.files.isEmpty,
                color: context.accentColor,
                barWidth: context.railWidth
            )
            .frame(width: context.railWidth, height: context.slotHeight)
        )
    }

    public func makeDrawerView(context: PurahPluginContext) -> AnyView {
        AnyView(DropShelfDrawerView(state: state, store: context.store))
    }

    public func makeHeaderAccessoryView(context: PurahPluginContext) -> AnyView? {
        let text = state.selectedFileIds.isEmpty
            ? "\(state.files.count)"
            : "\(state.selectedFileIds.count)/\(state.files.count)"
        return AnyView(PurahHeaderBadge(text, tint: context.accentColor))
    }

    public func makeHeaderTrailingView(context: PurahPluginContext) -> AnyView? {
        AnyView(ShelfHeaderTools(state: state, context: context))
    }

    public func makeSettingsView(store: PurahWorkspaceStore) -> AnyView? {
        AnyView(ShelfPluginSettingsView(state: state, store: store))
    }

    public func onMount(store: PurahWorkspaceStore) {
        state.mount(store: store)
    }

    public func onUnmount(store: PurahWorkspaceStore) {
        state.unmount(store: store)
    }

    public func minimumDrawerHeight(store: PurahWorkspaceStore) -> CGFloat { 130.0 }
    public func preferredDrawerHeight(store: PurahWorkspaceStore) -> CGFloat { 250.0 }
    public func adaptiveDrawerWidth(store: PurahWorkspaceStore) -> CGFloat? { 360.0 }

    public var supportedDropTypes: [UTType] {
        [.fileURL, .image, .png, .tiff, .url, .utf8PlainText, .plainText]
    }

    public func onDrop(providers: [NSItemProvider], context: PurahPluginContext) -> Bool {
        let pasteboard = NSPasteboard(name: .drag)
        if ShelfStashDropDelegate.ingestPasteboard(pasteboard, state: state, store: context.store) {
            if let latest = state.files.first {
                context.showToast("Stashed \(latest.name)", "tray.and.arrow.down.fill")
            }
            return true
        }
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    let url: URL?
                    if let directURL = item as? URL {
                        url = directURL
                    } else if let data = item as? Data, let pathString = String(data: data, encoding: .utf8) {
                        url = URL(fileURLWithPath: pathString)
                    } else {
                        url = nil
                    }
                    if let fileURL = url {
                        Task { @MainActor in
                            // A shelf item dropped back on the shelf's rail is a
                            // round trip, not an export.
                            if ShelfDragSession.shared.carriesAny(of: [fileURL]) {
                                ShelfDragSession.shared.claimSelfDrop()
                            }
                            state.addFile(url: fileURL)
                            context.performHaptic(.alignment)
                            context.showToast("Stashed \(fileURL.lastPathComponent)", "tray.and.arrow.down.fill")
                        }
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    if let data, !data.isEmpty {
                        Task { @MainActor in
                            if let item = state.addDroppedImageData(data) {
                                context.performHaptic(.alignment)
                                context.showToast("Stashed \(item.name)", "tray.and.arrow.down.fill")
                            }
                        }
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url = url {
                        Task { @MainActor in
                            if let scheme = url.scheme?.lowercased(), (scheme == "http" || scheme == "https") {
                                if let item = state.addDroppedWebLink(url) {
                                    context.performHaptic(.alignment)
                                    context.showToast("Stashed \(item.name)", "tray.and.arrow.down.fill")
                                }
                            } else {
                                if ShelfDragSession.shared.carriesAny(of: [url]) {
                                    ShelfDragSession.shared.claimSelfDrop()
                                }
                                state.addFile(url: url)
                                context.performHaptic(.alignment)
                                context.showToast("Stashed \(url.lastPathComponent)", "tray.and.arrow.down.fill")
                            }
                        }
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                _ = provider.loadObject(ofClass: String.self) { text, _ in
                    if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Task { @MainActor in
                            if let item = state.addDroppedTextSnippet(text) {
                                context.performHaptic(.alignment)
                                context.showToast("Stashed \(item.name)", "tray.and.arrow.down.fill")
                            }
                        }
                    }
                }
            }
        }
        return true
    }
}

// MARK: - Header tools

/// Zip, select-all and clear used to be a second row of text chips inside the
/// drawer, on top of the file list. They are three verbs, so they are three
/// icons in the one row that already holds every other verb.
struct ShelfHeaderTools: View {
    let state: ShelfPluginState
    let context: PurahPluginContext

    /// Clearing the shelf is not undoable from inside Purah, and the trash
    /// sits one click from Select All and Zip. The first click arms it; the
    /// second one clears.
    @State private var isConfirmingClear = false
    @State private var clearArmTimer: Task<Void, Never>?

    private var allSelected: Bool {
        !state.files.isEmpty && state.selectedFileIds.count == state.files.count
    }

    private func armClear() {
        isConfirmingClear = true
        clearArmTimer?.cancel()
        clearArmTimer = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            isConfirmingClear = false
        }
    }

    private func clearShelf() {
        clearArmTimer?.cancel()
        isConfirmingClear = false
        state.clear()
        context.store._shelfFiles = state.files
        context.performHaptic(.levelChange)
    }

    var body: some View {
        PurahHeaderGroup {
            PurahHeaderButton(
                systemImage: allSelected ? "checkmark.circle.fill" : "checkmark.circle",
                help: allSelected ? "dropshelf.deselectAll".localized : "dropshelf.selectAll".localized,
                tint: context.accentColor,
                isActive: allSelected
            ) {
                if allSelected {
                    state.clearSelection()
                } else {
                    state.selectAll()
                }
                context.performHaptic(.alignment)
            }

            PurahHeaderButton(systemImage: "archivebox", help: "dropshelf.zipHelp".localized) {
                if let zipItem = state.compressFilesToZip() {
                    context.store._shelfFiles = state.files
                    context.performHaptic(.levelChange)
                    context.showToast("Created \(zipItem.name)", "archivebox.fill")
                }
            }

            if isConfirmingClear {
                PurahHeaderButton(
                    systemImage: "trash.fill",
                    help: "destructive.confirmClearHelp".localized,
                    tint: Color(hex: PurahHeaderMetrics.destructiveHex),
                    isActive: true
                ) {
                    clearShelf()
                }
            } else {
                PurahHeaderButton(
                    systemImage: "trash",
                    help: "dropshelf.clearAll".localized,
                    role: .destructive
                ) {
                    armClear()
                }
            }
        }
    }
}

// MARK: - Reactive Live Rail Bar View for Music Plugin

public struct ShelfPluginSettingsView: View {
    public let state: ShelfPluginState
    public let store: PurahWorkspaceStore

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    public init(state: ShelfPluginState, store: PurahWorkspaceStore = PurahWorkspaceStore()) {
        self.state = state
        self.store = store
    }

    public init(store: PurahWorkspaceStore) {
        let pluginState = (PluginRegistry.shared.plugin(for: "shelf") as? DropShelfPlugin)?.state ?? ShelfPluginState()
        self.init(state: pluginState, store: store)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Card 1: Drop Shelf Behavior
            PurahPluginSettingsCard(
                title: "Drop Shelf Behavior",
                subtitle: "Temporary drag-and-drop workspace and stash files",
                icon: "tray.and.arrow.down.fill",
                iconColor: palette.primaryAccent
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("shelf.settings.autoRemoveOnDrag".localized)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(.primary)
                            Text("shelf.settings.autoRemoveSubtitle".localized)
                                .font(.system(size: 9.5))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { state.autoRemoveOnDrag },
                            set: {
                                state.autoRemoveOnDrag = $0
                                state.save()
                            }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                        .purahRowAccessibility("shelf.settings.autoRemoveOnDrag".localized, detail: "shelf.settings.autoRemoveSubtitle".localized)
                    }
                    .padding(9)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.primary.opacity(0.03))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(palette.borderColor.opacity(0.2), lineWidth: 0.8)
                    )

                    HStack(spacing: 8) {
                        HStack(spacing: 5) {
                            Image(systemName: "doc.on.doc.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Text(String(format: "shelf.settings.stashedFiles".localized, state.files.count))
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(.primary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.04))
                        .cornerRadius(6)

                        Spacer()

                        let starredCount = state.files.filter { $0.isFavorite }.count
                        if starredCount > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(Color(hex: "#FF9F0A"))
                                Text(String(format: "shelf.settings.starred".localized, starredCount))
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundColor(Color(hex: "#FF9F0A"))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.yellow.opacity(0.1))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.yellow.opacity(0.25), lineWidth: 0.8)
                            )
                        }
                    }
                }
            }

            // Card 2: Storage Policy Section
            PurahStoragePolicySection(
                retention: Binding(
                    get: { state.retentionPeriod },
                    set: {
                        state.retentionPeriod = $0
                        state.save()
                    }
                ),
                quota: Binding(
                    get: { state.diskQuota },
                    set: {
                        state.diskQuota = $0
                        state.save()
                    }
                ),
                autoPrune: Binding(
                    get: { state.autoPrune },
                    set: {
                        state.autoPrune = $0
                        state.save()
                    }
                ),
                fileStorage: state.fileStorage,
                onClearAll: {
                    state.clear()
                    store._shelfFiles = state.files
                }
            )
        }
    }
}

