// Sources/PurahUI/Plugins/PurahPodPlugin.swift
import SwiftUI
import UniformTypeIdentifiers
import PurahCore

@MainActor
public protocol PurahPodPlugin: PurahPodCapabilityProvider, Identifiable, Sendable {
    nonisolated var manifest: PurahPluginManifest { get }

    @ViewBuilder func makeRailBarView(context: PurahPluginContext) -> AnyView
    @ViewBuilder func makeDrawerView(context: PurahPluginContext) -> AnyView
    @ViewBuilder func makeSettingsView(store: PurahWorkspaceStore) -> AnyView?
    @ViewBuilder func makeSteppedDrawerView(subItemId: String, context: PurahPluginContext) -> AnyView?
    // Requirement (not just an extension default) so existential calls
    // dynamically dispatch to the plugin's override.
    @ViewBuilder func makeOverviewDrawerContent(context: PurahPluginContext) -> AnyView?

    func onMount(store: PurahWorkspaceStore)
    func onUnmount(store: PurahWorkspaceStore)

    // 1. Dynamic Bar Color (e.g. telemetry color, alerting tint)
    func dynamicBarColor(context: PurahPluginContext) -> Color?

    // Dynamic Accent Color (e.g. telemetry load color)
    func dynamicAccentColor(store: PurahWorkspaceStore?) -> Color?

    // 2. Supported Drawer Modes (Composite vs Stepped)
    var supportedDrawerModes: Set<PurahDrawerMode> { get }

    // 3. Stepped sub-items for decomposed rail chips
    func steppedItems(context: PurahPluginContext) -> [PurahPluginSubItem]

    // 4. One-Tap Rail Bar Fire
    func onRailBarTap(subItemId: String?, context: PurahPluginContext)

    // 5. Native Drag & Drop Ingestion
    var supportedDropTypes: [UTType] { get }
    func onDrop(providers: [NSItemProvider], context: PurahPluginContext) -> Bool

    // 6. Central Managed Polling Hook
    var preferredPollingInterval: TimeInterval? { get }
    func onPollingTick(store: PurahWorkspaceStore) async

    // 7. Native Context Menu Actions
    func contextMenuActions(subItemId: String?, context: PurahPluginContext) -> [PurahMenuAction]

    // 8. Custom Header Slots (Accessories next to title & Trailing tools before settings/pin)
    @ViewBuilder func makeHeaderAccessoryView(context: PurahPluginContext) -> AnyView?
    @ViewBuilder func makeHeaderTrailingView(context: PurahPluginContext) -> AnyView?

    // 9. Adaptive Telemetry Color
    var usesAdaptiveTelemetryColor: Bool { get }

    // 10. Alert Management
    func acknowledgeAllAlerts(context: PurahPluginContext)
}

public extension PurahPodPlugin {
    nonisolated var id: String { manifest.id }
    var podId: String { manifest.id }

    /// Whether the pod starts in stepped (chips) mode. A plugin that wants
    /// that must say so explicitly — declaring `supportedDrawerModes` only
    /// states that the mode exists, not that it is the default. The base
    /// fallback is composite, so a plugin never lands in a presentation it
    /// did not ask for.
    var isDecomposed: Bool { false }
    var decomposedPolicy: PurahDecomposedPolicy {
        supportedDrawerModes.contains(.stepped) ? .calendarDefault : .standardComposite
    }

    func isDecomposed(store: PurahWorkspaceStore) -> Bool { isDecomposed }
    func decomposedPolicy(store: PurahWorkspaceStore) -> PurahDecomposedPolicy { decomposedPolicy }
    func minimumDrawerHeight(store: PurahWorkspaceStore) -> CGFloat {
        if isDecomposed(store: store) {
            return decomposedPolicy(store: store).calculateMinimumHeight(activeCount: subItemCount(store: store))
        }
        return 120.0
    }
    func hasPinnedChild(store: PurahWorkspaceStore) -> Bool { false }
    func ownsSubItemId(_ itemId: String, store: PurahWorkspaceStore) -> Bool { itemId.hasPrefix("\(manifest.id)-") }

    func onMount(store: PurahWorkspaceStore) {}
    func onUnmount(store: PurahWorkspaceStore) {}
    func makeSettingsView(store: PurahWorkspaceStore) -> AnyView? { nil }
    func makeSteppedDrawerView(subItemId: String, context: PurahPluginContext) -> AnyView? { nil }
    func makeHeaderAccessoryView(context: PurahPluginContext) -> AnyView? { nil }
    func makeHeaderTrailingView(context: PurahPluginContext) -> AnyView? { nil }

    /// Content-only view for the pod's "+N more" overview drawer. The stepped
    /// container supplies the shared shell (rail bar, drawer-grade solid card,
    /// edge-flush shape, slide-in transition) so every overview looks and
    /// animates identically. Return nil if the pod has no overview drawer.
    func makeOverviewDrawerContent(context: PurahPluginContext) -> AnyView? { nil }


    var usesAdaptiveTelemetryColor: Bool { false }
    func acknowledgeAllAlerts(context: PurahPluginContext) {}

    func dynamicBarColor(context: PurahPluginContext) -> Color? { nil }
    func dynamicAccentColor(store: PurahWorkspaceStore?) -> Color? { nil }
    var supportedDrawerModes: Set<PurahDrawerMode> { [.composite] }
    func steppedItems(context: PurahPluginContext) -> [PurahPluginSubItem] { [] }
    func onRailBarTap(subItemId: String?, context: PurahPluginContext) {
        context.requestExpand()
    }

    var supportedDropTypes: [UTType] { [] }
    func onDrop(providers: [NSItemProvider], context: PurahPluginContext) -> Bool { false }

    var preferredPollingInterval: TimeInterval? { nil }
    func onPollingTick(store: PurahWorkspaceStore) async {}

    func contextMenuActions(subItemId: String?, context: PurahPluginContext) -> [PurahMenuAction] {
        let isPinned = context.isPinned
        return [
            PurahMenuAction(
                title: isPinned ? "Unpin Drawer" : "Pin Drawer",
                systemImage: isPinned ? "pin.slash.fill" : "pin.fill",
                action: { context.togglePin() }
            )
        ]
    }
}
