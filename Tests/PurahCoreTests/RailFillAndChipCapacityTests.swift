// Tests/PurahCoreTests/RailFillAndChipCapacityTests.swift
import Testing
import Foundation
import PurahCore
import PurahUI

/// Two rules that together keep a rail from fragmenting:
///
/// - switching decomposition on resizes the pod once to the height its chips
///   need (a five-role pod left one chip tall used to render exactly one of
///   them, whatever the "max on rail" setting said), while a length sculpted
///   by hand stays exactly as sculpted afterwards; and
/// - a rail with room to spare spends it on the pods instead of leaving dead
///   stretches between them — in proportion, so a pod sculpted short stays the
///   short one.
@MainActor
@Suite("Rail fill & chip capacity")
struct RailFillAndChipCapacityTests {

    private func makeIsolatedStore(_ label: String) -> (PurahWorkspaceStore, UserDefaults, String) {
        let suite = "test_rail_fill_\(label)_\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (PurahWorkspaceStore(userDefaults: defaults), defaults, suite)
    }

    /// Puts exactly `entries` (podId, start, length) on the left rail, alone.
    private func mount(
        _ entries: [(id: String, start: Double, length: Double)],
        on store: PurahWorkspaceStore,
        edge: MountEdge = .left
    ) {
        for idx in store.pods.indices {
            store.pods[idx].isEnabled = false
            store.pods[idx].majorGroupId = nil
        }
        for entry in entries {
            guard let idx = store.pods.firstIndex(where: { $0.id == entry.id }) else {
                Issue.record("Pod \(entry.id) is missing from the store")
                continue
            }
            store.pods[idx].isEnabled = true
            store.pods[idx].edge = edge
            store.pods[idx].pageIndex = 0
            store.pods[idx].range = NormalizedRange(start: entry.start, length: entry.length)
        }
        store.invalidateLayoutCache()
    }

    @Test("A decomposed pod is tall enough to show every chip it reports")
    func decomposedPodFitsItsChips() throws {
        let (store, isolated, suite) = makeIsolatedStore("chips")
        defer { isolated.removePersistentDomain(forName: suite) }

        let storage = ScopedPluginStorage(pluginId: "ai", defaults: isolated)
        let repo = PurahDiskRepository<AIChatSession>(
            pluginId: "ai_railfill_test",
            customStorage: PurahPluginFileStorage(
                pluginId: "ai_railfill_test",
                customBaseDirectory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("purah_railfill_\(UUID().uuidString)")
            )
        )
        let state = AIAssistantPluginState(storage: storage, repository: repo)
        let plugin = AIAssistantPlugin(state: state)
        store.registerCapabilityProvider(plugin)
        plugin.onMount(store: store)

        state.maxRailRoles = 5
        var enabled = 0
        for idx in state.rolePresets.indices {
            state.rolePresets[idx].isEnabled = enabled < 5
            if enabled < 5 { enabled += 1 }
        }

        // The pod had been left about one chip tall before the mode switch.
        mount([("ai", 0.30, 0.052)], on: store, edge: .right)
        store.overriddenScreenHeight = 1000.0

        // Switching the mode on is a resize: five roles need five chips, and
        // the pod is grown once to meet them.
        store.togglePodDecomposedInSculptor(podId: "ai")
        #expect(store.isPodDecomposed("ai"))

        let layout = store.resolvedPhysicalLayout(for: .right, totalHeight: 1000.0)
        let item = try #require(layout.first(where: { $0.pod.id == "ai" }))
        let policy = plugin.decomposedPolicy(store: store)

        let chipsThatFit = Int((item.spanH + Double(policy.spacing)) / (Double(policy.minChipHeight) + Double(policy.spacing)))
        #expect(plugin.subItemCount(store: store) == 5)
        #expect(
            chipsThatFit >= plugin.subItemCount(store: store),
            "a \(item.spanH)pt pod only fits \(chipsThatFit) of \(plugin.subItemCount(store: store)) chips"
        )
        #expect(item.spanH >= Double(policy.calculateMinimumHeight(activeCount: 5)) - 0.5)

        // And the sculpted length wins afterwards: shortening it on purpose is
        // not inflated back to the chips' height.
        store.updatePodRange(id: "ai", newRange: NormalizedRange(start: 0.30, length: 0.08))
        let shortened = try #require(
            store.resolvedPhysicalLayout(for: .right, totalHeight: 1000.0)
                .first(where: { $0.pod.id == "ai" })
        )
        #expect(shortened.spanH <= 90.0)
    }

    @Test("A rail with room to spare spends it on the pods, leaving no dead stretches")
    func railWithSlackGrowsItsPodsProportionally() throws {
        let (store, isolated, suite) = makeIsolatedStore("fill")
        defer { isolated.removePersistentDomain(forName: suite) }

        mount([
            ("music", 0.02, 0.25),
            ("shelf", 0.38, 0.22),
            ("terminal", 0.72, 0.20)
        ], on: store)

        let totalHeight = 900.0
        let layout = store.resolvedPhysicalLayout(for: .left, totalHeight: totalHeight)
        #expect(layout.count == 3)
        let top = try #require(layout.first(where: { $0.pod.id == "music" }))
        let middle = try #require(layout.first(where: { $0.pod.id == "shelf" }))
        let bottom = try #require(layout.first(where: { $0.pod.id == "terminal" }))

        // Consecutive pods are separated by the standard 8pt cluster gap.
        #expect(abs((middle.startY - (top.startY + top.spanH)) - 8.0) < 0.6)
        #expect(abs((bottom.startY - (middle.startY + middle.spanH)) - 8.0) < 0.6)

        // The whole usable rail is spent: no dead stretch above the first pod,
        // between pods, or below the last one.
        #expect(abs(top.startY - 16.0) < 0.6)
        #expect(abs((bottom.startY + bottom.spanH) - (totalHeight - 16.0)) < 0.6)

        // Grown in proportion to the sculpted lengths, so the short panel is
        // still the short panel.
        let sculptedRatio = (0.25 * totalHeight) / (0.22 * totalHeight)
        #expect(abs(top.spanH / middle.spanH - sculptedRatio) < 0.02)
        #expect(bottom.spanH < middle.spanH)
        #expect(top.spanH > 0.25 * totalHeight)
    }

    @Test("A lone pod keeps the length it was sculpted at")
    func lonePodKeepsItsSculptedLength() throws {
        let (store, isolated, suite) = makeIsolatedStore("lone")
        defer { isolated.removePersistentDomain(forName: suite) }

        mount([("music", 0.40, 0.20)], on: store)

        let totalHeight = 900.0
        let layout = store.resolvedPhysicalLayout(for: .left, totalHeight: totalHeight)
        let music = try #require(layout.first(where: { $0.pod.id == "music" }))
        #expect(abs(music.startY - 0.40 * totalHeight) < 0.6)
        #expect(abs(music.spanH - 0.20 * totalHeight) < 0.6)
    }

    @Test("Sculpting is exempt: hand-placed gaps stay put while the sculptor is open")
    func sculptingKeepsHandPlacedGaps() throws {
        let (store, isolated, suite) = makeIsolatedStore("sculpt")
        defer { isolated.removePersistentDomain(forName: suite) }

        mount([
            ("vitals", 0.10, 0.20),
            ("shelf", 0.50, 0.16),
            ("music", 0.80, 0.12)
        ], on: store)
        store.setLiveRailEditingMode(true)

        let totalHeight = 900.0
        let layout = store.resolvedPhysicalLayout(for: .left, totalHeight: totalHeight)
        let shelf = try #require(layout.first(where: { $0.pod.id == "shelf" }))
        let music = try #require(layout.first(where: { $0.pod.id == "music" }))
        #expect(
            music.startY - (shelf.startY + shelf.spanH) > 40.0,
            "the sculptor must show the gap exactly as it was hand-placed"
        )
        #expect(abs(music.startY - 0.80 * totalHeight) < 0.6)
    }
}
