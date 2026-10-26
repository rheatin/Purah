// Tests/PurahCoreTests/MultiDrawerFloorTests.swift
import Testing
import Foundation
@testable import PurahCore
@testable import PurahUI

/// When several drawers are open at once the expanded spans share the rail.
/// Each one must hold the floor its own plugin declared — a plugin asking for
/// 150pt cannot be clipped to a number the solver picked for a neighbour.
@MainActor
@Suite("Multi-Drawer Shared Rail Floor")
struct MultiDrawerFloorTests {

    private func makeStore() -> PurahWorkspaceStore {
        let suiteName = "test_multi_drawer_\(UUID().uuidString)"
        return PurahWorkspaceStore(userDefaults: UserDefaults(suiteName: suiteName)!)
    }

    /// Pins every pod on the left rail, so the multi-expanded branch runs with
    /// as little room as the rail can offer.
    private func pinAllLeftPods(_ store: PurahWorkspaceStore) {
        store.resetMajorGroups(for: .left)
        for pod in store.pods where pod.edge == .left {
            if !pod.isEnabled {
                store.togglePodEnabled(id: pod.id)
            }
            store.splitPodFromMajorGroup(id: pod.id)
        }
        for pod in store.pods where pod.edge == .left {
            if !store.isItemPinned(id: pod.id) {
                store.togglePinItem(id: pod.id)
            }
        }
    }

    @Test("Pinned drawers never fall below their plugin's declared floor")
    func testPinnedDrawersKeepDeclaredFloor() throws {
        let store = makeStore()
        pinAllLeftPods(store)

        let totalHeight = 900.0
        let layout = store.resolvedPhysicalLayout(for: .left, totalHeight: totalHeight)
        let pinned = layout.filter { store.isItemPinned(id: $0.pod.id) }
        #expect(pinned.count >= 3, "expected several pinned drawers to share the rail")

        for item in pinned {
            let declared = Double(store.minimumDrawerHeight(for: item.pod.id))
            // Squeezing below the floor is only legitimate if the rail simply
            // cannot hold every floor at once — and then the shortfall is
            // shared, not silently pinned on one unlucky pod.
            let sumFloors = pinned.reduce(0.0) { $0 + Double(store.minimumDrawerHeight(for: $1.pod.id)) }
            if sumFloors <= totalHeight {
                #expect(item.spanH >= declared - 0.5,
                        "\(item.pod.id) got \(item.spanH)pt but declared a \(declared)pt floor")
            }
        }
    }

    @Test("Pinned drawers stay non-overlapping and on-screen")
    func testPinnedDrawersStayInsideRail() throws {
        let store = makeStore()
        pinAllLeftPods(store)

        let totalHeight = 900.0
        let layout = store.resolvedPhysicalLayout(for: .left, totalHeight: totalHeight)
        #expect(!layout.isEmpty)

        for (index, item) in layout.enumerated() {
            #expect(item.startY >= 0)
            #expect(item.startY + item.spanH <= totalHeight + 0.5)
            if index > 0 {
                let previous = layout[index - 1]
                #expect(item.startY >= previous.startY + previous.spanH - 0.01,
                        "\(item.pod.id) overlaps \(previous.pod.id)")
            }
        }
    }

    @Test("A hovered drawer gets more room than an idle neighbour")
    func testHoveredDrawerOutranksIdle() throws {
        let store = makeStore()
        store.resetMajorGroups(for: .left)
        for pod in store.pods where pod.edge == .left && !pod.isEnabled {
            store.togglePodEnabled(id: pod.id)
        }

        let totalHeight = 900.0
        let idle = store.resolvedPhysicalLayout(for: .left, totalHeight: totalHeight)
        let idleVitals = try #require(idle.first { $0.pod.id == "vitals" })

        store.activateDrawer(podId: "vitals")
        let active = store.resolvedPhysicalLayout(for: .left, totalHeight: totalHeight)
        let activeVitals = try #require(active.first { $0.pod.id == "vitals" })

        #expect(activeVitals.spanH > idleVitals.spanH,
                "hovering must expand the drawer beyond its idle span")
    }
}
