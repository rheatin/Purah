// Sources/PurahUI/Plugins/PluginRegistry.swift
import SwiftUI
import PurahCore

@MainActor
public final class PluginRegistry: PluginMarketLifecycleDelegate, Sendable {
    public static let shared = PluginRegistry()

    private var registeredPlugins: [String: any PurahPodPlugin] = [:]
    private var catalogPlugins: [String: any PurahPodPlugin] = [:]

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
    }

    public func register(_ plugin: any PurahPodPlugin, store: PurahWorkspaceStore? = nil) {
        catalogPlugins[plugin.manifest.id] = plugin
        registeredPlugins[plugin.manifest.id] = plugin
        if let store {
            store.registerCapabilityProvider(plugin)
            plugin.onMount(store: store)
        }
    }

    public func bindStore(_ store: PurahWorkspaceStore, marketManager: PluginMarketManager? = nil) {
        let market = marketManager ?? PluginMarketManager(store: store)
        market.lifecycleDelegate = self
        PluginMarketManager.globalLifecycleDelegate = self
        for plugin in catalogPlugins.values {
            if market.isInstalled(id: plugin.manifest.id) {
                registeredPlugins[plugin.manifest.id] = plugin
                store.registerCapabilityProvider(plugin)
                plugin.onMount(store: store)
            } else {
                registeredPlugins.removeValue(forKey: plugin.manifest.id)
                store.unregisterCapabilityProvider(for: plugin.manifest.id)
            }
        }
    }

    public func unregister(id: String, store: PurahWorkspaceStore? = nil) {
        if let plugin = registeredPlugins.removeValue(forKey: id) {
            if let store {
                store.unregisterCapabilityProvider(for: id)
                plugin.onUnmount(store: store)
            }
        }
        if id == "terminal" {
            TerminalManager.shared.stopProcess()
        }
    }

    public func plugin(for id: String) -> (any PurahPodPlugin)? {
        registeredPlugins[id]
    }

    public func catalogPlugin(for id: String) -> (any PurahPodPlugin)? {
        catalogPlugins[id]
    }

    public var allPlugins: [any PurahPodPlugin] {
        Array(registeredPlugins.values)
    }

    public var allCatalogPlugins: [any PurahPodPlugin] {
        Array(catalogPlugins.values)
    }

    // MARK: - PluginMarketLifecycleDelegate
    public func pluginMarketDidInstall(id: String, store: PurahWorkspaceStore) {
        if let plugin = catalogPlugins[id] {
            register(plugin, store: store)
        }
    }

    public func pluginMarketDidUninstall(id: String, store: PurahWorkspaceStore) {
        unregister(id: id, store: store)
    }
}
