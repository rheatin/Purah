// Tests/PurahCoreTests/OrphanedPodPruningTests.swift
import Testing
import Foundation
@testable import PurahCore
@testable import PurahUI

/// A saved layout outlives the code that produced it. When a plugin disappears
/// — unloaded, uninstalled, or deleted from the project — its pod used to stay
/// on the rail forever: a bar that reserves space, draws nothing distinctive,
/// and cannot open a drawer. These tests pin the cleanup that removes exactly
/// those pods and nothing else.
@MainActor
@Suite("Orphaned Pod Pruning")
struct OrphanedPodPruningTests {

    private func isolatedStore() -> (PurahWorkspaceStore, UserDefaults) {
        let suiteName = "test_orphan_prune_\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return (PurahWorkspaceStore(userDefaults: defaults), defaults)
    }

    private func orphanPod(id: String = "com.example.netpulse", edge: MountEdge = .right) -> SlotPod {
        SlotPod(
            id: id,
            name: "NetPulse",
            systemIcon: "dot.radiowaves.left.and.right",
            edge: edge,
            range: .init(start: 0.10, length: 0.20),
            ambientStyle: .ghostDot,
            preferredZone: .goldenAction,
            ergonomicWeight: 30,
            isEnabled: true
        )
    }

    @Test("A pod with no implementation is removed and its layout reflows")
    func testOrphanIsRemoved() {
        let (store, _) = isolatedStore()
        store.pods.append(orphanPod())
        #expect(store.pods.contains { $0.id == "com.example.netpulse" })

        let removed = store.pruneOrphanedPods { $0 == "vitals" }

        #expect(removed == ["com.example.netpulse"])
        #expect(!store.pods.contains { $0.id == "com.example.netpulse" })
    }

    @Test("A registered plugin's pod survives the sweep")
    func testRegisteredPodSurvives() {
        let (store, _) = isolatedStore()
        store.pods.append(orphanPod())

        let removed = store.pruneOrphanedPods { _ in true }

        #expect(removed.isEmpty)
        #expect(store.pods.contains { $0.id == "com.example.netpulse" })
    }

    /// Built-in ids are the product's own vocabulary. A transient registration
    /// gap — a plugin that has not mounted yet — must never delete a layout the
    /// user sculpted by hand.
    @Test("Built-in pods are never pruned, even with no implementation")
    func testBuiltInsAreImmune() {
        let (store, _) = isolatedStore()
        let before = Set(store.pods.map(\.id))

        let removed = store.pruneOrphanedPods { _ in false }

        #expect(removed.isEmpty)
        #expect(Set(store.pods.map(\.id)) == before)
    }

    @Test("Pruning clears the orphan from installed and enabled plugin ids")
    func testMarketIdsAreCleaned() {
        let (store, _) = isolatedStore()
        let market = store.marketManager
        store.pods.append(orphanPod())
        market.installedPluginIds.insert("com.example.netpulse")
        market.enabledPluginIds.insert("com.example.netpulse")

        store.pruneOrphanedPods { _ in false }

        #expect(!market.installedPluginIds.contains("com.example.netpulse"))
        #expect(!market.enabledPluginIds.contains("com.example.netpulse"))
    }

    @Test("An open drawer and its pins do not outlive the pod")
    func testActiveDrawerAndPinsAreDropped() {
        let (store, _) = isolatedStore()
        store.pods.append(orphanPod())
        store.activateDrawer(podId: "com.example.netpulse")
        store.togglePinItem(id: "com.example.netpulse")
        #expect(store.activeDrawerPodId == "com.example.netpulse")

        store.pruneOrphanedPods { _ in false }

        #expect(store.activeDrawerPodId == nil)
        #expect(!store.pinnedDrawerItemIds.contains("com.example.netpulse"))
    }

    @Test("The sweep persists, so the orphan does not return on the next launch")
    func testPruneIsPersisted() {
        let (store, defaults) = isolatedStore()
        store.pods.append(orphanPod())
        store.savePersistentState()

        store.pruneOrphanedPods { _ in false }

        let relaunched = PurahWorkspaceStore(userDefaults: defaults)
        #expect(!relaunched.pods.contains { $0.id == "com.example.netpulse" })
    }

    /// End-to-end through the real startup path: a layout saved with a
    /// dynamically loaded plugin, reopened in a build where that plugin no
    /// longer exists.
    @Test("Binding the registry prunes a plugin that no longer exists")
    func testBindStorePrunesOrphans() {
        let (store, defaults) = isolatedStore()
        store.pods.append(orphanPod())
        store.savePersistentState()

        let relaunched = PurahWorkspaceStore(userDefaults: defaults)
        #expect(relaunched.pods.contains { $0.id == "com.example.netpulse" })

        PluginRegistry.shared.bindStore(relaunched)

        #expect(!relaunched.pods.contains { $0.id == "com.example.netpulse" })
        #expect(relaunched.pods.contains { $0.id == "vitals" })
    }
}
