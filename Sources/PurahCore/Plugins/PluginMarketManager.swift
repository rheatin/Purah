// Sources/PurahCore/Plugins/PluginMarketManager.swift
import Foundation
import Observation

@MainActor
public protocol PluginMarketLifecycleDelegate: AnyObject, Sendable {
    func pluginMarketDidInstall(id: String, store: PurahWorkspaceStore)
    func pluginMarketDidUninstall(id: String, store: PurahWorkspaceStore)
    func manifest(for id: String) -> PurahPluginManifest?
    /// Whether a plugin implementation (not just a manifest) is registered for
    /// this id. Defaults to `true` so delegates that predate the check keep
    /// working; the live registry answers with an exact lookup.
    func hasImplementation(for id: String) -> Bool
}

public extension PluginMarketLifecycleDelegate {
    func manifest(for id: String) -> PurahPluginManifest? { nil }
    func hasImplementation(for id: String) -> Bool { true }
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
    private weak var store: PurahWorkspaceStore?

    @ObservationIgnored
    public weak var lifecycleDelegate: (any PluginMarketLifecycleDelegate)?

    @ObservationIgnored
    private let userDefaults: UserDefaults

    @ObservationIgnored
    private let userDefaultsKey = "purah.installedPluginIds"

    public static let defaultInstalledIds: Set<String> = Set(PurahWorkspaceStore.defaultPods().map(\.id))

    public init(
        store: PurahWorkspaceStore? = nil,
        availableCatalog: [PurahPluginManifest] = PurahPluginManifest.fullCatalog,
        userDefaults: UserDefaults = .standard,
        lifecycleDelegate: (any PluginMarketLifecycleDelegate)? = nil
    ) {
        self.store = store
        self.availableCatalog = availableCatalog
        self.userDefaults = userDefaults
        self.lifecycleDelegate = lifecycleDelegate ?? Self.globalLifecycleDelegate

        let autoInstallAIKey = "purah.didAutoInstallAIPlugin"
        let shouldAutoInstallAI = !userDefaults.bool(forKey: autoInstallAIKey)

        var resolvedInstalledIds: Set<String>
        if let saved = userDefaults.stringArray(forKey: userDefaultsKey) {
            resolvedInstalledIds = Set(saved)
            if shouldAutoInstallAI {
                resolvedInstalledIds.insert("ai")
            }
            if let store {
                let managedIds = Set(availableCatalog.map(\.id)).union(PurahWorkspaceStore.defaultPods().map(\.id))
                store.pods.removeAll { managedIds.contains($0.id) && !resolvedInstalledIds.contains($0.id) }
                resolvedInstalledIds.formUnion(store.pods.map(\.id))
                store.invalidateLayoutCache()
            }
        } else {
            resolvedInstalledIds = Set(store?.pods.map(\.id) ?? PurahWorkspaceStore.defaultPods().map(\.id))
            if shouldAutoInstallAI {
                resolvedInstalledIds.insert("ai")
            }
        }

        if shouldAutoInstallAI {
            userDefaults.set(true, forKey: autoInstallAIKey)
            resolvedInstalledIds.insert("ai")
            if let store {
                if let index = store.pods.firstIndex(where: { $0.id == "ai" }) {
                    store.pods[index].isEnabled = true
                } else if let defAI = PurahWorkspaceStore.defaultPods().first(where: { $0.id == "ai" }) {
                    var pod = defAI
                    pod.isEnabled = true
                    store.pods.append(pod)
                }
                store.invalidateLayoutCache()
            }
        }

        self.installedPluginIds = resolvedInstalledIds
        self.enabledPluginIds = Set(store?.pods.filter(\.isEnabled).map(\.id) ?? [])
        if shouldAutoInstallAI {
            self.enabledPluginIds.insert("ai")
            savePersistentState()
        }
        loadPersistentState()
    }

    public func isInstalled(id: String) -> Bool {
        installedPluginIds.contains(id)
    }

    public func isEnabled(id: String) -> Bool {
        if let pod = store?.pods.first(where: { $0.id == id }) {
            return pod.isEnabled
        }
        return enabledPluginIds.contains(id)
    }

    /// Installs a plugin that has a real implementation registered.
    ///
    /// A manifest alone is metadata; mounting a pod from one produced a rail
    /// entry whose drawer could only echo the manifest's own description back
    /// at the user. Installs are therefore refused unless the lifecycle
    /// delegate can name an implementation for the id.
    @discardableResult
    public func install(id: String) -> Bool {
        let activeDelegate = lifecycleDelegate ?? Self.globalLifecycleDelegate
        let hasImplementation = activeDelegate?.hasImplementation(for: id) ?? true
        guard hasImplementation else {
            DiagnosticLogger.shared.info("Market", "Install refused: no plugin implementation for \(id)")
            return false
        }

        installedPluginIds.insert(id)
        enabledPluginIds.insert(id)
        savePersistentState()

        guard let store else { return true }

        if let index = store.pods.firstIndex(where: { $0.id == id }) {
            store.pods[index].isEnabled = true
        } else {
            if let defaultPod = PurahWorkspaceStore.defaultPods().first(where: { $0.id == id }) {
                var pod = defaultPod
                pod.isEnabled = true
                store.pods.append(pod)
            } else if let manifest = availableCatalog.first(where: { $0.id == id }) ?? activeDelegate?.manifest(for: id) {
                let pod = manifest.makeDefaultSlotPod(isEnabled: true)
                store.pods.append(pod)
            }
        }

        activeDelegate?.pluginMarketDidInstall(id: id, store: store)

        store.autoLayoutAll()
        return true
    }

    public func install(pluginId: String) {
        install(id: pluginId)
    }

    public func uninstall(id: String) {
        installedPluginIds.remove(id)
        enabledPluginIds.remove(id)
        savePersistentState()

        guard let store else { return }

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
        if store?.pods.contains(where: { $0.id == manifest.id }) == true {
            installedPluginIds.insert(manifest.id)
            enabledPluginIds.insert(manifest.id)
        }
    }

    public func toggleEnabled(id: String) {
        guard let store else { return }
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
        // Derive enabled IDs strictly from store.pods (the single source of truth for pod state)
        if let store {
            self.enabledPluginIds = Set(store.pods.filter(\.isEnabled).map(\.id))
            store.invalidateLayoutCache()
        }
    }

    public func savePersistentState() {
        userDefaults.set(Array(installedPluginIds), forKey: userDefaultsKey)
        if let store {
            let enabled = Array(store.pods.filter(\.isEnabled).map(\.id))
            UserDefaults.standard.setValue(enabled, forKey: "purah.market.enabledPluginIds")
        }
    }
}
