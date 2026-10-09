// Sources/PurahCore/Plugins/PluginMarketManager.swift
import Foundation
import Observation

@MainActor
public protocol PluginMarketLifecycleDelegate: AnyObject, Sendable {
    func pluginMarketDidInstall(id: String, store: PurahWorkspaceStore)
    func pluginMarketDidUninstall(id: String, store: PurahWorkspaceStore)
    func manifest(for id: String) -> PurahPluginManifest?
}

public extension PluginMarketLifecycleDelegate {
    func manifest(for id: String) -> PurahPluginManifest? { nil }
}

@Observable
@MainActor
public final class PluginMarketManager: Sendable {
    public static weak var globalLifecycleDelegate: (any PluginMarketLifecycleDelegate)?

    public var installedPluginIds: Set<String> {
        didSet {
            savePersistentState()
        }
    }
    public var enabledPluginIds: Set<String> {
        didSet {
            savePersistentState()
        }
    }
    public var availableCatalog: [PurahPluginManifest]

    @ObservationIgnored
    public let store: PurahWorkspaceStore

    @ObservationIgnored
    public weak var lifecycleDelegate: (any PluginMarketLifecycleDelegate)?

    @ObservationIgnored
    private let userDefaults: UserDefaults

    @ObservationIgnored
    private let userDefaultsKey = "purah.installedPluginIds"

    public init(
        store: PurahWorkspaceStore = PurahWorkspaceStore(),
        availableCatalog: [PurahPluginManifest] = PurahPluginManifest.fullCatalog,
        userDefaults: UserDefaults = .standard,
        lifecycleDelegate: (any PluginMarketLifecycleDelegate)? = nil
    ) {
        self.store = store
        self.availableCatalog = availableCatalog
        self.userDefaults = userDefaults
        self.lifecycleDelegate = lifecycleDelegate ?? Self.globalLifecycleDelegate

        var resolvedInstalledIds: Set<String>
        if let saved = userDefaults.stringArray(forKey: userDefaultsKey) {
            resolvedInstalledIds = Set(saved)
            let managedIds = Set(availableCatalog.map(\.id)).union(PurahWorkspaceStore.defaultPods().map(\.id))
            store.pods.removeAll { managedIds.contains($0.id) && !resolvedInstalledIds.contains($0.id) }
            resolvedInstalledIds.formUnion(store.pods.map(\.id))
            store.autoLayoutAll()
        } else {
            resolvedInstalledIds = Set(store.pods.map(\.id))
        }

        self.installedPluginIds = resolvedInstalledIds
        self.enabledPluginIds = Set(store.pods.filter(\.isEnabled).map(\.id))
        loadPersistentState()
    }

    public func isInstalled(id: String) -> Bool {
        installedPluginIds.contains(id)
    }

    public func isEnabled(id: String) -> Bool {
        if let pod = store.pods.first(where: { $0.id == id }) {
            return pod.isEnabled
        }
        return enabledPluginIds.contains(id)
    }

    public func install(id: String) {
        installedPluginIds.insert(id)
        enabledPluginIds.insert(id)
        savePersistentState()

        if let index = store.pods.firstIndex(where: { $0.id == id }) {
            store.pods[index].isEnabled = true
        } else {
            if let defaultPod = PurahWorkspaceStore.defaultPods().first(where: { $0.id == id }) {
                var pod = defaultPod
                pod.isEnabled = true
                store.pods.append(pod)
            } else if let manifest = availableCatalog.first(where: { $0.id == id }) ?? (lifecycleDelegate ?? Self.globalLifecycleDelegate)?.manifest(for: id) {
                let pod = manifest.makeDefaultSlotPod(isEnabled: true)
                store.pods.append(pod)
            }
        }

        let activeDelegate = lifecycleDelegate ?? Self.globalLifecycleDelegate
        activeDelegate?.pluginMarketDidInstall(id: id, store: store)

        store.autoLayoutAll()
    }

    public func install(pluginId: String) {
        install(id: pluginId)
    }

    public func uninstall(id: String) {
        installedPluginIds.remove(id)
        enabledPluginIds.remove(id)
        savePersistentState()

        let activeDelegate = lifecycleDelegate ?? Self.globalLifecycleDelegate
        activeDelegate?.pluginMarketDidUninstall(id: id, store: store)

        if store.activeDrawerPodId == id {
            store.dismissActiveDrawer()
        }
        store.pinnedDrawerItemIds = store.pinnedDrawerItemIds.filter { !($0 == id || $0.hasPrefix("\(id)-")) }

        store.pods.removeAll { $0.id == id }
        store.unregisterCapabilityProvider(for: id)
        store.autoLayoutAll()
    }

    public func uninstall(pluginId: String) {
        uninstall(id: pluginId)
    }

    public func addCatalogManifest(_ manifest: PurahPluginManifest) {
        if let index = availableCatalog.firstIndex(where: { $0.id == manifest.id }) {
            availableCatalog[index] = manifest
        } else {
            availableCatalog.append(manifest)
        }
        if store.pods.contains(where: { $0.id == manifest.id }) {
            installedPluginIds.insert(manifest.id)
            enabledPluginIds.insert(manifest.id)
        }
    }

    public func toggleEnabled(id: String) {
        store.togglePodEnabled(id: id)
        if let pod = store.pods.first(where: { $0.id == id }) {
            if pod.isEnabled {
                enabledPluginIds.insert(id)
            } else {
                enabledPluginIds.remove(id)
            }
        }
        savePersistentState()
    }

    public func toggleEnabled(pluginId: String) {
        toggleEnabled(id: pluginId)
    }

    public func loadPersistentState() {
        if let savedEnabled = UserDefaults.standard.stringArray(forKey: "purah.market.enabledPluginIds") {
            let savedSet = Set(savedEnabled)
            let managedIds = Set(availableCatalog.map(\.id)).union(PurahWorkspaceStore.defaultPods().map(\.id))
            for i in store.pods.indices where managedIds.contains(store.pods[i].id) {
                store.pods[i].isEnabled = savedSet.contains(store.pods[i].id)
            }
            self.enabledPluginIds = savedSet.union(store.pods.filter(\.isEnabled).map(\.id))
            store.autoLayoutAll()
        }
    }

    public func savePersistentState() {
        userDefaults.set(Array(installedPluginIds), forKey: userDefaultsKey)
        UserDefaults.standard.setValue(Array(enabledPluginIds), forKey: "purah.market.enabledPluginIds")
    }
}
