// Sources/PurahUI/Plugins/PluginDynamicLoader.swift
import SwiftUI
import AppKit
import Foundation
import PurahCore

public enum PluginDynamicLoadError: LocalizedError, Sendable {
    case fileNotFound(String)
    case dlopenFailed(String)
    case missingEntrySymbol(String)
    case invalidPluginType
    case compilationFailed(String)
    /// The dylib declares an ABI the host cannot speak.
    case incompatibleABI(found: String, expected: String)
    /// The dylib or its container is not signed, or the signature is invalid.
    case unsignedPlugin(String)
    /// A plugin with this id is already registered.
    case duplicatePluginId(String)
    /// The current process already mapped this path; `dlopen` would return the
    /// cached image rather than the rebuilt dylib.
    case restartRequired(String)
    case invalidPluginId(String)
    /// A C entry point returned NULL.
    case nullEntryPoint(String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "Dynamic library not found at: \(path)"
        case .dlopenFailed(let msg):
            return "Failed to load dynamic library: \(msg)"
        case .missingEntrySymbol(let sym):
            return "Missing plugin entry point symbol '\(sym)' or 'purahPluginManifestJSON'."
        case .invalidPluginType:
            return "Exported plugin instance or manifest JSON is invalid."
        case .compilationFailed(let log):
            return "Swift Package compilation failed:\n\(log)"
        case .incompatibleABI(let found, let expected):
            return "Plugin targets ABI \(found) but this version of Purah speaks \(expected)."
        case .unsignedPlugin(let detail):
            return "Plugin is not signed: \(detail)"
        case .duplicatePluginId(let id):
            return "A plugin with id '\(id)' is already loaded."
        case .restartRequired(let path):
            return "Purah already loaded \(path) in this process. Rebuild the plugin, quit Purah, and launch it again to load the new image."
        case .invalidPluginId(let id):
            return "Plugin id '\(id)' is invalid."
        case .nullEntryPoint(let symbol):
            return "Plugin entry point '\(symbol)' returned null."
        }
    }
}

/// Version of the zero-dependency C ABI an external plugin must target.
///
/// Plugins export `purahPluginABIVersion` returning a C string. A missing
/// symbol is treated as legacy ABI 1 so already-built developer plugins keep
/// loading; anything newer than the host is rejected instead of being called
/// through an incompatible function table.
public enum PurahPluginABI {
    public static let current = "1"
    public static let versionSymbol = "purahPluginABIVersion"
    public static let manifestSymbol = "purahPluginManifestJSON"

    public static func isCompatible(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let major = Int(trimmed.split(separator: ".").first ?? "") else { return trimmed == current }
        return major <= Int(current) ?? 1
    }
}

// MARK: - Dynamic Plugin Loader Service
@MainActor
public final class PluginDynamicLoader {
    public static let shared = PluginDynamicLoader()

    /// Fallback store for callers that never registered a per-plugin binding
    /// (settings windows, tests, single-store builds).
    public weak var currentStore: PurahWorkspaceStore?

    /// Store each external plugin was last rendered against. Binding is
    /// per-plugin so a second screen (or a second store) cannot silently
    /// re-route every external plugin's host actions to the newest store —
    /// with a single `currentStore` the last writer won, and an external pod
    /// on screen A could end up expanding a pod on screen B.
    private var pluginStores: [String: WeakStore] = [:]

    private struct WeakStore {
        weak var value: PurahWorkspaceStore?
    }

    private var loadedHandles: [String: UnsafeMutableRawPointer] = [:]
    private var loadedDylibPaths: [String: String] = [:]
    /// `unloadPlugin` deliberately keeps images mapped. Track their canonical
    /// paths so a second `dlopen` cannot silently return that cached image.
    private var residentDylibPaths: Set<String> = []

    /// Persisted `pluginId → dylib path` for plugins loaded through
    /// `Dev: Load Package...`. Without this the plugin existed only for the
    /// current process: the next launch had no implementation for its pod and
    /// `pruneOrphanedPods` deleted the user's layout as if the plugin had been
    /// uninstalled.
    private var installedDylibPaths: [String: String] = [:]
    private var installedPackagePaths: [String: String] = [:]
    private let installedPathsKey = "purah.dynamicPluginPaths"
    private let installedPackagePathsKey = "purah.dynamicPluginPackagePaths"
    private let userDefaults: UserDefaults

    /// Last stepped items each dynamic plugin reported. The layout engine needs
    /// a sub-item count before any context exists, so the render pass caches
    /// what it learned here.
    private var steppedItemCache: [String: [PurahPluginSubItem]] = [:]

    /// Production uses `shared` and standard defaults. Tests inject an
    /// isolated domain so installed-path persistence cannot leak.
    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        installedDylibPaths = userDefaults.dictionary(forKey: installedPathsKey) as? [String: String] ?? [:]
        installedPackagePaths = userDefaults.dictionary(forKey: installedPackagePathsKey) as? [String: String] ?? [:]
    }

    // MARK: - Installation persistence

    /// Records a loaded plugin so it can be re-registered at next launch.
    public func rememberInstalled(path: String, packagePath: String? = nil, for id: String) {
        installedDylibPaths[id] = path
        userDefaults.set(installedDylibPaths, forKey: installedPathsKey)
        if let packagePath {
            installedPackagePaths[id] = packagePath
            userDefaults.set(installedPackagePaths, forKey: installedPackagePathsKey)
        }
    }

    public func installedPackagePath(for id: String) -> String? {
        installedPackagePaths[id]
    }

    public func forgetInstalled(id: String) {
        installedDylibPaths.removeValue(forKey: id)
        userDefaults.set(installedDylibPaths, forKey: installedPathsKey)
        installedPackagePaths.removeValue(forKey: id)
        userDefaults.set(installedPackagePaths, forKey: installedPackagePathsKey)
    }

    public func forgetInstalled(pluginId: String) {
        forgetInstalled(id: pluginId)
    }

    public var installedPluginPaths: [String: String] { installedDylibPaths }

    /// Re-loads every persisted external plugin and re-registers it.
    ///
    /// Runs after `PluginRegistry.bindStore`, so the registry already knows
    /// which plugins are built-ins; the pods these plugins own are then
    /// restored rather than pruned. A path that no longer exists (or a dylib
    /// that no longer loads) is forgotten instead of retried forever — the
    /// orphan prune will clean up its pod, which is the correct outcome for a
    /// plugin the developer deleted.
    public func restoreInstalledPlugins(into store: PurahWorkspaceStore) {
        guard !installedDylibPaths.isEmpty else { return }
        var didRestore = false

        for (pluginId, path) in installedDylibPaths {
            guard FileManager.default.fileExists(atPath: path) else {
                DiagnosticLogger.shared.warn("Plugin", "External plugin path gone, forgetting: \(path)")
                installedDylibPaths.removeValue(forKey: pluginId)
                installedPackagePaths.removeValue(forKey: pluginId)
                continue
            }
            do {
                let plugin = try loadPlugin(from: URL(fileURLWithPath: path))
                PluginRegistry.shared.register(plugin, store: store)
                if !store.marketManager.isInstalled(id: plugin.manifest.id) {
                    store.marketManager.install(id: plugin.manifest.id)
                }
                didRestore = true
                DiagnosticLogger.shared.info("Plugin", "Restored external plugin: \(plugin.manifest.id)")
            } catch {
                // Keep the entry: a compile error or a temporary lock should
                // not silently uninstall the developer's plugin. The pod is
                // pruned this launch and comes back when the build is fixed.
                DiagnosticLogger.shared.warn("Plugin", "External plugin failed to restore: \(pluginId) — \(error.localizedDescription)")
            }
        }

        userDefaults.set(installedDylibPaths, forKey: installedPathsKey)
        userDefaults.set(installedPackagePaths, forKey: installedPackagePathsKey)

        if didRestore {
            // A restored pod may be missing from the saved layout (first launch
            // after loading a dylib that was never laid out).
            for id in installedDylibPaths.keys
            where !store.pods.contains(where: { $0.id == id }) {
                if let manifest = PluginRegistry.shared.manifest(for: id) {
                    store.pods.append(manifest.makeDefaultSlotPod(isEnabled: true))
                }
            }
            store.invalidateLayoutCache()
            store.savePersistentState()
            store.onWindowsRebuildNeeded?()
        }
    }

    public func cacheSteppedItems(_ items: [PurahPluginSubItem], for pluginId: String) {
        steppedItemCache[pluginId] = items
    }

    public func cachedSteppedItems(for pluginId: String) -> [PurahPluginSubItem] {
        steppedItemCache[pluginId] ?? []
    }

    public func registerStore(_ store: PurahWorkspaceStore) {
        self.currentStore = store
    }

    public func registerStore(_ store: PurahWorkspaceStore, for pluginId: String) {
        self.currentStore = store
        self.pluginStores[pluginId] = WeakStore(value: store)
    }

    public func store(for pluginId: String) -> PurahWorkspaceStore? {
        pluginStores[pluginId]?.value ?? currentStore
    }

    public func handleExternalPluginAction(pluginId: String, action: String, payload: String?) {
        guard let store = store(for: pluginId) else { return }
        switch action {
        case "expand":
            store.activateDrawer(podId: pluginId, itemId: (payload?.isEmpty == false) ? payload : nil)
        case "dismiss":
            if !store.isItemPinned(id: pluginId) {
                if store.activeDrawerItemId == pluginId {
                    store.activeDrawerItemId = nil
                }
                if store.activeDrawerPodId == pluginId {
                    store.activeDrawerPodId = nil
                }
                if store.activePodId == pluginId {
                    store.activePodId = nil
                }
                if store.hoveredPodId == pluginId {
                    store.hoveredPodId = nil
                }
                store.onDismissPreviewPanel?()
                store.activePreviewScreenFrame = nil
                store.activeDropdownScreenFrame = nil
                store.invalidateLayoutCache()
            }
        case "togglePin":
            store.togglePin(for: pluginId)
        case "showToast":
            store.onToast?(payload ?? "", "sparkles")
        case "showWarning":
            store.onCapacityWarningToast?(payload ?? "")
        case "openSettings":
            store.openPluginSettings(id: pluginId)
        case "performHaptic":
            let hapticType: PurahHapticType = (payload == "levelChange") ? .levelChange : .alignment
            SensoryFeedbackService.shared.performControlHapticIfEnabled(hapticType)
        case "requestLayoutRecalculation":
            store.recalculateLayout()
        case "setDecomposed":
            // Lets a plugin's own settings page offer the same bar ↔ chips
            // switch the Sculptor dock offers. The host owns persistence.
            let wantsChips = (payload == "true" || payload == "1")
            store.togglePodDecomposedIfNeeded(podId: pluginId, decomposed: wantsChips)
        case "askAI":
            answerAIRequest(pluginId: pluginId, payload: payload)
        default:
            break
        }
    }

    /// One `askAI` bridge call in, one `purahHandleAIResponse` call out.
    ///
    /// The manifest is the only gate: a plugin that did not declare
    /// `"usesAI": true` gets an error reply, not an answer, so third-party
    /// code cannot spend the person's API credits unannounced. The person's
    /// own provider, credentials and on-device preference still decide where
    /// the text goes — a plugin cannot route around them through this seam.
    private func answerAIRequest(pluginId: String, payload: String?) {
        guard let payload,
              let data = payload.data(using: .utf8),
              let request = try? JSONDecoder().decode(PurahABIAIRequest.self, from: data),
              !request.id.isEmpty,
              let plugin = PluginRegistry.shared.plugin(for: pluginId) as? DynamicABIPodPlugin
        else { return }

        guard plugin.manifest.usesAI else {
            plugin.deliverAIResponse(
                requestId: request.id,
                answer: nil,
                error: "\(plugin.manifest.displayName) did not declare AI use in its manifest."
            )
            return
        }

        Task { @MainActor in
            do {
                let answer = try await PurahAIService.ask(
                    request.prompt,
                    system: request.system,
                    privacy: request.privacyMode
                )
                plugin.deliverAIResponse(requestId: request.id, answer: answer, error: nil)
            } catch {
                plugin.deliverAIResponse(
                    requestId: request.id,
                    answer: nil,
                    error: error.localizedDescription
                )
            }
        }
    }

    /// Dynamically loads a compiled .dylib into the running process and resolves its PurahPodPlugin instance
    public func loadPlugin(from dylibURL: URL, symbol: String = "createPlugin") throws -> any PurahPodPlugin {
        let path = dylibURL.path
        guard FileManager.default.fileExists(atPath: path) else {
            throw PluginDynamicLoadError.fileNotFound(path)
        }
        let canonicalPath = URL(fileURLWithPath: path)
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
        guard !residentDylibPaths.contains(canonicalPath) else {
            throw PluginDynamicLoadError.restartRequired(canonicalPath)
        }

        // Trust gate before executing any code from the image: a plugin runs
        // in-process with full user privileges, so a corrupted dylib must
        // never reach dlopen.
        //
        // shortcut: this proves the seal is intact and that the signer is
        // *some* valid authority — not that it is one we trust. A locally
        // built plugin is ad-hoc signed (that is what `Dev: Load Package...`
        // produces), so pinning a Team ID here would reject the feature's only
        // real use. The check is also TOCTOU: the path can be replaced between
        // this call and `dlopen`. Upgrade when plugins are distributed rather
        // than built by their author: pin a Team ID, or copy the dylib into a
        // directory this process owns and load from there.
        try verifySignature(of: dylibURL)

        guard let handle = dlopen(path, RTLD_NOW | RTLD_GLOBAL) else {
            let errorMsg = dlerror().map { String(cString: $0) } ?? "Unknown dlopen error"
            throw PluginDynamicLoadError.dlopenFailed(errorMsg)
        }
        residentDylibPaths.insert(canonicalPath)

        try verifyABIVersion(handle: handle, path: path)

        // Strategy A: Direct PurahPodPlugin protocol conformance via createPlugin
        if let sym = dlsym(handle, symbol) {
            typealias InitFunc = @convention(c) () -> UnsafeMutableRawPointer?
            let createFn = unsafeBitCast(sym, to: InitFunc.self)
            guard let rawInstance = createFn() else {
                throw PluginDynamicLoadError.nullEntryPoint(symbol)
            }

            let unmanaged = Unmanaged<AnyObject>.fromOpaque(rawInstance)
            if let plugin = unmanaged.takeRetainedValue() as? any PurahPodPlugin {
                guard PurahPluginFileStorage.isValidPluginId(plugin.manifest.id) else {
                    throw PluginDynamicLoadError.invalidPluginId(plugin.manifest.id)
                }
                try rejectDuplicate(id: plugin.manifest.id, path: path)
                if let bridgeSym = dlsym(handle, "purahSetHostActionBridge") {
                    typealias SetBridgeFunc = @convention(c) (PurahABIHostActionCallback) -> Void
                    let setBridgeFn = unsafeBitCast(bridgeSym, to: SetBridgeFunc.self)
                    setBridgeFn(purahHostActionBridgeDispatcher)
                }
                loadedHandles[plugin.manifest.id] = handle
                loadedDylibPaths[plugin.manifest.id] = path
                return plugin
            }
        }

        // Strategy B: Zero-dependency ABI C bridge (purahPluginManifestJSON + purahCreateRailView + purahCreateDrawerView)
        if let manifestSym = dlsym(handle, PurahPluginABI.manifestSymbol) {
            typealias ManifestFunc = @convention(c) () -> UnsafePointer<CChar>?
            let manifestFn = unsafeBitCast(manifestSym, to: ManifestFunc.self)
            guard let cString = manifestFn() else {
                throw PluginDynamicLoadError.nullEntryPoint(PurahPluginABI.manifestSymbol)
            }
            let jsonString = String(cString: cString)
            guard let jsonData = jsonString.data(using: .utf8),
                  let manifest = try? JSONDecoder().decode(PurahPluginManifest.self, from: jsonData) else {
                throw PluginDynamicLoadError.invalidPluginType
            }
            guard PurahPluginFileStorage.isValidPluginId(manifest.id) else {
                throw PluginDynamicLoadError.invalidPluginId(manifest.id)
            }
            try rejectDuplicate(id: manifest.id, path: path)

            if let bridgeSym = dlsym(handle, "purahSetHostActionBridge") {
                typealias SetBridgeFunc = @convention(c) (PurahABIHostActionCallback) -> Void
                let setBridgeFn = unsafeBitCast(bridgeSym, to: SetBridgeFunc.self)
                setBridgeFn(purahHostActionBridgeDispatcher)
            }

            typealias ContextViewFunc = @convention(c) (UnsafePointer<CChar>) -> UnsafeMutableRawPointer
            typealias ZeroArgViewFunc = @convention(c) () -> UnsafeMutableRawPointer
            typealias VoidFunc = @convention(c) () -> Void

            let railViewWithContextFn = dlsym(handle, "purahCreateRailViewWithContext").map { unsafeBitCast($0, to: ContextViewFunc.self) }
            let railViewFn = dlsym(handle, "purahCreateRailView").map { unsafeBitCast($0, to: ZeroArgViewFunc.self) }

            let drawerViewWithContextFn = dlsym(handle, "purahCreateDrawerViewWithContext").map { unsafeBitCast($0, to: ContextViewFunc.self) }
            let drawerViewFn = dlsym(handle, "purahCreateDrawerView").map { unsafeBitCast($0, to: ZeroArgViewFunc.self) }

            let settingsViewWithContextFn = dlsym(handle, "purahCreateSettingsViewWithContext").map { unsafeBitCast($0, to: ContextViewFunc.self) }
            let settingsViewFn = dlsym(handle, "purahCreateSettingsView").map { unsafeBitCast($0, to: ZeroArgViewFunc.self) }

            let accessoryWithContextFn = dlsym(handle, "purahCreateHeaderAccessoryViewWithContext").map { unsafeBitCast($0, to: ContextViewFunc.self) }
            let accessoryFn = dlsym(handle, "purahCreateHeaderAccessoryView").map { unsafeBitCast($0, to: ZeroArgViewFunc.self) }

            let trailingWithContextFn = dlsym(handle, "purahCreateHeaderTrailingViewWithContext").map { unsafeBitCast($0, to: ContextViewFunc.self) }
            let trailingFn = dlsym(handle, "purahCreateHeaderTrailingView").map { unsafeBitCast($0, to: ZeroArgViewFunc.self) }

            let tapFn = dlsym(handle, "purahOnRailBarTap").map { unsafeBitCast($0, to: VoidFunc.self) }
            let mountFn = dlsym(handle, "purahOnMount").map { unsafeBitCast($0, to: VoidFunc.self) }
            let unmountFn = dlsym(handle, "purahOnUnmount").map { unsafeBitCast($0, to: VoidFunc.self) }

            // Optional capability symbols. Their absence is meaningful: a plugin
            // that exports no stepped symbols has no stepped mode, and one with
            // no colour symbols keeps the static manifest colour.
            typealias JSONOutFunc = @convention(c) (UnsafePointer<CChar>) -> UnsafePointer<CChar>?
            typealias ContextOptionalViewFunc = @convention(c) (UnsafePointer<CChar>) -> UnsafeMutableRawPointer?
            typealias SteppedViewFunc = @convention(c) (UnsafePointer<CChar>, UnsafePointer<CChar>) -> UnsafeMutableRawPointer?

            let steppedItemsFn = dlsym(handle, "purahSteppedItemsJSON").map { unsafeBitCast($0, to: JSONOutFunc.self) }
            let steppedDrawerViewFn = (dlsym(handle, "purahCreateSteppedDrawerContentWithContext") ?? dlsym(handle, "purahCreateSteppedDrawerViewWithContext")).map { unsafeBitCast($0, to: SteppedViewFunc.self) }
            let steppedRowAccessoryFn = dlsym(handle, "purahCreateSteppedRowAccessoryWithContext").map { unsafeBitCast($0, to: SteppedViewFunc.self) }
            let overviewContentFn = dlsym(handle, "purahCreateOverviewDrawerContentWithContext").map { unsafeBitCast($0, to: ContextOptionalViewFunc.self) }
            let policyFn = dlsym(handle, "purahDecomposedPolicyJSON").map { unsafeBitCast($0, to: JSONOutFunc.self) }
            let settingsSchemaJSONFn = dlsym(handle, "purahSettingsSchemaJSON").map { unsafeBitCast($0, to: JSONOutFunc.self) }
            typealias SettingChangedFunc = @convention(c) (UnsafePointer<CChar>, UnsafePointer<CChar>, UnsafePointer<CChar>) -> Void
            let onSettingChangedFn = dlsym(handle, "purahOnSettingChanged").map { unsafeBitCast($0, to: SettingChangedFunc.self) }

            let headerAccessoryJSONFn = dlsym(handle, "purahHeaderAccessoryJSON").map { unsafeBitCast($0, to: JSONOutFunc.self) }
            let headerTrailingItemsJSONFn = dlsym(handle, "purahHeaderTrailingItemsJSON").map { unsafeBitCast($0, to: JSONOutFunc.self) }
            typealias HeaderActionFunc = @convention(c) (UnsafePointer<CChar>, UnsafePointer<CChar>) -> Void
            let onHeaderActionFn = dlsym(handle, "purahOnHeaderAction").map { unsafeBitCast($0, to: HeaderActionFunc.self) }

            let railBarStateFn = dlsym(handle, "purahRailBarStateJSON").map { unsafeBitCast($0, to: JSONOutFunc.self) }
            let barColorFn = dlsym(handle, "purahDynamicBarColorHex").map { unsafeBitCast($0, to: JSONOutFunc.self) }
            let accentColorFn = dlsym(handle, "purahDynamicAccentColorHex").map { unsafeBitCast($0, to: JSONOutFunc.self) }

            typealias UpdateViewFunc = @convention(c) (UnsafeMutableRawPointer, UnsafePointer<CChar>) -> Void
            typealias TapWithContextFunc = @convention(c) (UnsafePointer<CChar>, UnsafePointer<CChar>) -> Int32
            typealias PollingFunc = @convention(c) (UnsafePointer<CChar>) -> Void

            let updateViewFn = dlsym(handle, "purahUpdateContext").map { unsafeBitCast($0, to: UpdateViewFunc.self) }
            let tapWithContextFn = dlsym(handle, "purahOnRailBarTapWithContext").map { unsafeBitCast($0, to: TapWithContextFunc.self) }
            let pollingFn = dlsym(handle, "purahOnPollingTick").map { unsafeBitCast($0, to: PollingFunc.self) }

            typealias AIResponseFunc = @convention(c) (UnsafePointer<CChar>, UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Void
            let aiResponseFn = dlsym(handle, "purahHandleAIResponse").map { unsafeBitCast($0, to: AIResponseFunc.self) }

            // The policy is static, so resolve it once at load rather than
            // calling into the plugin on every layout pass.
            let declaredPolicy: PurahDecomposedPolicy? = policyFn.flatMap { fn in
                PurahABIContextPayload.forLoadTime(pluginId: manifest.id)
                    .withJSONCString { cStr -> PurahDecomposedPolicy? in
                        guard let out = fn(cStr) else { return nil }
                        return PurahABIDecomposedPolicy.decode(String(cString: out))
                    } ?? nil
            }

            let plugin = DynamicABIPodPlugin(
                manifest: manifest,
                railBarStateFn: railBarStateFn,
                makeRailViewFn: railViewFn,
                makeDrawerViewFn: drawerViewFn,
                makeAccessoryViewFn: accessoryFn,
                makeTrailingViewFn: trailingFn,
                onRailTapFn: tapFn,
                makeRailViewWithContextFn: railViewWithContextFn,
                makeDrawerViewWithContextFn: drawerViewWithContextFn,
                makeSettingsViewFn: settingsViewFn,
                makeSettingsViewWithContextFn: settingsViewWithContextFn,
                makeAccessoryViewWithContextFn: accessoryWithContextFn,
                makeTrailingViewWithContextFn: trailingWithContextFn,
                onMountFn: mountFn,
                onUnmountFn: unmountFn,
                steppedItemsFn: steppedItemsFn,
                makeSteppedDrawerViewFn: steppedDrawerViewFn,
                makeSteppedRowAccessoryFn: steppedRowAccessoryFn,
                makeOverviewDrawerContentFn: overviewContentFn,
                decomposedPolicyFn: policyFn,
                settingsSchemaJSONFn: settingsSchemaJSONFn,
                onSettingChangedFn: onSettingChangedFn,
                headerAccessoryJSONFn: headerAccessoryJSONFn,
                headerTrailingItemsJSONFn: headerTrailingItemsJSONFn,
                onHeaderActionFn: onHeaderActionFn,
                dynamicBarColorFn: barColorFn,
                dynamicAccentColorFn: accentColorFn,
                updateViewFn: updateViewFn,
                onRailTapWithContextFn: tapWithContextFn,
                onPollingTickFn: pollingFn,
                aiResponseFn: aiResponseFn,
                declaredDecomposedPolicy: declaredPolicy
            )

            loadedHandles[plugin.manifest.id] = handle
            loadedDylibPaths[plugin.manifest.id] = path
            return plugin
        }

        throw PluginDynamicLoadError.missingEntrySymbol(symbol)
    }

    /// Unloads a dynamically loaded plugin handle.
    ///
    /// The handle is deliberately *not* `dlclose`d. Swift runtime metadata,
    /// dispatch blocks and KVO/notification observers registered by the plugin
    /// can outlive this call, and unmapping the image would turn a stale
    /// callback into a crash. The plugin's views are torn down by the registry;
    /// the image stays resident until the next launch.
    public func unloadPlugin(id: String) {
        if let handle = loadedHandles.removeValue(forKey: id) {
            _ = handle // Intentionally retained: see doc comment.
        }
        loadedDylibPaths.removeValue(forKey: id)
    }

    // MARK: - Trust gates

    /// Requires the dylib to carry a valid code signature.
    ///
    /// This authenticates *integrity*, not publisher identity — a developer
    /// building locally produces an ad-hoc signature, which is accepted. It
    /// stops a tampered or downloaded unsigned binary from being mapped.
    private func verifySignature(of url: URL) throws {
        var staticCode: SecStaticCode?
        let status = SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode)
        guard status == errSecSuccess, let code = staticCode else {
            throw PluginDynamicLoadError.unsignedPlugin("cannot read code signature (OSStatus \(status))")
        }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures)
        let validity = SecStaticCodeCheckValidity(code, flags, nil)
        guard validity == errSecSuccess else {
            throw PluginDynamicLoadError.unsignedPlugin("signature invalid (OSStatus \(validity))")
        }
    }

    /// Rejects plugins built against an ABI newer than this host.
    private func verifyABIVersion(handle: UnsafeMutableRawPointer, path: String) throws {
        guard let sym = dlsym(handle, PurahPluginABI.versionSymbol) else {
            return // Legacy plugin predating the version symbol.
        }
        typealias VersionFunc = @convention(c) () -> UnsafePointer<CChar>?
        let versionFn = unsafeBitCast(sym, to: VersionFunc.self)
        guard let declared = versionFn().map({ String(cString: $0) }), !declared.isEmpty else {
            return
        }
        guard PurahPluginABI.isCompatible(declared) else {
            throw PluginDynamicLoadError.incompatibleABI(found: declared, expected: PurahPluginABI.current)
        }
    }

    private func rejectDuplicate(id: String, path: String) throws {
        if (loadedHandles[id] != nil || PluginRegistry.shared.catalogPlugin(for: id) != nil),
           loadedDylibPaths[id] != path {
            throw PluginDynamicLoadError.duplicatePluginId(id)
        }
    }

    /// Returns the active dylib path for a loaded dynamic plugin
    public func loadedPath(for id: String) -> String? {
        loadedDylibPaths[id]
    }

    /// Checks if a plugin is dynamically loaded
    public func isDynamicallyLoaded(id: String) -> Bool {
        loadedHandles[id] != nil
    }
}
