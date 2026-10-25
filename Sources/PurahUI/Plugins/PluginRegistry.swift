// Sources/PurahUI/Plugins/PluginRegistry.swift
import SwiftUI
import PurahCore

@MainActor
public final class PluginRegistry: PluginMarketLifecycleDelegate, Sendable {
    public static let shared = PluginRegistry()

    private var registeredPlugins: [String: any PurahPodPlugin] = [:]
    public var plugins: [String: any PurahPodPlugin] { registeredPlugins }
    private var catalogPlugins: [String: any PurahPodPlugin] = [:]
    private var pollingTasks: [String: Task<Void, Never>] = [:]
    private var mountedPluginIds: Set<String> = []
    private weak var boundStore: PurahWorkspaceStore?

    public init() {
        registerBuiltInPlugins()
        PluginMarketManager.globalLifecycleDelegate = self
    }

    public func registerBuiltInPlugins() {
        register(HardwareVitalsPlugin())
        register(ScriptRunwayPlugin())
        register(TerminalPlugin())
        register(QuickNotesPlugin())
        register(DropShelfPlugin())
        register(MusicPlugin())
        register(CalendarPlugin())
        register(TodoPlugin())
        register(ClipboardPlugin())
        register(AIAssistantPlugin())

        for manifest in PurahPluginManifest.communityCatalog {
            catalogPlugins[manifest.id] = CommunityPodPlugin(manifest: manifest)
        }
    }

    public func registerManifestOnly(_ manifest: PurahPluginManifest) {
        let plugin = CommunityPodPlugin(manifest: manifest)
        catalogPlugins[manifest.id] = plugin
    }

    public func register(_ plugin: any PurahPodPlugin, store: PurahWorkspaceStore? = nil) {
        let id = plugin.manifest.id
        catalogPlugins[id] = plugin
        registeredPlugins[id] = plugin
        if let store {
            self.boundStore = store
            store.marketManager.addCatalogManifest(plugin.manifest)
            store.registerCapabilityProvider(plugin)
            mountPlugin(id: id, store: store)
        }
    }

    public func bindStore(_ store: PurahWorkspaceStore, marketManager: PluginMarketManager? = nil) {
        self.boundStore = store
        let market = marketManager ?? store.marketManager
        store.setMarketManager(market)
        market.lifecycleDelegate = self
        PluginMarketManager.globalLifecycleDelegate = self

        // Capability-driven: every plugin that owns a decomposed mode
        // implements `setDecomposed`, so the host never needs to know which
        // pod ids happen to be stepped today (this used to special-case
        // "scripts" and "vitals" only).
        store.onDecomposedStateSync = { [weak self] podId, isDecomp in
            self?.plugin(for: podId)?.setDecomposed(isDecomp, store: store)
        }
        for plugin in catalogPlugins.values {
            let id = plugin.manifest.id
            if market.isInstalled(id: id) {
                registeredPlugins[id] = plugin
                store.registerCapabilityProvider(plugin)
                // Strict on-demand mount: only mount if the pod is actually enabled on an active rail!
                // Disabled plugins (e.g. terminal, clipboard by default) remain 100% idle with 0 resource footprint.
                let isEnabledOnRail = store.pods.contains(where: { $0.id == id && $0.isEnabled })
                if isEnabledOnRail {
                    mountPlugin(id: id, store: store)
                } else {
                    unmountPlugin(id: id, store: store)
                }
            } else {
                if let _ = registeredPlugins.removeValue(forKey: id) {
                    store.unregisterCapabilityProvider(for: id)
                    unmountPlugin(id: id, store: store)
                }
            }
        }
    }

    public func mountPlugin(id: String, store: PurahWorkspaceStore) {
        guard !mountedPluginIds.contains(id), let plugin = registeredPlugins[id] else { return }
        mountedPluginIds.insert(id)
        plugin.onMount(store: store)
        if let plugin = plugins[id] {
            startPollingIfNeeded(for: plugin, store: store)
        }
        DiagnosticLogger.shared.info("Plugin", "Plugin mounted: \(id) (\(plugin.manifest.displayName))")
    }

    public func unmountPlugin(id: String, store: PurahWorkspaceStore) {
        guard mountedPluginIds.contains(id), let plugin = registeredPlugins[id] ?? catalogPlugins[id] else { return }
        mountedPluginIds.remove(id)
        pollingTasks[id]?.cancel()
        pollingTasks.removeValue(forKey: id)
        stopPolling(for: id)
        plugin.onUnmount(store: store)
        DiagnosticLogger.shared.info("Plugin", "Plugin unmounted: \(id)")
    }

    public func isPluginMounted(id: String) -> Bool {
        mountedPluginIds.contains(id)
    }

    public func unregister(id: String, store: PurahWorkspaceStore? = nil) {
        stopPolling(for: id)
        if let _ = registeredPlugins.removeValue(forKey: id) {
            let targetStore = store ?? boundStore
            if let targetStore {
                targetStore.unregisterCapabilityProvider(for: id)
                unmountPlugin(id: id, store: targetStore)
            } else {
                mountedPluginIds.remove(id)
            }
        }
    }

    private func startPollingIfNeeded(for plugin: any PurahPodPlugin, store: PurahWorkspaceStore) {
        stopPolling(for: plugin.manifest.id)
        guard let interval = plugin.preferredPollingInterval, interval > 0 else { return }
        let pluginId = plugin.manifest.id
        guard store.pods.first(where: { $0.id == pluginId })?.isEnabled ?? true else { return }
        pollingTasks[pluginId] = Task { [weak store] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard let store, !Task.isCancelled else { break }
                guard store.pods.first(where: { $0.id == pluginId })?.isEnabled ?? true else { break }
                let isEnabled = store.pods.contains(where: { $0.id == pluginId && $0.isEnabled })
                if isEnabled && !store.isRailsFrozen {
                    await plugin.onPollingTick(store: store)
                }
            }
        }
    }

    private func stopPolling(for id: String) {
        pollingTasks[id]?.cancel()
        pollingTasks.removeValue(forKey: id)
    }

    public func plugin(for id: String) -> (any PurahPodPlugin)? {
        registeredPlugins[id]
    }

    public func catalogPlugin(for id: String) -> (any PurahPodPlugin)? {
        catalogPlugins[id]
    }

    public func unregisterCatalog(id: String) {
        catalogPlugins.removeValue(forKey: id)
    }

    public var allPlugins: [any PurahPodPlugin] {
        Array(registeredPlugins.values)
    }

    public var allCatalogPlugins: [any PurahPodPlugin] {
        Array(catalogPlugins.values)
    }

    // MARK: - PluginMarketLifecycleDelegate
    public func manifest(for id: String) -> PurahPluginManifest? {
        catalogPlugins[id]?.manifest
    }

    public func pluginMarketDidInstall(id: String, store: PurahWorkspaceStore) {
        if let plugin = catalogPlugins[id] {
            register(plugin, store: store)
        } else if let manifest = PurahPluginManifest.fullCatalog.first(where: { $0.id == id }) {
            let plugin = CommunityPodPlugin(manifest: manifest)
            catalogPlugins[id] = plugin
            register(plugin, store: store)
        }
    }

    public func pluginMarketDidUninstall(id: String, store: PurahWorkspaceStore) {
        unregister(id: id, store: store)
    }
}
