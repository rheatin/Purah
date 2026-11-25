// Sources/PurahUI/Plugins/DynamicABIPodPlugin.swift
import SwiftUI
import AppKit
import Foundation
import PurahCore

// MARK: - Native AppKit View Bridge for ABI-Independent Dynamic Plugins

private final class PurahFlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}

/// Hard-clamped host container for external plugin body views.
///
/// On macOS 14+, `NSView.clipsToBounds` defaults to `false`, and when an
/// `NSHostingView` is compressed below its SwiftUI root view's `fittingSize`,
/// it centers the overflowing root view vertically — bleeding upward over the
/// host's drawer header and downward through the card's bottom padding.
///
/// This container enforces two invariants:
/// 1. `clipsToBounds = true` + `layer.masksToBounds = true` at the container
///    boundary so plugin drawing can never escape the body slot.
/// 2. The inner `NSHostingView` is always given `height = max(bounds.height, fittingH)`
///    inside a flipped, zero-chrome scroll viewport (`y = 0` at top), so it
///    never vertically centers an oversized view and remains scrollable when
///    the pod is shorter than the plugin's content.
private final class PurahClampedPluginContainerView: NSView {
    private let scrollView = NSScrollView()
    private let documentContainer = PurahFlippedDocumentView()
    let hostedView: NSView
    private var didInitialScrollToTop = false

    override var isFlipped: Bool { true }

    init(hostedView: NSView) {
        self.hostedView = hostedView
        super.init(frame: .zero)
        wantsLayer = true
        clipsToBounds = true
        layer?.masksToBounds = true

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.wantsLayer = true
        scrollView.clipsToBounds = true
        scrollView.layer?.masksToBounds = true
        scrollView.contentView.wantsLayer = true
        scrollView.contentView.clipsToBounds = true
        scrollView.contentView.layer?.masksToBounds = true

        documentContainer.wantsLayer = true
        documentContainer.clipsToBounds = true
        documentContainer.layer?.masksToBounds = true

        hostedView.wantsLayer = true
        hostedView.clipsToBounds = true
        hostedView.layer?.masksToBounds = true
        hostedView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        hostedView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        documentContainer.addSubview(hostedView)
        scrollView.documentView = documentContainer
        addSubview(scrollView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        let targetWidth = max(bounds.width, 1)
        hostedView.frame.size.width = targetWidth
        hostedView.layoutSubtreeIfNeeded()
        let fittingH = hostedView.fittingSize.height
        let contentH = max(bounds.height, fittingH)
        documentContainer.frame = NSRect(x: 0, y: 0, width: targetWidth, height: contentH)
        hostedView.frame = documentContainer.bounds
        if !didInitialScrollToTop && bounds.height > 0 {
            didInitialScrollToTop = true
            scrollView.contentView.scroll(to: .zero)
        }
    }
}

private struct HostedPluginNSView: NSViewRepresentable {
    let view: NSView
    /// The retained pointer the plugin handed back. `nil` for views the host
    /// created itself, which have nothing to update.
    let pointer: UnsafeMutableRawPointer?
    let contextJSON: String
    let updateFn: (@convention(c) (UnsafeMutableRawPointer, UnsafePointer<CChar>) -> Void)?
    var isIntrinsicSized: Bool = false
    var isSettingsView: Bool = false

    func makeNSView(context: Context) -> NSView {
        if isIntrinsicSized || isSettingsView {
            view.wantsLayer = true
            view.clipsToBounds = true
            view.layer?.masksToBounds = true
            return view
        }
        return PurahClampedPluginContainerView(hostedView: view)
    }

    /// Push the new context into the plugin's own view.
    ///
    /// Without this the factory ran exactly once and the plugin never learned
    /// that the drawer expanded, the pod got pinned, or the width changed —
    /// every later render produced a fresh NSHostingView that SwiftUI threw
    /// away. Plugins that export no update symbol keep the old behaviour.
    func updateNSView(_ nsView: NSView, context: Context) {
        if let container = nsView as? PurahClampedPluginContainerView {
            container.needsLayout = true
        }
        guard let updateFn, let pointer else { return }
        contextJSON.withCString { updateFn(pointer, $0) }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSView, context: Context) -> CGSize? {
        if isSettingsView {
            let width = proposal.width ?? 400
            view.frame.size.width = width
            view.layoutSubtreeIfNeeded()
            let fitting = view.fittingSize
            return CGSize(width: width, height: max(fitting.height, 1))
        }
        if isIntrinsicSized {
            let fitting = nsView.fittingSize
            guard fitting.width > 0 && fitting.height > 0 else { return nil }
            return fitting
        }
        let targetView = (nsView as? PurahClampedPluginContainerView)?.hostedView ?? nsView
        let fitting = targetView.fittingSize
        let width = proposal.width ?? (fitting.width > 0 ? fitting.width : 280)
        // When hosted inside a fixed-height drawer card (`proposal.height` is
        // finite), strictly accept the proposed body height so the plugin can
        // never push or overlap the host's header row. When hosted inside an
        // unconstrained ScrollView (e.g. plugin settings page where
        // `proposal.height == nil`), report the plugin's natural fitting height.
        let height: CGFloat
        if let proposedH = proposal.height, proposedH.isFinite {
            height = max(0, proposedH)
        } else {
            height = fitting.height > 0 ? fitting.height : 200
        }
        return CGSize(width: max(0, width), height: height)
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

@MainActor
public struct DynamicABIHostBridge: Sendable {
    private let _handleAction: @MainActor @Sendable (String, String, String?) -> Void
    private let _registerStore: @MainActor @Sendable (PurahWorkspaceStore, String) -> Void
    private let _cacheSteppedItems: @MainActor @Sendable ([PurahPluginSubItem], String) -> Void
    private let _cachedSteppedItems: @MainActor @Sendable (String) -> [PurahPluginSubItem]

    public init(
        handleAction: @escaping @MainActor @Sendable (String, String, String?) -> Void,
        registerStore: @escaping @MainActor @Sendable (PurahWorkspaceStore, String) -> Void,
        cacheSteppedItems: @escaping @MainActor @Sendable ([PurahPluginSubItem], String) -> Void,
        cachedSteppedItems: @escaping @MainActor @Sendable (String) -> [PurahPluginSubItem]
    ) {
        self._handleAction = handleAction
        self._registerStore = registerStore
        self._cacheSteppedItems = cacheSteppedItems
        self._cachedSteppedItems = cachedSteppedItems
    }

    public func handleAction(_ pluginId: String, _ action: String, _ payload: String?) {
        _handleAction(pluginId, action, payload)
    }

    public func registerStore(_ store: PurahWorkspaceStore, for pluginId: String) {
        _registerStore(store, pluginId)
    }

    public func cacheSteppedItems(_ items: [PurahPluginSubItem], for pluginId: String) {
        _cacheSteppedItems(items, pluginId)
    }

    public func cachedSteppedItems(for pluginId: String) -> [PurahPluginSubItem] {
        _cachedSteppedItems(pluginId)
    }

    public static func live() -> DynamicABIHostBridge {
        DynamicABIHostBridge(
            handleAction: { pluginId, action, payload in
                PluginDynamicLoader.shared.handleExternalPluginAction(pluginId: pluginId, action: action, payload: payload)
            },
            registerStore: { store, pluginId in
                PluginDynamicLoader.shared.registerStore(store, for: pluginId)
            },
            cacheSteppedItems: { items, pluginId in
                PluginDynamicLoader.shared.cacheSteppedItems(items, for: pluginId)
            },
            cachedSteppedItems: { pluginId in
                PluginDynamicLoader.shared.cachedSteppedItems(for: pluginId)
            }
        )
    }
}

public func purahHostActionBridgeDispatcher(
    pluginIdPtr: UnsafePointer<CChar>,
    actionPtr: UnsafePointer<CChar>,
    payloadPtr: UnsafePointer<CChar>?
) {
    let pluginId = String(cString: pluginIdPtr)
    let action = String(cString: actionPtr)
    let payload = payloadPtr.map { String(cString: $0) }
    if Thread.isMainThread {
        MainActor.assumeIsolated {
            DynamicABIHostBridge.live().handleAction(pluginId, action, payload)
        }
    } else {
        Task { @MainActor in
            DynamicABIHostBridge.live().handleAction(pluginId, action, payload)
        }
    }
}

// MARK: - Dynamic ABI Pod Plugin
@MainActor
public final class DynamicABIPodPlugin: PurahPodPlugin {
    public nonisolated let manifest: PurahPluginManifest

    private let railBarStateFn: (@convention(c) (UnsafePointer<CChar>) -> UnsafePointer<CChar>?)?
    private let makeDrawerViewFn: (@convention(c) () -> UnsafeMutableRawPointer)?
    private let makeAccessoryViewFn: (@convention(c) () -> UnsafeMutableRawPointer)?
    private let makeTrailingViewFn: (@convention(c) () -> UnsafeMutableRawPointer)?
    private let onRailTapFn: (@convention(c) () -> Void)?

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
    private let makeSteppedRowAccessoryFn: (@convention(c) (UnsafePointer<CChar>, UnsafePointer<CChar>) -> UnsafeMutableRawPointer?)?
    private let makeOverviewDrawerContentFn: (@convention(c) (UnsafePointer<CChar>) -> UnsafeMutableRawPointer?)?
    private let decomposedPolicyFn: (@convention(c) (UnsafePointer<CChar>) -> UnsafePointer<CChar>?)?
    private let settingsSchemaJSONFn: (@convention(c) (UnsafePointer<CChar>) -> UnsafePointer<CChar>?)?
    private let onSettingChangedFn: (@convention(c) (UnsafePointer<CChar>, UnsafePointer<CChar>, UnsafePointer<CChar>) -> Void)?
    private let headerAccessoryJSONFn: (@convention(c) (UnsafePointer<CChar>) -> UnsafePointer<CChar>?)?
    private let headerTrailingItemsJSONFn: (@convention(c) (UnsafePointer<CChar>) -> UnsafePointer<CChar>?)?
    private let onHeaderActionFn: (@convention(c) (UnsafePointer<CChar>, UnsafePointer<CChar>) -> Void)?
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

    /// `purahHandleAIResponse(requestId, answer, error)` — how an answer to an
    /// `askAI` bridge call gets back into the plugin. Answers are asynchronous,
    /// and the bridge itself is fire-and-forget, so this is the return leg.
    private let aiResponseFn: (@convention(c) (UnsafePointer<CChar>, UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Void)?

    /// Fallback when the plugin declares no stepped policy. Matches the host's
    /// standard composite policy so an ABI plugin without one behaves exactly
    /// like a plugin that never opted into stepped mode.
    private let declaredDecomposedPolicy: PurahDecomposedPolicy?
    private let hostBridge: DynamicABIHostBridge

    public init(
        manifest: PurahPluginManifest,
        railBarStateFn: (@convention(c) (UnsafePointer<CChar>) -> UnsafePointer<CChar>?)? = nil,
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
        makeSteppedRowAccessoryFn: (@convention(c) (UnsafePointer<CChar>, UnsafePointer<CChar>) -> UnsafeMutableRawPointer?)? = nil,
        makeOverviewDrawerContentFn: (@convention(c) (UnsafePointer<CChar>) -> UnsafeMutableRawPointer?)? = nil,
        decomposedPolicyFn: (@convention(c) (UnsafePointer<CChar>) -> UnsafePointer<CChar>?)? = nil,
        settingsSchemaJSONFn: (@convention(c) (UnsafePointer<CChar>) -> UnsafePointer<CChar>?)? = nil,
        onSettingChangedFn: (@convention(c) (UnsafePointer<CChar>, UnsafePointer<CChar>, UnsafePointer<CChar>) -> Void)? = nil,
        headerAccessoryJSONFn: (@convention(c) (UnsafePointer<CChar>) -> UnsafePointer<CChar>?)? = nil,
        headerTrailingItemsJSONFn: (@convention(c) (UnsafePointer<CChar>) -> UnsafePointer<CChar>?)? = nil,
        onHeaderActionFn: (@convention(c) (UnsafePointer<CChar>, UnsafePointer<CChar>) -> Void)? = nil,
        dynamicBarColorFn: (@convention(c) (UnsafePointer<CChar>) -> UnsafePointer<CChar>?)? = nil,
        dynamicAccentColorFn: (@convention(c) (UnsafePointer<CChar>) -> UnsafePointer<CChar>?)? = nil,
        updateViewFn: (@convention(c) (UnsafeMutableRawPointer, UnsafePointer<CChar>) -> Void)? = nil,
        onRailTapWithContextFn: (@convention(c) (UnsafePointer<CChar>, UnsafePointer<CChar>) -> Int32)? = nil,
        onPollingTickFn: (@convention(c) (UnsafePointer<CChar>) -> Void)? = nil,
        aiResponseFn: (@convention(c) (UnsafePointer<CChar>, UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Void)? = nil,
        declaredDecomposedPolicy: PurahDecomposedPolicy? = nil,
        hostBridge: DynamicABIHostBridge = .live()
    ) {
        self.manifest = manifest
        self.railBarStateFn = railBarStateFn
        _ = makeRailViewFn
        _ = makeRailViewWithContextFn
        self.makeDrawerViewFn = makeDrawerViewFn
        self.makeAccessoryViewFn = makeAccessoryViewFn
        self.makeTrailingViewFn = makeTrailingViewFn
        self.onRailTapFn = onRailTapFn
        self.makeDrawerViewWithContextFn = makeDrawerViewWithContextFn
        self.makeSettingsViewFn = makeSettingsViewFn
        self.makeSettingsViewWithContextFn = makeSettingsViewWithContextFn
        self.makeAccessoryViewWithContextFn = makeAccessoryViewWithContextFn
        self.makeTrailingViewWithContextFn = makeTrailingViewWithContextFn
        self.onMountFn = onMountFn
        self.onUnmountFn = onUnmountFn
        self.steppedItemsFn = steppedItemsFn
        self.makeSteppedDrawerViewFn = makeSteppedDrawerViewFn
        self.makeSteppedRowAccessoryFn = makeSteppedRowAccessoryFn
        self.makeOverviewDrawerContentFn = makeOverviewDrawerContentFn
        self.decomposedPolicyFn = decomposedPolicyFn
        self.settingsSchemaJSONFn = settingsSchemaJSONFn
        self.onSettingChangedFn = onSettingChangedFn
        self.headerAccessoryJSONFn = headerAccessoryJSONFn
        self.headerTrailingItemsJSONFn = headerTrailingItemsJSONFn
        self.onHeaderActionFn = onHeaderActionFn
        self.dynamicBarColorFn = dynamicBarColorFn
        self.dynamicAccentColorFn = dynamicAccentColorFn
        self.updateViewFn = updateViewFn
        self.onRailTapWithContextFn = onRailTapWithContextFn
        self.onPollingTickFn = onPollingTickFn
        self.aiResponseFn = aiResponseFn
        self.declaredDecomposedPolicy = declaredDecomposedPolicy
        self.hostBridge = hostBridge
    }

    /// Hands one answer back to the plugin that asked. Called on the main
    /// actor; the C strings only live for the duration of the call, which is
    /// the plugin's job to copy before returning.
    func deliverAIResponse(requestId: String, answer: String?, error: String?) {
        guard let fn = aiResponseFn else { return }
        requestId.withCString { id in
            if let answer {
                answer.withCString { fn(id, $0, nil) }
            } else {
                (error ?? "The AI Assistant returned no answer.").withCString { fn(id, nil, $0) }
            }
        }
    }

    /// External plugins never draw arbitrary views on the 8pt edge rail.
    /// Instead, the host renders the composite rail bar from `purahRailBarStateJSON`
    /// (or defaults to a solid pill in the plugin's dynamic/accent color).
    public func railBarDescriptor(context: PurahPluginContext) -> PurahRailBarDescriptor {
        hostBridge.registerStore(context.store, for: manifest.id)
        let defaultColor = dynamicBarColor(context: context) ?? context.accentColor
        guard let railBarStateFn else {
            return .solid(color: defaultColor, hasContent: true)
        }
        let payload = PurahABIContextPayload.from(context: context)
        guard let json = payload.withJSONCString({ cStr -> String? in
            guard let out = railBarStateFn(cStr) else { return nil }
            return String(cString: out)
        }) ?? nil,
              let state = PurahABIRailBarState.decode(json) else {
            return .solid(color: defaultColor, hasContent: true)
        }

        let baseColor = state.colorHex.flatMap { Color(hex: $0) } ?? defaultColor
        let style = (state.style ?? "solid").lowercased()
        if style == "gauge" || style == "segmented" || state.ratio != nil || state.segments != nil {
            let resolvedSegments: [PurahGaugeSegment]
            if let segs = state.segments, !segs.isEmpty {
                resolvedSegments = segs.map { seg in
                    PurahGaugeSegment(
                        id: seg.id,
                        ratio: min(max(seg.ratio, 0.0), 1.0),
                        color: seg.colorHex.flatMap { Color(hex: $0) } ?? baseColor,
                        isAlerting: seg.isAlerting ?? false
                    )
                }
            } else if let ratio = state.ratio {
                resolvedSegments = [
                    PurahGaugeSegment(
                        id: manifest.id,
                        ratio: min(max(ratio, 0.0), 1.0),
                        color: baseColor,
                        isAlerting: state.isAlerting ?? false
                    )
                ]
            } else {
                resolvedSegments = []
            }
            return .gauge(
                segments: resolvedSegments,
                trackColor: baseColor.opacity(0.25),
                minimumVisibleFill: CGFloat(state.minimumVisibleFill ?? 4.0),
                accessibilityValueLabel: state.accessibilityValueLabel
            )
        }

        return .solid(
            color: baseColor,
            hasContent: state.hasContent ?? true,
            isGradient: state.isGradient ?? false
        )
    }

    public func makeRailBarView(context: PurahPluginContext) -> AnyView {
        hostBridge.registerStore(context.store, for: manifest.id)
        return AnyView(PurahHostRailBarView(descriptor: railBarDescriptor(context: context), context: context))
    }

    public func makeDrawerView(context: PurahPluginContext) -> AnyView {
        hostBridge.registerStore(context.store, for: manifest.id)
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
        hostBridge.registerStore(store, for: manifest.id)
        let payload = PurahABIContextPayload.from(store: store, pluginId: manifest.id)

        var customSettingsView: AnyView?
        if let fnWithContext = makeSettingsViewWithContextFn {
            if let (nsView, pointer) = payload.withJSONCString({ cStr -> (NSView, UnsafeMutableRawPointer) in
                let ptr = fnWithContext(cStr)
                return (Unmanaged<NSView>.fromOpaque(ptr).takeRetainedValue(), ptr)
            }) {
                customSettingsView = hosted(nsView, pointer: pointer, payload: payload, isSettingsView: true)
            }
        } else if let fn = makeSettingsViewFn {
            let ptr = fn()
            let nsView = Unmanaged<NSView>.fromOpaque(ptr).takeRetainedValue()
            customSettingsView = hosted(nsView, pointer: ptr, payload: payload, isSettingsView: true)
        }

        let hasSchema = settingsSchemaJSONFn != nil
        if hasSchema {
            let declarativeView = PurahDeclarativeSettingsView(
                store: store,
                sectionsProvider: { [weak self, weak store] in
                    guard let self, let store else { return [] }
                    return self.settingsSections(store: store)
                },
                onSettingChanged: { [weak self, weak store] key, val in
                    guard let self, let store else { return }
                    self.onSettingChanged(key: key, value: val, store: store)
                }
            )
            if let custom = customSettingsView {
                return AnyView(
                    VStack(alignment: .leading, spacing: 14) {
                        declarativeView
                        custom
                    }
                )
            }
            return AnyView(declarativeView)
        }

        return customSettingsView
    }

    public func settingsSections(store: PurahWorkspaceStore) -> [PurahPluginSettingSection] {
        guard let settingsSchemaJSONFn else { return [] }
        let payload = PurahABIContextPayload.from(store: store, pluginId: manifest.id)
        guard let json = payload.withJSONCString({ cStr -> String? in
            guard let out = settingsSchemaJSONFn(cStr) else { return nil }
            return String(cString: out)
        }) ?? nil else { return [] }
        return PurahPluginSettingSection.decodeList(json)
    }

    public func onSettingChanged(key: String, value: String, store: PurahWorkspaceStore) {
        guard let onSettingChangedFn else { return }
        let payload = PurahABIContextPayload.from(store: store, pluginId: manifest.id)
        payload.withJSONCString { cStr in
            key.withCString { kStr in
                value.withCString { vStr in
                    onSettingChangedFn(cStr, kStr, vStr)
                }
            }
        }
        store.invalidateLayoutCache()
        store.onWindowsRebuildNeeded?()
    }

    public func headerAccessory(context: PurahPluginContext) -> PurahHeaderAccessoryDescriptor? {
        guard let headerAccessoryJSONFn else { return nil }
        hostBridge.registerStore(context.store, for: manifest.id)
        let payload = PurahABIContextPayload.from(context: context)
        guard let json = payload.withJSONCString({ cStr -> String? in
            guard let out = headerAccessoryJSONFn(cStr) else { return nil }
            return String(cString: out)
        }) ?? nil else { return nil }
        return PurahHeaderAccessoryDescriptor.decode(json)
    }

    public func headerTrailingItems(context: PurahPluginContext) -> [PurahHeaderTrailingItem] {
        guard let headerTrailingItemsJSONFn else { return [] }
        hostBridge.registerStore(context.store, for: manifest.id)
        let payload = PurahABIContextPayload.from(context: context)
        guard let json = payload.withJSONCString({ cStr -> String? in
            guard let out = headerTrailingItemsJSONFn(cStr) else { return nil }
            return String(cString: out)
        }) ?? nil else { return [] }
        return PurahHeaderTrailingItem.decodeList(json)
    }

    public func onHeaderAction(actionId: String, context: PurahPluginContext) {
        guard let onHeaderActionFn else { return }
        hostBridge.registerStore(context.store, for: manifest.id)
        let payload = PurahABIContextPayload.from(context: context)
        payload.withJSONCString { cStr in
            actionId.withCString { aStr in
                onHeaderActionFn(cStr, aStr)
            }
        }
        context.store.invalidateLayoutCache()
        context.store.onWindowsRebuildNeeded?()
    }

    public func makeHeaderAccessoryView(context: PurahPluginContext) -> AnyView? {
        if let descriptor = headerAccessory(context: context) {
            return AnyView(PurahHostHeaderAccessoryView(descriptor: descriptor, context: context) { [weak self] actionId in
                self?.onHeaderAction(actionId: actionId, context: context)
            })
        }
        return nil
    }

    public func makeHeaderTrailingView(context: PurahPluginContext) -> AnyView? {
        let items = headerTrailingItems(context: context)
        if !items.isEmpty {
            return AnyView(PurahHostHeaderTrailingView(items: items, context: context) { [weak self] actionId in
                self?.onHeaderAction(actionId: actionId, context: context)
            })
        }
        return nil
    }

    private func hosted(
        _ nsView: NSView,
        pointer: UnsafeMutableRawPointer?,
        payload: PurahABIContextPayload,
        isIntrinsicSized: Bool = false,
        isSettingsView: Bool = false
    ) -> AnyView {
        AnyView(HostedPluginNSView(
            view: nsView,
            pointer: pointer,
            contextJSON: payload.jsonString,
            updateFn: updateViewFn,
            isIntrinsicSized: isIntrinsicSized,
            isSettingsView: isSettingsView
        ))
    }

    /// Rail tap with the clicked chip's identity, so a stepped plugin can tell
    /// which item was hit (and act without the host force-opening the drawer).
    public func onRailBarTap(subItemId: String?, context: PurahPluginContext) {
        hostBridge.registerStore(context.store, for: manifest.id)

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
        hostBridge.registerStore(store, for: manifest.id)
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

    public func steppedDrawerWidth(store: PurahWorkspaceStore) -> CGFloat? {
        guard makeSteppedRowAccessoryFn != nil else { return nil }
        return max(280.0, CGFloat(manifest.defaultDrawerWidth))
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
        hostBridge
            .cachedSteppedItems(for: manifest.id)
            .contains { store.isItemPinned(id: $0.id) }
    }

    public func ownsSubItemId(_ itemId: String, store: PurahWorkspaceStore) -> Bool {
        hostBridge
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
        hostBridge.cacheSteppedItems(items, for: manifest.id)
        return items
    }

    /// The layout engine asks for a sub-item count while the drawer is closed,
    /// when there is no `PurahPluginContext` to hand the plugin. The count
    /// therefore comes from the last render, cached by the loader. A cold start
    /// reports 0 — the same answer a plugin with no sub-items gives — and
    /// self-corrects on the first render, which is also when the container
    /// decides whether to show chips at all.
    public func subItemCount(store: PurahWorkspaceStore) -> Int {
        hostBridge.cachedSteppedItems(for: manifest.id).count
    }

    public func subItemId(at index: Int, store: PurahWorkspaceStore) -> String? {
        let items = hostBridge.cachedSteppedItems(for: manifest.id)
        guard items.indices.contains(index) else { return nil }
        return items[index].id
    }

    /// External plugins never own the stepped card shell (`makeSteppedDrawerView`
    /// is always `nil`). Instead, the host renders the stepped row (26pt icon
    /// block, title, badge, subtitle, optional row accessory, gear/pin) and
    /// only displays the plugin's body content below the row when the chip's
    /// body height is at least 48pt.
    public func steppedDrawerMinimumBodyHeight(subItemId: String) -> CGFloat {
        makeSteppedDrawerViewFn == nil ? .infinity : 48.0
    }

    public func makeSteppedRowAccessory(subItemId: String, context: PurahPluginContext) -> AnyView? {
        guard !PurahPluginSubItem.isMoreItemsID(subItemId),
              let fn = makeSteppedRowAccessoryFn else { return nil }
        let payload = PurahABIContextPayload.from(context: context)
        let built: (NSView, UnsafeMutableRawPointer)? = payload.withJSONCString({ cStr -> (NSView, UnsafeMutableRawPointer)? in
            guard let ptr = subItemId.withCString({ idStr in fn(cStr, idStr) }) else { return nil }
            return (Unmanaged<NSView>.fromOpaque(ptr).takeRetainedValue(), ptr)
        }) ?? nil
        guard let (nsView, pointer) = built else { return nil }
        return hosted(nsView, pointer: pointer, payload: payload, isIntrinsicSized: true)
    }

    public func makeSteppedDrawerContent(subItemId: String, context: PurahPluginContext) -> AnyView? {
        guard !PurahPluginSubItem.isMoreItemsID(subItemId) else { return nil }
        if let fn = makeSteppedDrawerViewFn {
            let payload = PurahABIContextPayload.from(context: context)
            let built: (NSView, UnsafeMutableRawPointer)? = payload.withJSONCString({ cStr -> (NSView, UnsafeMutableRawPointer)? in
                guard let ptr = subItemId.withCString({ idStr in fn(cStr, idStr) }) else { return nil }
                return (Unmanaged<NSView>.fromOpaque(ptr).takeRetainedValue(), ptr)
            }) ?? nil
            if let (nsView, pointer) = built {
                return hosted(nsView, pointer: pointer, payload: payload)
            }
            return nil
        }
        guard ownsSubItemId(subItemId, store: context.store) else { return nil }
        return AnyView(EmptyView())
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

