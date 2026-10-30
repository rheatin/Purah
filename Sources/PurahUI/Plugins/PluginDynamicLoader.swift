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
    /// The retained pointer the plugin handed back. `nil` for views the host
    /// created itself, which have nothing to update.
    let pointer: UnsafeMutableRawPointer?
    let contextJSON: String
    let updateFn: (@convention(c) (UnsafeMutableRawPointer, UnsafePointer<CChar>) -> Void)?

    func makeNSView(context: Context) -> NSView { view }

    /// Push the new context into the plugin's own view.
    ///
    /// Without this the factory ran exactly once and the plugin never learned
    /// that the drawer expanded, the pod got pinned, or the width changed —
    /// every later render produced a fresh NSHostingView that SwiftUI threw
    /// away. Plugins that export no update symbol keep the old behaviour.
    func updateNSView(_ nsView: NSView, context: Context) {
        guard let updateFn, let pointer else { return }
        contextJSON.withCString { updateFn(pointer, $0) }
    }
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

    /// Sub-item ids the stepped container is currently showing. A "+N more"
    /// overview must exclude these or it repeats what is already on the rail.
    public let visibleSubItemIds: [String]
    /// Whether the pod is currently in stepped (chips) mode. Lets a plugin
    /// render a different drawer without guessing from its own state.
    public let isDecomposed: Bool
    /// Theme surface colours, so a plugin drawer can follow the active palette
    /// instead of only reacting to light/dark.
    public let paletteStyle: String
    public let primaryAccentHex: String
    public let borderColorHex: String

    /// Which of the permissions this plugin declared are actually granted.
    /// A dylib plugin has no other way to learn this: it cannot read TCC, and
    /// the host is the only party that may raise the prompt.
    public let grantedPermissions: [String]

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
        storageDirectoryPath: String,
        visibleSubItemIds: [String] = [],
        isDecomposed: Bool = false,
        paletteStyle: String = "native",
        primaryAccentHex: String = "#00D1FF",
        borderColorHex: String = "#888888",
        grantedPermissions: [String] = []
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
        self.visibleSubItemIds = visibleSubItemIds
        self.isDecomposed = isDecomposed
        self.paletteStyle = paletteStyle
        self.primaryAccentHex = primaryAccentHex
        self.borderColorHex = borderColorHex
        self.grantedPermissions = grantedPermissions
    }

    /// Pre-encoded form for `updateNSView`, which has no `withCString` scope.
    public var jsonString: String {
        guard let data = try? JSONEncoder().encode(self),
              let json = String(data: data, encoding: .utf8) else { return "{}" }
        return json
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
            storageDirectoryPath: storagePath,
            visibleSubItemIds: Array(context.visibleSubItemIds),
            isDecomposed: context.store.isPodDecomposed(context.pod.id),
            paletteStyle: context.palette.style.rawValue,
            primaryAccentHex: context.palette.primaryAccent.toHex() ?? "#00D1FF",
            borderColorHex: context.palette.borderColor.toHex() ?? "#888888",
            grantedPermissions: Self.resolvedGrantedPermissions(pluginId: context.pod.id)
        )
    }

    /// The host answers this, never the plugin: a dylib cannot read TCC.
    @MainActor
    private static func resolvedGrantedPermissions(pluginId: String) -> [String] {
        (PluginRegistry.shared.manifest(for: pluginId)?.permissions ?? [])
            .filter { PermissionManager.shared.status(for: $0).isGranted }
            .map(\.rawValue)
    }

    @MainActor
    public static func from(store: PurahWorkspaceStore, pluginId: String) -> PurahABIContextPayload {
        let isDark = NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let pod = store.pods.first(where: { $0.id == pluginId })
        let edgeStr = (pod?.edge ?? .right) == .left ? "left" : "right"
        let hex = store.podColorHex(for: pluginId)
        let storagePath = PurahPluginFileStorage(pluginId: pluginId).rootDirectory.path
        let palette = ThemeManager.shared.palette
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
            storageDirectoryPath: storagePath,
            visibleSubItemIds: [],
            isDecomposed: store.isPodDecomposed(pluginId),
            paletteStyle: palette.style.rawValue,
            primaryAccentHex: palette.primaryAccent.toHex() ?? "#00D1FF",
            borderColorHex: palette.borderColor.toHex() ?? "#888888",
            grantedPermissions: resolvedGrantedPermissions(pluginId: pluginId)
        )
    }

    /// Payload for load-time questions (the decomposed policy) that must be
    /// answered before any pod or store exists. Values are neutral rather than
    /// absent so the plugin's decoder sees the shape it expects.
    @MainActor
    public static func forLoadTime(pluginId: String) -> PurahABIContextPayload {
        let isDark = NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return PurahABIContextPayload(
            pluginId: pluginId,
            edge: "right",
            railWidth: 8,
            slotHeight: 60,
            drawerWidth: 320,
            isExpanded: false,
            isPinned: false,
            isDark: isDark,
            accentColorHex: "#00D1FF",
            storageDirectoryPath: PurahPluginFileStorage(pluginId: pluginId).rootDirectory.path
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

    // Stepped (per-sub-item chips) capability. A plugin that exports no stepped
    // symbols simply has no stepped mode, which is what the host already does
    // for any plugin that reports `[.composite]`.
    private let steppedItemsFn: (@convention(c) (UnsafePointer<CChar>) -> UnsafePointer<CChar>?)?
    private let makeSteppedDrawerViewFn: (@convention(c) (UnsafePointer<CChar>, UnsafePointer<CChar>) -> UnsafeMutableRawPointer?)?
    private let makeOverviewDrawerContentFn: (@convention(c) (UnsafePointer<CChar>) -> UnsafeMutableRawPointer?)?
    private let decomposedPolicyFn: (@convention(c) (UnsafePointer<CChar>) -> UnsafePointer<CChar>?)?
    private let dynamicBarColorFn: (@convention(c) (UnsafePointer<CChar>) -> UnsafePointer<CChar>?)?
    private let dynamicAccentColorFn: (@convention(c) (UnsafePointer<CChar>) -> UnsafePointer<CChar>?)?

    /// `purahUpdateContext(view, contextJSON)` — pushes a new payload into a
    /// view the plugin already created.
    private let updateViewFn: (@convention(c) (UnsafeMutableRawPointer, UnsafePointer<CChar>) -> Void)?
    /// `purahOnRailBarTapWithContext(contextJSON, subItemId) -> Int32`.
    /// Non-zero means the plugin handled the tap and the host should not
    /// haptic + expand on its behalf.
    private let onRailTapWithContextFn: (@convention(c) (UnsafePointer<CChar>, UnsafePointer<CChar>) -> Int32)?
    /// `purahOnPollingTick(contextJSON)` — the host owns the timer.
    private let onPollingTickFn: (@convention(c) (UnsafePointer<CChar>) -> Void)?

    /// Fallback when the plugin declares no stepped policy. Matches the host's
    /// standard composite policy so an ABI plugin without one behaves exactly
    /// like a plugin that never opted into stepped mode.
    private let declaredDecomposedPolicy: PurahDecomposedPolicy?

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
        onUnmountFn: (@convention(c) () -> Void)? = nil,
        steppedItemsFn: (@convention(c) (UnsafePointer<CChar>) -> UnsafePointer<CChar>?)? = nil,
        makeSteppedDrawerViewFn: (@convention(c) (UnsafePointer<CChar>, UnsafePointer<CChar>) -> UnsafeMutableRawPointer?)? = nil,
        makeOverviewDrawerContentFn: (@convention(c) (UnsafePointer<CChar>) -> UnsafeMutableRawPointer?)? = nil,
        decomposedPolicyFn: (@convention(c) (UnsafePointer<CChar>) -> UnsafePointer<CChar>?)? = nil,
        dynamicBarColorFn: (@convention(c) (UnsafePointer<CChar>) -> UnsafePointer<CChar>?)? = nil,
        dynamicAccentColorFn: (@convention(c) (UnsafePointer<CChar>) -> UnsafePointer<CChar>?)? = nil,
        updateViewFn: (@convention(c) (UnsafeMutableRawPointer, UnsafePointer<CChar>) -> Void)? = nil,
        onRailTapWithContextFn: (@convention(c) (UnsafePointer<CChar>, UnsafePointer<CChar>) -> Int32)? = nil,
        onPollingTickFn: (@convention(c) (UnsafePointer<CChar>) -> Void)? = nil,
        declaredDecomposedPolicy: PurahDecomposedPolicy? = nil
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
        self.steppedItemsFn = steppedItemsFn
        self.makeSteppedDrawerViewFn = makeSteppedDrawerViewFn
        self.makeOverviewDrawerContentFn = makeOverviewDrawerContentFn
        self.decomposedPolicyFn = decomposedPolicyFn
        self.dynamicBarColorFn = dynamicBarColorFn
        self.dynamicAccentColorFn = dynamicAccentColorFn
        self.updateViewFn = updateViewFn
        self.onRailTapWithContextFn = onRailTapWithContextFn
        self.onPollingTickFn = onPollingTickFn
        self.declaredDecomposedPolicy = declaredDecomposedPolicy
    }

    public func makeRailBarView(context: PurahPluginContext) -> AnyView {
        PluginDynamicLoader.shared.registerStore(context.store, for: manifest.id)
        let payload = PurahABIContextPayload.from(context: context)
        if let fnWithContext = makeRailViewWithContextFn {
            if let (nsView, pointer) = payload.withJSONCString({ cStr -> (NSView, UnsafeMutableRawPointer) in
                let ptr = fnWithContext(cStr)
                return (Unmanaged<NSView>.fromOpaque(ptr).takeRetainedValue(), ptr)
            }) {
                return hosted(nsView, pointer: pointer, payload: payload)
            }
        }
        if let fn = makeRailViewFn {
            let ptr = fn()
            let nsView = Unmanaged<NSView>.fromOpaque(ptr).takeRetainedValue()
            return hosted(nsView, pointer: ptr, payload: payload)
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
            if let (nsView, pointer) = payload.withJSONCString({ cStr -> (NSView, UnsafeMutableRawPointer) in
                let ptr = fnWithContext(cStr)
                return (Unmanaged<NSView>.fromOpaque(ptr).takeRetainedValue(), ptr)
            }) {
                return hosted(nsView, pointer: pointer, payload: payload)
            }
        }
        if let fn = makeDrawerViewFn {
            let ptr = fn()
            let nsView = Unmanaged<NSView>.fromOpaque(ptr).takeRetainedValue()
            return hosted(nsView, pointer: ptr, payload: payload)
        }
        return AnyView(EmptyView())
    }

    public func makeSettingsView(store: PurahWorkspaceStore) -> AnyView? {
        PluginDynamicLoader.shared.registerStore(store, for: manifest.id)
        let payload = PurahABIContextPayload.from(store: store, pluginId: manifest.id)
        if let fnWithContext = makeSettingsViewWithContextFn {
            if let (nsView, pointer) = payload.withJSONCString({ cStr -> (NSView, UnsafeMutableRawPointer) in
                let ptr = fnWithContext(cStr)
                return (Unmanaged<NSView>.fromOpaque(ptr).takeRetainedValue(), ptr)
            }) {
                return hosted(nsView, pointer: pointer, payload: payload)
            }
        }
        if let fn = makeSettingsViewFn {
            let ptr = fn()
            let nsView = Unmanaged<NSView>.fromOpaque(ptr).takeRetainedValue()
            return hosted(nsView, pointer: ptr, payload: payload)
        }
        return nil
    }

    public func makeHeaderAccessoryView(context: PurahPluginContext) -> AnyView? {
        PluginDynamicLoader.shared.registerStore(context.store, for: manifest.id)
        let payload = PurahABIContextPayload.from(context: context)
        if let fnWithContext = makeAccessoryViewWithContextFn {
            if let (nsView, pointer) = payload.withJSONCString({ cStr -> (NSView, UnsafeMutableRawPointer) in
                let ptr = fnWithContext(cStr)
                return (Unmanaged<NSView>.fromOpaque(ptr).takeRetainedValue(), ptr)
            }) {
                return hosted(nsView, pointer: pointer, payload: payload)
            }
        }
        if let fn = makeAccessoryViewFn {
            let ptr = fn()
            let nsView = Unmanaged<NSView>.fromOpaque(ptr).takeRetainedValue()
            return hosted(nsView, pointer: ptr, payload: payload)
        }
        return nil
    }

    public func makeHeaderTrailingView(context: PurahPluginContext) -> AnyView? {
        PluginDynamicLoader.shared.registerStore(context.store, for: manifest.id)
        let payload = PurahABIContextPayload.from(context: context)
        if let fnWithContext = makeTrailingViewWithContextFn {
            if let (nsView, pointer) = payload.withJSONCString({ cStr -> (NSView, UnsafeMutableRawPointer) in
                let ptr = fnWithContext(cStr)
                return (Unmanaged<NSView>.fromOpaque(ptr).takeRetainedValue(), ptr)
            }) {
                return hosted(nsView, pointer: pointer, payload: payload)
            }
        }
        if let fn = makeTrailingViewFn {
            let ptr = fn()
            let nsView = Unmanaged<NSView>.fromOpaque(ptr).takeRetainedValue()
            return hosted(nsView, pointer: ptr, payload: payload)
        }
        return nil
    }

    private func hosted(
        _ nsView: NSView,
        pointer: UnsafeMutableRawPointer?,
        payload: PurahABIContextPayload
    ) -> AnyView {
        AnyView(HostedPluginNSView(
            view: nsView,
            pointer: pointer,
            contextJSON: payload.jsonString,
            updateFn: updateViewFn
        ))
    }

    /// Rail tap with the clicked chip's identity, so a stepped plugin can tell
    /// which item was hit (and act without the host force-opening the drawer).
    public func onRailBarTap(subItemId: String?, context: PurahPluginContext) {
        PluginDynamicLoader.shared.registerStore(context.store, for: manifest.id)

        if let fn = onRailTapWithContextFn {
            let payload = PurahABIContextPayload.from(context: context)
            let handled = payload.withJSONCString { cStr -> Bool in
                let idString = subItemId ?? ""
                return idString.withCString { idPtr in
                    // Non-zero return = the plugin handled the tap itself and
                    // does not want the host's default haptic + expand.
                    fn(cStr, idPtr) != 0
                }
            } ?? false
            if handled { return }
            context.performHaptic(.levelChange)
            context.requestExpand()
            return
        }

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

    // MARK: - Declared dimensions (manifest-driven)

    /// The manifest declares the composite drawer's ergonomic range. The host
    /// clamps the floor to the >= 120pt rule and guarantees a real expansion
    /// range, so a plugin cannot flatten its own tier ladder.
    public func minimumDrawerHeight(store: PurahWorkspaceStore) -> CGFloat {
        guard !isDecomposed(store: store) else {
            return decomposedPolicy(store: store)
                .calculateMinimumHeight(activeCount: subItemCount(store: store))
        }
        let declared = manifest.minimumDrawerHeight.map { CGFloat($0) }
        return max(declared ?? 120.0, 120.0)
    }

    public func preferredDrawerHeight(store: PurahWorkspaceStore) -> CGFloat {
        let floor = minimumDrawerHeight(store: store)
        guard !isDecomposed(store: store) else {
            return max(floor, floor * 1.5)
        }
        let declared = manifest.preferredDrawerHeight.map { CGFloat($0) }
        // A preferred height equal to the floor removes the hover-expansion
        // range entirely (Adaptive Tier Principle), so keep at least 24pt.
        return max(declared ?? (floor * 1.5), floor + 24.0)
    }

    // MARK: - Decomposition state

    /// Composite-bar ↔ stepped-chips is user state, persisted by the store so
    /// it survives restarts and the host can offer the same toggle it offers
    /// built-ins. When the user has never touched it, the *plugin* decides via
    /// the manifest's `defaultDecomposed` — the base never assumes a plugin
    /// wants chips just because it can render them. Absent that declaration
    /// the fallback is composite.
    public func isDecomposed(store: PurahWorkspaceStore) -> Bool {
        guard steppedItemsFn != nil else { return false }
        if store.isInSharedMajorPod(podId: manifest.id) { return false }
        return store.externalPodDecomposed(manifest.id) ?? manifest.defaultDecomposed ?? false
    }

    public func setDecomposed(_ decomposed: Bool, store: PurahWorkspaceStore) {
        store.setExternalPodDecomposed(manifest.id, decomposed)
    }

    // MARK: - Pinned children

    /// Answered from the loader's cached chip list rather than a new ABI
    /// symbol: the host already knows which sub-item ids belong to this pod.
    /// Without it, pinning a third-party chip would not keep the canvas wide
    /// enough to hold its open drawer.
    public func hasPinnedChild(store: PurahWorkspaceStore) -> Bool {
        PluginDynamicLoader.shared
            .cachedSteppedItems(for: manifest.id)
            .contains { store.isItemPinned(id: $0.id) }
    }

    public func ownsSubItemId(_ itemId: String, store: PurahWorkspaceStore) -> Bool {
        PluginDynamicLoader.shared
            .cachedSteppedItems(for: manifest.id)
            .contains { $0.id == itemId }
    }

    // MARK: - Host-driven polling

    /// The registry owns the timer, so disabling the pod, unmounting it or
    /// freezing the rails stops the ticks. Plugins must not run their own.
    public var preferredPollingInterval: TimeInterval? {
        guard onPollingTickFn != nil, let interval = manifest.pollingInterval, interval > 0 else {
            return nil
        }
        return interval
    }

    public func onPollingTick(store: PurahWorkspaceStore) async {
        guard let fn = onPollingTickFn else { return }
        let payload = PurahABIContextPayload.from(store: store, pluginId: manifest.id)
        payload.withJSONCString { cStr in fn(cStr) }
    }

    // MARK: - Stepped mode

    /// A dynamic plugin has a stepped mode exactly when it can list its
    /// sub-items — the container asks for items first and renders chips from
    /// them, so exporting only the drawer factory would produce nothing.
    public var supportedDrawerModes: Set<PurahDrawerMode> {
        steppedItemsFn == nil ? [.composite] : [.composite, .stepped]
    }

    public var decomposedPolicy: PurahDecomposedPolicy {
        declaredDecomposedPolicy ?? .standardComposite
    }

    public func decomposedPolicy(store: PurahWorkspaceStore) -> PurahDecomposedPolicy {
        decomposedPolicy
    }

    public func steppedItems(context: PurahPluginContext) -> [PurahPluginSubItem] {
        guard let steppedItemsFn else { return [] }
        let payload = PurahABIContextPayload.from(context: context)
        guard let json = payload.withJSONCString({ cStr -> String? in
            guard let out = steppedItemsFn(cStr) else { return nil }
            return String(cString: out)
        }) ?? nil else { return [] }

        let items = PurahABISubItem.decodeList(json)
        PluginDynamicLoader.shared.cacheSteppedItems(items, for: manifest.id)
        return items
    }

    /// The layout engine asks for a sub-item count while the drawer is closed,
    /// when there is no `PurahPluginContext` to hand the plugin. The count
    /// therefore comes from the last render, cached by the loader. A cold start
    /// reports 0 — the same answer a plugin with no sub-items gives — and
    /// self-corrects on the first render, which is also when the container
    /// decides whether to show chips at all.
    public func subItemCount(store: PurahWorkspaceStore) -> Int {
        PluginDynamicLoader.shared.cachedSteppedItems(for: manifest.id).count
    }

    public func subItemId(at index: Int, store: PurahWorkspaceStore) -> String? {
        let items = PluginDynamicLoader.shared.cachedSteppedItems(for: manifest.id)
        guard items.indices.contains(index) else { return nil }
        return items[index].id
    }

    public func makeSteppedDrawerView(subItemId: String, context: PurahPluginContext) -> AnyView? {
        guard let fn = makeSteppedDrawerViewFn else { return nil }
        let payload = PurahABIContextPayload.from(context: context)
        let built: (NSView, UnsafeMutableRawPointer)? = payload.withJSONCString({ cStr -> (NSView, UnsafeMutableRawPointer)? in
            guard let ptr = subItemId.withCString({ idStr in fn(cStr, idStr) }) else { return nil }
            return (Unmanaged<NSView>.fromOpaque(ptr).takeRetainedValue(), ptr)
        }) ?? nil
        guard let (nsView, pointer) = built else { return nil }
        return hosted(nsView, pointer: pointer, payload: payload)
    }

    public func makeOverviewDrawerContent(context: PurahPluginContext) -> AnyView? {
        guard let fn = makeOverviewDrawerContentFn else { return nil }
        let payload = PurahABIContextPayload.from(context: context)
        let built: (NSView, UnsafeMutableRawPointer)? = payload.withJSONCString({ cStr -> (NSView, UnsafeMutableRawPointer)? in
            guard let ptr = fn(cStr) else { return nil }
            return (Unmanaged<NSView>.fromOpaque(ptr).takeRetainedValue(), ptr)
        }) ?? nil
        guard let (nsView, pointer) = built else { return nil }
        return hosted(nsView, pointer: pointer, payload: payload)
    }

    // MARK: - Dynamic telemetry color

    public var usesAdaptiveTelemetryColor: Bool { dynamicBarColorFn != nil }

    public func dynamicBarColor(context: PurahPluginContext) -> Color? {
        guard let dynamicBarColorFn else { return nil }
        let payload = PurahABIContextPayload.from(context: context)
        let hex = payload.withJSONCString { cStr -> String? in
            guard let out = dynamicBarColorFn(cStr) else { return nil }
            let value = String(cString: out)
            return value.isEmpty ? nil : value
        } ?? nil
        return hex.flatMap { Color(hex: $0) }
    }

    public func dynamicAccentColor(store: PurahWorkspaceStore?) -> Color? {
        guard let dynamicAccentColorFn, let store else { return nil }
        let payload = PurahABIContextPayload.from(store: store, pluginId: manifest.id)
        let hex = payload.withJSONCString { cStr -> String? in
            guard let out = dynamicAccentColorFn(cStr) else { return nil }
            let value = String(cString: out)
            return value.isEmpty ? nil : value
        } ?? nil
        return hex.flatMap { Color(hex: $0) }
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

    /// Persisted `pluginId → dylib path` for plugins loaded through
    /// `Dev: Load Package...`. Without this the plugin existed only for the
    /// current process: the next launch had no implementation for its pod and
    /// `pruneOrphanedPods` deleted the user's layout as if the plugin had been
    /// uninstalled.
    private var installedDylibPaths: [String: String] = [:]
    private let installedPathsKey = "purah.dynamicPluginPaths"

    /// Last stepped items each dynamic plugin reported. The layout engine needs
    /// a sub-item count before any context exists, so the render pass caches
    /// what it learned here.
    private var steppedItemCache: [String: [PurahPluginSubItem]] = [:]

    private init() {
        installedDylibPaths = UserDefaults.standard.dictionary(forKey: installedPathsKey) as? [String: String] ?? [:]
    }

    // MARK: - Installation persistence

    /// Records a loaded plugin so it can be re-registered at next launch.
    public func rememberInstalled(path: String, for pluginId: String) {
        installedDylibPaths[pluginId] = path
        UserDefaults.standard.set(installedDylibPaths, forKey: installedPathsKey)
    }

    public func forgetInstalled(pluginId: String) {
        installedDylibPaths.removeValue(forKey: pluginId)
        UserDefaults.standard.set(installedDylibPaths, forKey: installedPathsKey)
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

        UserDefaults.standard.set(installedDylibPaths, forKey: installedPathsKey)

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
        case "setDecomposed":
            // Lets a plugin's own settings page offer the same bar ↔ chips
            // switch the Sculptor dock offers. The host owns persistence.
            let wantsChips = (payload == "true" || payload == "1")
            store.togglePodDecomposedIfNeeded(podId: pluginId, decomposed: wantsChips)
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

            // Optional capability symbols. Their absence is meaningful: a plugin
            // that exports no stepped symbols has no stepped mode, and one with
            // no colour symbols keeps the static manifest colour.
            typealias JSONOutFunc = @convention(c) (UnsafePointer<CChar>) -> UnsafePointer<CChar>?
            typealias ContextOptionalViewFunc = @convention(c) (UnsafePointer<CChar>) -> UnsafeMutableRawPointer?
            typealias SteppedViewFunc = @convention(c) (UnsafePointer<CChar>, UnsafePointer<CChar>) -> UnsafeMutableRawPointer?

            let steppedItemsFn = dlsym(handle, "purahSteppedItemsJSON").map { unsafeBitCast($0, to: JSONOutFunc.self) }
            let steppedDrawerViewFn = dlsym(handle, "purahCreateSteppedDrawerViewWithContext").map { unsafeBitCast($0, to: SteppedViewFunc.self) }
            let overviewContentFn = dlsym(handle, "purahCreateOverviewDrawerContentWithContext").map { unsafeBitCast($0, to: ContextOptionalViewFunc.self) }
            let policyFn = dlsym(handle, "purahDecomposedPolicyJSON").map { unsafeBitCast($0, to: JSONOutFunc.self) }
            let barColorFn = dlsym(handle, "purahDynamicBarColorHex").map { unsafeBitCast($0, to: JSONOutFunc.self) }
            let accentColorFn = dlsym(handle, "purahDynamicAccentColorHex").map { unsafeBitCast($0, to: JSONOutFunc.self) }

            typealias UpdateViewFunc = @convention(c) (UnsafeMutableRawPointer, UnsafePointer<CChar>) -> Void
            typealias TapWithContextFunc = @convention(c) (UnsafePointer<CChar>, UnsafePointer<CChar>) -> Int32
            typealias PollingFunc = @convention(c) (UnsafePointer<CChar>) -> Void

            let updateViewFn = dlsym(handle, "purahUpdateContext").map { unsafeBitCast($0, to: UpdateViewFunc.self) }
            let tapWithContextFn = dlsym(handle, "purahOnRailBarTapWithContext").map { unsafeBitCast($0, to: TapWithContextFunc.self) }
            let pollingFn = dlsym(handle, "purahOnPollingTick").map { unsafeBitCast($0, to: PollingFunc.self) }

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
                makeOverviewDrawerContentFn: overviewContentFn,
                decomposedPolicyFn: policyFn,
                dynamicBarColorFn: barColorFn,
                dynamicAccentColorFn: accentColorFn,
                updateViewFn: updateViewFn,
                onRailTapWithContextFn: tapWithContextFn,
                onPollingTickFn: pollingFn,
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
