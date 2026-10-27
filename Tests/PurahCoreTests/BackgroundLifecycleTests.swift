// Tests/PurahCoreTests/BackgroundLifecycleTests.swift
import Testing
import Foundation
import SwiftUI
@testable import PurahCore
@testable import PurahUI

/// Purah is a background accessory: it is *supposed* to sit idle for hours.
/// That makes a leaked timer or polling loop uniquely bad — there is no window
/// closing to reveal it, just warmth and battery drain the user eventually
/// notices. These tests assert the lifecycle contracts that keep it idle.
@Suite("Background Lifecycle Tests", .serialized)
@MainActor
struct BackgroundLifecycleTests {

    /// A plugin that polls, so mounting and unmounting it exercises the
    /// registry's polling task bookkeeping.
    private final class PollingSpyPlugin: PurahPodPlugin {
        nonisolated let manifest = PurahPluginManifest(
            id: "polling-spy",
            displayName: "Polling Spy",
            systemIcon: "timer",
            author: "Test",
            version: "1.0.0",
            description: "Counts its polling ticks.",
            defaultEdge: .left,
            preferredZone: .goldenAction,
            ergonomicWeight: 30.0,
            minLengthRatio: 0.15,
            defaultColorHex: "#00F5D4",
            category: .lightweight,
            permissions: []
        )

        /// Fast enough that a test can observe ticks, slow enough not to spin.
        var preferredPollingInterval: TimeInterval? { 0.02 }
        private(set) var tickCount = 0
        private(set) var mountCount = 0

        func onMount(store: PurahWorkspaceStore) { mountCount += 1 }
        func onPollingTick(store: PurahWorkspaceStore) async { tickCount += 1 }

        func makeRailBarView(context: PurahPluginContext) -> AnyView { AnyView(EmptyView()) }
        func makeDrawerView(context: PurahPluginContext) -> AnyView { AnyView(EmptyView()) }
    }

    /// Each test gets its own defaults domain: the store persists to it, and a
    /// shared domain would make the tests order-dependent.
    private static func makeStore() -> PurahWorkspaceStore {
        let suite = "purah.test.lifecycle.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        return PurahWorkspaceStore(userDefaults: defaults)
    }

    /// Registers a plugin and gives the store a matching enabled pod.
    ///
    /// `register` alone only records the plugin — it does not create a pod — and
    /// the polling loop requires a pod that genuinely exists and is enabled
    /// (a strict `contains`, not a defaulted `first(where:)`). Without this the
    /// task runs but never ticks, which is exactly what the first version of
    /// this test discovered.
    private static func makeInstalled(
        _ registry: PluginRegistry, store: PurahWorkspaceStore, plugin: PollingSpyPlugin
    ) {
        registry.register(plugin)
        let manifest = plugin.manifest
        if let idx = store.pods.firstIndex(where: { $0.id == manifest.id }) {
            store.pods[idx].isEnabled = true
        } else {
            store.pods.append(SlotPod(
                id: manifest.id,
                nameKey: manifest.id,
                defaultName: manifest.displayName,
                systemIcon: manifest.systemIcon,
                edge: manifest.defaultEdge,
                range: NormalizedRange(start: 0.4, length: 0.15),
                ambientStyle: .ghostDot,
                preferredZone: manifest.preferredZone,
                ergonomicWeight: manifest.ergonomicWeight,
                isEnabled: true
            ))
        }
    }

    @Test("Unmounting a plugin stops its polling task")
    func testUnmountStopsPolling() async {
        let registry = PluginRegistry()
        let store = Self.makeStore()
        let plugin = PollingSpyPlugin()

        Self.makeInstalled(registry, store: store, plugin: plugin)
        defer { registry.unregister(id: plugin.manifest.id, store: store) }

        let before = registry.activePollingTaskCount
        registry.mountPlugin(id: plugin.manifest.id, store: store)
        #expect(registry.activePollingTaskCount > before,
                "Mounting a polling plugin must start exactly one task")

        registry.unmountPlugin(id: plugin.manifest.id, store: store)
        #expect(registry.activePollingTaskCount == before,
                "Unmounting must leave no polling task behind")
    }

    /// Waits until `predicate` holds, or gives up.
    ///
    /// A fixed `sleep` is not enough here: the polling task hops to the main
    /// actor, and when the whole suite runs the main actor is busy with other
    /// tests, so a 120ms sleep can expire before the first tick lands. Polling
    /// for the condition makes the test wait for the event it cares about
    /// instead of for a wall-clock guess.
    private static func waitUntil(
        timeout: Duration = .seconds(5),
        _ predicate: @MainActor () -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if predicate() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return predicate()
    }

    @Test("An unmounted plugin stops ticking")
    func testUnmountStopsTicks() async throws {
        let registry = PluginRegistry()
        let store = Self.makeStore()
        let plugin = PollingSpyPlugin()

        Self.makeInstalled(registry, store: store, plugin: plugin)
        defer { registry.unregister(id: plugin.manifest.id, store: store) }

        registry.mountPlugin(id: plugin.manifest.id, store: store)
        let didTick = await Self.waitUntil { plugin.tickCount > 0 }
        #expect(didTick, "The polling task never ran")

        registry.unmountPlugin(id: plugin.manifest.id, store: store)
        // Let any in-flight tick land before sampling the baseline.
        try await Task.sleep(for: .milliseconds(60))
        let afterUnmount = plugin.tickCount

        // Several polling intervals; if the task survived the unmount it will
        // have ticked by now.
        try await Task.sleep(for: .milliseconds(200))
        #expect(plugin.tickCount == afterUnmount,
                "A disabled pod kept polling — this is the idle-CPU leak")
    }

    @Test("Mounting twice does not start a second polling task")
    func testMountIsIdempotent() {
        let registry = PluginRegistry()
        let store = Self.makeStore()
        let plugin = PollingSpyPlugin()

        Self.makeInstalled(registry, store: store, plugin: plugin)
        defer { registry.unregister(id: plugin.manifest.id, store: store) }

        let before = registry.activePollingTaskCount
        registry.mountPlugin(id: plugin.manifest.id, store: store)
        let afterFirst = registry.activePollingTaskCount
        registry.mountPlugin(id: plugin.manifest.id, store: store)

        #expect(registry.activePollingTaskCount == afterFirst,
                "A second mount must not add another timer")
        #expect(afterFirst - before == 1)
    }

    @Test("Repeated mount/unmount cycles do not accumulate tasks")
    func testNoAccumulationAcrossCycles() {
        let registry = PluginRegistry()
        let store = Self.makeStore()
        let plugin = PollingSpyPlugin()

        Self.makeInstalled(registry, store: store, plugin: plugin)
        defer { registry.unregister(id: plugin.manifest.id, store: store) }

        let baseline = registry.activePollingTaskCount
        // The drawer opens and closes constantly during a working day. If each
        // cycle leaked a task, this would be the vector.
        for _ in 0..<20 {
            registry.mountPlugin(id: plugin.manifest.id, store: store)
            registry.unmountPlugin(id: plugin.manifest.id, store: store)
        }
        #expect(registry.activePollingTaskCount == baseline,
                "20 mount/unmount cycles left \(registry.activePollingTaskCount - baseline) tasks")
    }
}
