// Sources/PurahUI/Plugins/PluginRegistry.swift
import SwiftUI
import PurahCore

@MainActor
public final class PluginRegistry {
    public static let shared = PluginRegistry()

    private var registeredPlugins: [String: any PurahPodPlugin] = [:]

    public init() {
        registerBuiltInPlugins()
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
        registeredPlugins[plugin.manifest.id] = plugin
        if let store {
            store.registerCapabilityProvider(plugin)
            plugin.onMount(store: store)
        }
    }

    public func bindStore(_ store: PurahWorkspaceStore) {
        for plugin in registeredPlugins.values {
            store.registerCapabilityProvider(plugin)
            plugin.onMount(store: store)
        }
    }

    public func unregister(id: String, store: PurahWorkspaceStore? = nil) {
        if let plugin = registeredPlugins.removeValue(forKey: id), let store {
            plugin.onUnmount(store: store)
        }
    }

    public func plugin(for id: String) -> (any PurahPodPlugin)? {
        registeredPlugins[id]
    }

    public var allPlugins: [any PurahPodPlugin] {
        Array(registeredPlugins.values)
    }
}
