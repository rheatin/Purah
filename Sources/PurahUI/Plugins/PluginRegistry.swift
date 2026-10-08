// Sources/PurahUI/Plugins/PluginRegistry.swift
import SwiftUI
import PurahCore

@MainActor
public final class PluginRegistry: PluginMarketLifecycleDelegate, Sendable {
    public static let shared = PluginRegistry()

    private var registeredPlugins: [String: any PurahPodPlugin] = [:]
    private var catalogPlugins: [String: any PurahPodPlugin] = [:]
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

        for manifest in PurahPluginManifest.communityCatalog {
            catalogPlugins[manifest.id] = CommunityPodPlugin(manifest: manifest)
        }
    }

    public func registerManifestOnly(_ manifest: PurahPluginManifest) {
        let plugin = CommunityPodPlugin(manifest: manifest)
        catalogPlugins[manifest.id] = plugin
    }

    public func register(_ plugin: any PurahPodPlugin, store: PurahWorkspaceStore? = nil) {
        catalogPlugins[plugin.manifest.id] = plugin
        registeredPlugins[plugin.manifest.id] = plugin
        if let store {
            self.boundStore = store
            store.marketManager.addCatalogManifest(plugin.manifest)
            store.registerCapabilityProvider(plugin)
            plugin.onMount(store: store)
        }
    }

    public func bindStore(_ store: PurahWorkspaceStore, marketManager: PluginMarketManager? = nil) {
        self.boundStore = store
        let market = marketManager ?? store.marketManager
        store.setMarketManager(market)
        market.lifecycleDelegate = self
        PluginMarketManager.globalLifecycleDelegate = self
        for plugin in catalogPlugins.values {
            if market.isInstalled(id: plugin.manifest.id) {
                registeredPlugins[plugin.manifest.id] = plugin
                store.registerCapabilityProvider(plugin)
                plugin.onMount(store: store)
            } else {
                if let removed = registeredPlugins.removeValue(forKey: plugin.manifest.id) {
                    store.unregisterCapabilityProvider(for: plugin.manifest.id)
                    removed.onUnmount(store: store)
                } else {
                    store.unregisterCapabilityProvider(for: plugin.manifest.id)
                    plugin.onUnmount(store: store)
                }
            }
        }
    }

    public func unregister(id: String, store: PurahWorkspaceStore? = nil) {
        if let plugin = registeredPlugins.removeValue(forKey: id) {
            let targetStore = store ?? boundStore
            if let targetStore {
                targetStore.unregisterCapabilityProvider(for: id)
                plugin.onUnmount(store: targetStore)
            } else {
                plugin.onUnmount(store: PurahWorkspaceStore())
            }
        }
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
