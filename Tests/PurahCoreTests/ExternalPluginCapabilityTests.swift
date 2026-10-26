// Tests/PurahCoreTests/ExternalPluginCapabilityTests.swift
import Testing
import Foundation
import AppKit
@testable import PurahCore
@testable import PurahUI

/// Covers the capability surface external (C-ABI) plugins reach without their
/// own symbols: manifest-declared dimensions, host-owned decomposition state,
/// pinned-child detection from the chip cache, and hover-only alert acks.
@Suite("External Plugin Capabilities")
@MainActor
struct ExternalPluginCapabilityTests {

    private func isolatedStore() -> PurahWorkspaceStore {
        PurahWorkspaceStore(
            userDefaults: UserDefaults(suiteName: "test_extcap_\(UUID().uuidString)")!
        )
    }

    private func manifest(
        id: String = "com.example.ext",
        minimumDrawerHeight: Double? = nil,
        preferredDrawerHeight: Double? = nil,
        pollingInterval: Double? = nil
    ) -> PurahPluginManifest {
        PurahPluginManifest(
            id: id,
            displayName: "External",
            systemIcon: "square",
            description: "external",
            defaultEdge: .right,
            preferredZone: .glance,
            defaultColorHex: "#888888",
            minimumDrawerHeight: minimumDrawerHeight,
            preferredDrawerHeight: preferredDrawerHeight,
            pollingInterval: pollingInterval
        )
    }

    // MARK: - Manifest-declared dimensions

    @Test("Manifest height bounds reach the plugin, with the ergonomic floor enforced")
    func testManifestHeights() {
        let plugin = DynamicABIPodPlugin(manifest: manifest(
            minimumDrawerHeight: 150,
            preferredDrawerHeight: 320
        ))
        let store = isolatedStore()

        #expect(plugin.minimumDrawerHeight(store: store) == 150)
        #expect(plugin.preferredDrawerHeight(store: store) == 320)
    }

    /// A plugin cannot opt out of the >= 120pt rule by declaring less.
    @Test("A declared minimum below the ergonomic floor is clamped up")
    func testMinimumHeightFloor() {
        let plugin = DynamicABIPodPlugin(manifest: manifest(minimumDrawerHeight: 80))
        let store = isolatedStore()

        #expect(plugin.minimumDrawerHeight(store: store) == 120)
    }

    /// Adaptive Tier Principle: min == preferred removes the expansion range.
    @Test("A preferred height equal to the minimum keeps a real expansion range")
    func testPreferredHeightKeepsRange() {
        let plugin = DynamicABIPodPlugin(manifest: manifest(
            minimumDrawerHeight: 120,
            preferredDrawerHeight: 120
        ))
        let store = isolatedStore()

        let minH = plugin.minimumDrawerHeight(store: store)
        let prefH = plugin.preferredDrawerHeight(store: store)
        #expect(prefH > minH)
    }

    @Test("No declared heights falls back to the host defaults")
    func testUndeclaredHeights() {
        let plugin = DynamicABIPodPlugin(manifest: manifest())
        let store = isolatedStore()

        #expect(plugin.minimumDrawerHeight(store: store) == 120)
        #expect(plugin.preferredDrawerHeight(store: store) >= 144)
    }

    // MARK: - Decomposition state

    /// Before the user touches the toggle, a plugin that exports stepped
    /// symbols starts decomposed — the Default Decomposed Principle.
    @Test("Decomposition defaults to the plugin's own stepped support")
    func testDecompositionDefault() {
        let composite = DynamicABIPodPlugin(manifest: manifest(id: "composite"))
        let stepped = DynamicABIPodPlugin(
            manifest: manifest(id: "stepped"),
            steppedItemsFn: { _ in nil }
        )
        let store = isolatedStore()

        #expect(composite.isDecomposed(store: store) == false)
        #expect(store.externalPodDecomposed("stepped") == nil)
        #expect(stepped.isDecomposed(store: store) == true)
    }

    @Test("The user's bar ↔ chips choice persists and overrides the default")
    func testDecompositionPersists() {
        let plugin = DynamicABIPodPlugin(
            manifest: manifest(id: "com.example.persist"),
            steppedItemsFn: { _ in nil }
        )
        let defaults = UserDefaults(suiteName: "test_extcap_persist_\(UUID().uuidString)")!
        let store = PurahWorkspaceStore(userDefaults: defaults)

        plugin.setDecomposed(false, store: store)
        #expect(plugin.isDecomposed(store: store) == false)

        // A second store over the same defaults — i.e. the next launch.
        let relaunched = PurahWorkspaceStore(userDefaults: defaults)
        #expect(plugin.isDecomposed(store: relaunched) == false)

        plugin.setDecomposed(true, store: relaunched)
        #expect(plugin.isDecomposed(store: PurahWorkspaceStore(userDefaults: defaults)))
    }

    @Test("A stacked pod never decomposes")
    func testStackedPodStaysComposite() {
        let plugin = DynamicABIPodPlugin(
            manifest: manifest(id: "com.example.stacked"),
            steppedItemsFn: { _ in nil }
        )
        let store = isolatedStore()
        store.pods.append(plugin.manifest.makeDefaultSlotPod())
        store.mergePodWithNext(id: plugin.manifest.id)

        #expect(plugin.isDecomposed(store: store) == false)
    }

    // MARK: - Pinned children

    /// Pinning a chip must keep the canvas wide enough to hold its drawer;
    /// `hasPinnedItem(on:)` drives the window width.
    @Test("Pinning a cached chip marks the pod as having a pinned child")
    func testPinnedChildFromCache() {
        let plugin = DynamicABIPodPlugin(
            manifest: manifest(id: "com.example.pinned"),
            steppedItemsFn: { _ in nil }
        )
        let store = isolatedStore()
        let items = [
            PurahPluginSubItem(id: "com.example.pinned-a", title: "A", systemIcon: "circle"),
            PurahPluginSubItem(id: "com.example.pinned-b", title: "B", systemIcon: "circle")
        ]
        PluginDynamicLoader.shared.cacheSteppedItems(items, for: plugin.manifest.id)
        defer { PluginDynamicLoader.shared.cacheSteppedItems([], for: plugin.manifest.id) }

        #expect(plugin.hasPinnedChild(store: store) == false)
        #expect(plugin.ownsSubItemId("com.example.pinned-b", store: store))

        store.togglePinItem(id: "com.example.pinned-b")
        #expect(plugin.hasPinnedChild(store: store) == true)
    }

    // MARK: - Host-driven polling

    @Test("Polling is only offered when both the symbol and the manifest interval exist")
    func testPollingRequiresSymbolAndInterval() {
        let noSymbol = DynamicABIPodPlugin(manifest: manifest(pollingInterval: 5))
        let noInterval = DynamicABIPodPlugin(
            manifest: manifest(pollingInterval: nil),
            onPollingTickFn: { _ in }
        )
        let both = DynamicABIPodPlugin(
            manifest: manifest(pollingInterval: 5),
            onPollingTickFn: { _ in }
        )

        #expect(noSymbol.preferredPollingInterval == nil)
        #expect(noInterval.preferredPollingInterval == nil)
        #expect(both.preferredPollingInterval == 5)
    }

    @Test("A zero or negative interval never schedules a timer")
    func testNonPositivePollingInterval() {
        let plugin = DynamicABIPodPlugin(
            manifest: manifest(pollingInterval: 0),
            onPollingTickFn: { _ in }
        )
        #expect(plugin.preferredPollingInterval == nil)
    }

    // MARK: - Context payload

    @Test("The context payload carries the fields a stepped plugin needs")
    func testPayloadCarriesVisibleSubItemsAndPalette() throws {
        let payload = PurahABIContextPayload(
            pluginId: "com.example.ext",
            edge: "right",
            railWidth: 8,
            slotHeight: 140,
            drawerWidth: 290,
            isExpanded: true,
            isPinned: false,
            isDark: true,
            accentColorHex: "#FF6B6B",
            storageDirectoryPath: "/tmp/ext",
            visibleSubItemIds: ["com.example.ext-a"],
            isDecomposed: true,
            paletteStyle: "sheikah",
            primaryAccentHex: "#00D1FF",
            borderColorHex: "#333333"
        )

        let data = try JSONEncoder().encode(payload)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["visibleSubItemIds"] as? [String] == ["com.example.ext-a"])
        #expect(object["isDecomposed"] as? Bool == true)
        #expect(object["paletteStyle"] as? String == "sheikah")
        #expect(object["primaryAccentHex"] as? String == "#00D1FF")
        #expect(object["borderColorHex"] as? String == "#333333")
    }

    // MARK: - Hover-only alert acknowledgment

    /// Hover is now the only acknowledgment path: activating a drawer quiets
    /// the alert, and there is no setting that can turn that off.
    @Test("Activating a drawer always acknowledges its pod's alerts")
    func testActivateDrawerAcknowledges() {
        let store = isolatedStore()
        store.pods.append(store.pods.first { $0.id == "calendar" } ?? SlotPod(
            id: "calendar", name: "Calendar", systemIcon: "calendar", edge: .right,
            range: NormalizedRange(start: 0, length: 0.2), ambientStyle: .ghostDot,
            preferredZone: .glance, ergonomicWeight: 35, minLength: 0.2, isEnabled: true
        ))
        store.acknowledgedAlertIds.removeAll()

        store.activateDrawer(podId: "calendar", itemId: "calendar-event-1")

        // `acknowledgeAllAlerts(forPodId:)` records the pod-level ack; the
        // item-level ack is recorded too.
        #expect(store.isAlertAcknowledged(id: "calendar-event-1"))
    }
}
