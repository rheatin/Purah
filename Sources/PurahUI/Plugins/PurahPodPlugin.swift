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

    func onMount(store: PurahWorkspaceStore)
    func onUnmount(store: PurahWorkspaceStore)

    // 1. Dynamic Bar Color (e.g. telemetry color, alerting tint)
    func dynamicBarColor(context: PurahPluginContext) -> Color?

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
}

public extension PurahPodPlugin {
    nonisolated var id: String { manifest.id }
    var podId: String { manifest.id }
    var isDecomposed: Bool { supportedDrawerModes.contains(.stepped) }

    func minimumDrawerHeight(store: PurahWorkspaceStore) -> CGFloat { 120.0 }
    func hasPinnedChild(store: PurahWorkspaceStore) -> Bool { false }
    func ownsSubItemId(_ itemId: String, store: PurahWorkspaceStore) -> Bool { itemId.hasPrefix("\(manifest.id)-") }
    func activeSubItemFrames(
        item: ResolvedPodLayoutItem,
        store: PurahWorkspaceStore,
        totalHeight: Double,
        windowWidth: Double,
        corridor: Double
    ) -> [CGRect]? { nil }

    func onMount(store: PurahWorkspaceStore) {}
    func onUnmount(store: PurahWorkspaceStore) {}
    func makeSettingsView(store: PurahWorkspaceStore) -> AnyView? { nil }

    func dynamicBarColor(context: PurahPluginContext) -> Color? { nil }
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
