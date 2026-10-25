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

// MARK: - Native AppKit View Bridge for ABI-Independent Dynamic Plugins
private struct HostedPluginNSView: NSViewRepresentable {
    let view: NSView
    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - C-ABI Context Payload
public struct PurahABIContextPayload: Codable, Sendable {
    public let pluginId: String
    public let edge: String            // "left" or "right"
    public let railWidth: Double
    public let slotHeight: Double
    public let drawerWidth: Double
    public let isExpanded: Bool
    public let isPinned: Bool
    public let isDark: Bool
    public let accentColorHex: String
    public let storageDirectoryPath: String

    public init(
        pluginId: String,
        edge: String,
        railWidth: Double,
        slotHeight: Double,
        drawerWidth: Double,
        isExpanded: Bool,
        isPinned: Bool,
        isDark: Bool,
        accentColorHex: String,
        storageDirectoryPath: String
    ) {
        self.pluginId = pluginId
        self.edge = edge
        self.railWidth = railWidth
        self.slotHeight = slotHeight
        self.drawerWidth = drawerWidth
        self.isExpanded = isExpanded
        self.isPinned = isPinned
        self.isDark = isDark
        self.accentColorHex = accentColorHex
        self.storageDirectoryPath = storageDirectoryPath
    }

    public func withJSONCString<R>(_ body: (UnsafePointer<CChar>) -> R) -> R? {
        guard let data = try? JSONEncoder().encode(self),
              let jsonString = String(data: data, encoding: .utf8) else {
            return nil
        }
        return jsonString.withCString(body)
    }

    @MainActor
    public static func from(context: PurahPluginContext) -> PurahABIContextPayload {
        let isDark = NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let hex = context.accentColor.toHex() ?? "#00D1FF"
        let storagePath = PurahPluginFileStorage(pluginId: context.pod.id).rootDirectory.path
        return PurahABIContextPayload(
            pluginId: context.pod.id,
            edge: context.edge == .left ? "left" : "right",
            railWidth: Double(context.railWidth),
            slotHeight: Double(context.slotHeight),
            drawerWidth: Double(context.drawerWidth),
            isExpanded: context.isExpanded,
            isPinned: context.isPinned,
            isDark: isDark,
            accentColorHex: hex,
            storageDirectoryPath: storagePath
        )
    }

    @MainActor
    public static func from(store: PurahWorkspaceStore, pluginId: String) -> PurahABIContextPayload {
        let isDark = NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let pod = store.pods.first(where: { $0.id == pluginId })
        let edgeStr = (pod?.edge ?? .right) == .left ? "left" : "right"
        let hex = store.podColorHex(for: pluginId)
        let storagePath = PurahPluginFileStorage(pluginId: pluginId).rootDirectory.path
        return PurahABIContextPayload(
            pluginId: pluginId,
            edge: edgeStr,
            railWidth: Double(store.railWidth),
            slotHeight: 60.0,
            drawerWidth: Double(pod?.drawerWidth ?? 320.0),
            isExpanded: store.activePodId == pluginId,
            isPinned: store.isItemPinned(id: pluginId),
            isDark: isDark,
            accentColorHex: hex,
            storageDirectoryPath: storagePath
        )
    }
}

// MARK: - C-ABI Host Action Callback
public typealias PurahABIHostActionCallback = @convention(c) @Sendable (UnsafePointer<CChar>, UnsafePointer<CChar>, UnsafePointer<CChar>?) -> Void

private func purahHostActionBridgeDispatcher(
    pluginIdPtr: UnsafePointer<CChar>,
    actionPtr: UnsafePointer<CChar>,
    payloadPtr: UnsafePointer<CChar>?
) {
    let pluginId = String(cString: pluginIdPtr)
    let action = String(cString: actionPtr)
    let payload = payloadPtr.map { String(cString: $0) }
    if Thread.isMainThread {
        MainActor.assumeIsolated {
            PluginDynamicLoader.shared.handleExternalPluginAction(
                pluginId: pluginId,
                action: action,
                payload: payload
            )
        }
    } else {
        Task { @MainActor in
            PluginDynamicLoader.shared.handleExternalPluginAction(
                pluginId: pluginId,
                action: action,
                payload: payload
            )
        }
    }
}

// MARK: - Dynamic ABI Pod Plugin
@MainActor
public final class DynamicABIPodPlugin: PurahPodPlugin {
    public nonisolated let manifest: PurahPluginManifest

    private let makeRailViewFn: (@convention(c) () -> UnsafeMutableRawPointer)?
    private let makeDrawerViewFn: (@convention(c) () -> UnsafeMutableRawPointer)?
    private let makeAccessoryViewFn: (@convention(c) () -> UnsafeMutableRawPointer)?
    private let makeTrailingViewFn: (@convention(c) () -> UnsafeMutableRawPointer)?
    private let onRailTapFn: (@convention(c) () -> Void)?

    private let makeRailViewWithContextFn: (@convention(c) (UnsafePointer<CChar>) -> UnsafeMutableRawPointer)?
    private let makeDrawerViewWithContextFn: (@convention(c) (UnsafePointer<CChar>) -> UnsafeMutableRawPointer)?
    private let makeSettingsViewFn: (@convention(c) () -> UnsafeMutableRawPointer)?
    private let makeSettingsViewWithContextFn: (@convention(c) (UnsafePointer<CChar>) -> UnsafeMutableRawPointer)?
    private let makeAccessoryViewWithContextFn: (@convention(c) (UnsafePointer<CChar>) -> UnsafeMutableRawPointer)?
    private let makeTrailingViewWithContextFn: (@convention(c) (UnsafePointer<CChar>) -> UnsafeMutableRawPointer)?
    private let onMountFn: (@convention(c) () -> Void)?
    private let onUnmountFn: (@convention(c) () -> Void)?

    public init(
        manifest: PurahPluginManifest,
        makeRailViewFn: (@convention(c) () -> UnsafeMutableRawPointer)? = nil,
        makeDrawerViewFn: (@convention(c) () -> UnsafeMutableRawPointer)? = nil,
        makeAccessoryViewFn: (@convention(c) () -> UnsafeMutableRawPointer)? = nil,
        makeTrailingViewFn: (@convention(c) () -> UnsafeMutableRawPointer)? = nil,
        onRailTapFn: (@convention(c) () -> Void)? = nil,
        makeRailViewWithContextFn: (@convention(c) (UnsafePointer<CChar>) -> UnsafeMutableRawPointer)? = nil,
        makeDrawerViewWithContextFn: (@convention(c) (UnsafePointer<CChar>) -> UnsafeMutableRawPointer)? = nil,
        makeSettingsViewFn: (@convention(c) () -> UnsafeMutableRawPointer)? = nil,
        makeSettingsViewWithContextFn: (@convention(c) (UnsafePointer<CChar>) -> UnsafeMutableRawPointer)? = nil,
        makeAccessoryViewWithContextFn: (@convention(c) (UnsafePointer<CChar>) -> UnsafeMutableRawPointer)? = nil,
        makeTrailingViewWithContextFn: (@convention(c) (UnsafePointer<CChar>) -> UnsafeMutableRawPointer)? = nil,
        onMountFn: (@convention(c) () -> Void)? = nil,
        onUnmountFn: (@convention(c) () -> Void)? = nil
    ) {
        self.manifest = manifest
        self.makeRailViewFn = makeRailViewFn
        self.makeDrawerViewFn = makeDrawerViewFn
        self.makeAccessoryViewFn = makeAccessoryViewFn
        self.makeTrailingViewFn = makeTrailingViewFn
        self.onRailTapFn = onRailTapFn
        self.makeRailViewWithContextFn = makeRailViewWithContextFn
        self.makeDrawerViewWithContextFn = makeDrawerViewWithContextFn
        self.makeSettingsViewFn = makeSettingsViewFn
        self.makeSettingsViewWithContextFn = makeSettingsViewWithContextFn
        self.makeAccessoryViewWithContextFn = makeAccessoryViewWithContextFn
        self.makeTrailingViewWithContextFn = makeTrailingViewWithContextFn
        self.onMountFn = onMountFn
        self.onUnmountFn = onUnmountFn
    }

    public func makeRailBarView(context: PurahPluginContext) -> AnyView {
        PluginDynamicLoader.shared.registerStore(context.store, for: manifest.id)
        let payload = PurahABIContextPayload.from(context: context)
        if let fnWithContext = makeRailViewWithContextFn {
            if let nsView = payload.withJSONCString({ cStr -> NSView in
                let ptr = fnWithContext(cStr)
                return Unmanaged<NSView>.fromOpaque(ptr).takeRetainedValue()
            }) {
                return AnyView(HostedPluginNSView(view: nsView))
            }
        }
        if let fn = makeRailViewFn {
            let ptr = fn()
            let nsView = Unmanaged<NSView>.fromOpaque(ptr).takeRetainedValue()
            return AnyView(HostedPluginNSView(view: nsView))
        }
        return AnyView(
            Capsule()
                .fill(context.accentColor.opacity(0.85))
                .frame(width: context.railWidth, height: context.slotHeight)
        )
    }

    public func makeDrawerView(context: PurahPluginContext) -> AnyView {
        PluginDynamicLoader.shared.registerStore(context.store, for: manifest.id)
        let payload = PurahABIContextPayload.from(context: context)
        if let fnWithContext = makeDrawerViewWithContextFn {
            if let nsView = payload.withJSONCString({ cStr -> NSView in
                let ptr = fnWithContext(cStr)
                return Unmanaged<NSView>.fromOpaque(ptr).takeRetainedValue()
            }) {
                return AnyView(HostedPluginNSView(view: nsView))
            }
        }
        if let fn = makeDrawerViewFn {
            let ptr = fn()
            let nsView = Unmanaged<NSView>.fromOpaque(ptr).takeRetainedValue()
            return AnyView(HostedPluginNSView(view: nsView))
        }
        return AnyView(EmptyView())
    }

    public func makeSettingsView(store: PurahWorkspaceStore) -> AnyView? {
        PluginDynamicLoader.shared.registerStore(store, for: manifest.id)
        let payload = PurahABIContextPayload.from(store: store, pluginId: manifest.id)
        if let fnWithContext = makeSettingsViewWithContextFn {
            if let nsView = payload.withJSONCString({ cStr -> NSView in
                let ptr = fnWithContext(cStr)
                return Unmanaged<NSView>.fromOpaque(ptr).takeRetainedValue()
            }) {
                return AnyView(HostedPluginNSView(view: nsView))
            }
        }
        if let fn = makeSettingsViewFn {
            let ptr = fn()
            let nsView = Unmanaged<NSView>.fromOpaque(ptr).takeRetainedValue()
            return AnyView(HostedPluginNSView(view: nsView))
        }
        return nil
    }

    public func makeHeaderAccessoryView(context: PurahPluginContext) -> AnyView? {
        PluginDynamicLoader.shared.registerStore(context.store, for: manifest.id)
        let payload = PurahABIContextPayload.from(context: context)
        if let fnWithContext = makeAccessoryViewWithContextFn {
            if let nsView = payload.withJSONCString({ cStr -> NSView in
                let ptr = fnWithContext(cStr)
                return Unmanaged<NSView>.fromOpaque(ptr).takeRetainedValue()
            }) {
                return AnyView(HostedPluginNSView(view: nsView))
            }
        }
        if let fn = makeAccessoryViewFn {
            let ptr = fn()
            let nsView = Unmanaged<NSView>.fromOpaque(ptr).takeRetainedValue()
            return AnyView(HostedPluginNSView(view: nsView))
        }
        return nil
    }

    public func makeHeaderTrailingView(context: PurahPluginContext) -> AnyView? {
        PluginDynamicLoader.shared.registerStore(context.store, for: manifest.id)
        let payload = PurahABIContextPayload.from(context: context)
        if let fnWithContext = makeTrailingViewWithContextFn {
            if let nsView = payload.withJSONCString({ cStr -> NSView in
                let ptr = fnWithContext(cStr)
                return Unmanaged<NSView>.fromOpaque(ptr).takeRetainedValue()
            }) {
                return AnyView(HostedPluginNSView(view: nsView))
            }
        }
        if let fn = makeTrailingViewFn {
            let ptr = fn()
            let nsView = Unmanaged<NSView>.fromOpaque(ptr).takeRetainedValue()
            return AnyView(HostedPluginNSView(view: nsView))
        }
        return nil
    }

    public func onRailBarTap(subItemId: String?, context: PurahPluginContext) {
        PluginDynamicLoader.shared.registerStore(context.store, for: manifest.id)
        if let fn = onRailTapFn {
            fn()
        }
        context.performHaptic(.levelChange)
        context.requestExpand()
    }

    public func onMount(store: PurahWorkspaceStore) {
        PluginDynamicLoader.shared.registerStore(store, for: manifest.id)
        onMountFn?()
    }

    public func onUnmount(store: PurahWorkspaceStore) {
        onUnmountFn?()
    }

    public func adaptiveDrawerWidth(store: PurahWorkspaceStore) -> CGFloat? {
        CGFloat(manifest.defaultDrawerWidth)
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

    private init() {}

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
            store.activePodId = pluginId
            store.activeDrawerItemId = pluginId
            store.activeDrawerPodId = pluginId
            store.invalidateLayoutCache()
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
        default:
            break
        }
    }

    /// Dynamically loads a compiled .dylib into the running process and resolves its PurahPodPlugin instance
    public func loadPlugin(from dylibURL: URL, symbol: String = "createPlugin") throws -> any PurahPodPlugin {
        let path = dylibURL.path
        guard FileManager.default.fileExists(atPath: path) else {
            throw PluginDynamicLoadError.fileNotFound(path)
        }

        // Trust gate before executing any code from the image: a plugin runs
        // in-process with full user privileges, so an unsigned or tampered
        // dylib must never reach dlopen.
        try verifySignature(of: dylibURL)

        guard let handle = dlopen(path, RTLD_NOW | RTLD_GLOBAL) else {
            let errorMsg = dlerror().map { String(cString: $0) } ?? "Unknown dlopen error"
            throw PluginDynamicLoadError.dlopenFailed(errorMsg)
        }

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
                try rejectDuplicate(id: plugin.manifest.id)
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
            try rejectDuplicate(id: manifest.id)

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

            let plugin = DynamicABIPodPlugin(
                manifest: manifest,
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
                onUnmountFn: unmountFn
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

    private func rejectDuplicate(id: String) throws {
        guard loadedHandles[id] == nil else {
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
