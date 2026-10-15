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
    public func adaptiveDrawerWidth(store: PurahWorkspaceStore) -> CGFloat? { 360.0 }

    public var supportedDropTypes: [UTType] { [.fileURL, .url] }

    public func onDrop(providers: [NSItemProvider], context: PurahPluginContext) -> Bool {
        let pasteboard = NSPasteboard(name: .drag)
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            for url in urls {
                state.addFile(url: url)
                context.performHaptic(.alignment)
                context.showToast("Stashed \(url.lastPathComponent)", "tray.and.arrow.down.fill")
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
                            state.addFile(url: fileURL)
                            context.performHaptic(.alignment)
                            context.showToast("Stashed \(fileURL.lastPathComponent)", "tray.and.arrow.down.fill")
                        }
                    }
                }
            } else {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url = url {
                        Task { @MainActor in
                            state.addFile(url: url)
                            context.performHaptic(.alignment)
                            context.showToast("Stashed \(url.lastPathComponent)", "tray.and.arrow.down.fill")
                        }
                    }
                }
            }
        }
        return true
    }
}

// MARK: - Reactive Live Rail Bar View for Music Plugin

public struct ShelfPluginSettingsView: View {
    public let state: ShelfPluginState
    public let store: PurahWorkspaceStore

    public init(state: ShelfPluginState, store: PurahWorkspaceStore = PurahWorkspaceStore()) {
        self.state = state
        self.store = store
    }

    public init(store: PurahWorkspaceStore) {
        let pluginState = (PluginRegistry.shared.plugin(for: "shelf") as? DropShelfPlugin)?.state ?? ShelfPluginState()
        self.init(state: pluginState, store: store)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Toggle("shelf.settings.autoRemoveOnDrag".localized, isOn: Binding(
                    get: { state.autoRemoveOnDrag },
                    set: {
                        state.autoRemoveOnDrag = $0
                        state.save()
                    }
                ))
                .font(.caption)

                Text("shelf.settings.autoRemoveSubtitle".localized)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            HStack {
                Text(String(format: "shelf.settings.stashedFiles".localized, state.files.count))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                let starredCount = state.files.filter { $0.isFavorite }.count
                if starredCount > 0 {
                    Text(String(format: "shelf.settings.starred".localized, starredCount))
                        .font(.caption2)
                        .foregroundColor(Color(hex: "#FF9F0A"))
                }
            }

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

