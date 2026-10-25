// Tests/PurahCoreTests/ChipAnchoringTests.swift
import Testing
import Foundation
import AppKit
import PurahUI
@testable import PurahCore

/// Hovering a decomposed chip must extrude the drawer from *that* chip.
///
/// Regression: the solver used to split the pod's preferred expanded height
/// evenly across every chip, so hovering the second chip of a squeezed pod
/// shoved it ~109pt down the rail and the card appeared to spring out of the
/// middle of the pod instead of from under the cursor.
@Suite("Chip Anchoring Tests")
@MainActor
struct ChipAnchoringTests {

    private func makeStore() -> PurahWorkspaceStore {
        let suite = UserDefaults(suiteName: "test_chip_anchor_\(UUID().uuidString)")!
        let store = PurahWorkspaceStore(userDefaults: suite)
        store.isDynamicBreathingEnabled = true
        store.isAlwaysCompactBreathing = true
        return store
    }

    private func calendarSlots(_ store: PurahWorkspaceStore, height: Double = 900.0) -> [PodChipSlot] {
        store.resolvedPhysicalLayout(for: .right, totalHeight: height)
            .first(where: { $0.pod.id == "calendar" })?
            .chipSlots ?? []
    }

    @Test("Hovering a lower chip keeps its top edge fixed")
    func testLowerChipStaysPut() throws {
        let store = makeStore()
        let provider = try #require(store.capabilityProvider(for: "calendar"))

        store.dismissActiveDrawer()
        store.invalidateLayoutCache()
        let idle = calendarSlots(store)
        let idleSecond = try #require(idle.indices.contains(1) ? idle[1] : nil)

        let secondId = try #require(provider.subItemId(at: 1, store: store))
        store.hoveredPodId = "calendar"
        store.activeDrawerPodId = "calendar"
        store.activeDrawerItemId = secondId
        store.invalidateLayoutCache()

        let expanded = calendarSlots(store)
        let active = try #require(expanded.first(where: { $0.isActive }))

        #expect(active.id == secondId)
        #expect(abs(active.top - idleSecond.top) < 0.001,
                "Hovered chip must not move: idle top \(idleSecond.top), expanded top \(active.top)")
    }

    @Test("Only the hovered chip grows; neighbours keep their docked height")
    func testNeighboursKeepDockedHeight() throws {
        let store = makeStore()
        let provider = try #require(store.capabilityProvider(for: "calendar"))

        store.dismissActiveDrawer()
        store.invalidateLayoutCache()
        let idle = calendarSlots(store)
        let idleHeights = idle.map(\.height)

        let firstId = try #require(provider.subItemId(at: 0, store: store))
        store.hoveredPodId = "calendar"
        store.activeDrawerPodId = "calendar"
        store.activeDrawerItemId = firstId
        store.invalidateLayoutCache()

        let expanded = calendarSlots(store)
        #expect(expanded[0].isActive)
        #expect(expanded[0].height > idleHeights[0])
        for i in 1..<expanded.count {
            #expect(abs(expanded[i].height - idleHeights[i]) < 0.001,
                    "Chip \(i) must keep its docked height")
        }
    }

    @Test("Every chip stays contiguous with no overlap after a chip grows")
    func testChipsStayContiguous() throws {
        let store = makeStore()
        let provider = try #require(store.capabilityProvider(for: "calendar"))
        let spacing = provider.decomposedPolicy(store: store).spacing

        let secondId = try #require(provider.subItemId(at: 1, store: store))
        store.hoveredPodId = "calendar"
        store.activeDrawerPodId = "calendar"
        store.activeDrawerItemId = secondId
        store.invalidateLayoutCache()

        let slots = calendarSlots(store)
        for i in 0..<(slots.count - 1) {
            let expected = slots[i].top + slots[i].height + Double(spacing)
            #expect(abs(slots[i + 1].top - expected) < 0.001,
                    "Chip \(i + 1) must sit directly below chip \(i) plus spacing")
        }
    }

    @Test("Expanded pod span equals the sum of its chips")
    func testExpandedSpanCoversChips() throws {
        let store = makeStore()
        let provider = try #require(store.capabilityProvider(for: "calendar"))
        let spacing = Double(provider.decomposedPolicy(store: store).spacing)

        let firstId = try #require(provider.subItemId(at: 0, store: store))
        store.hoveredPodId = "calendar"
        store.activeDrawerPodId = "calendar"
        store.activeDrawerItemId = firstId
        store.invalidateLayoutCache()

        let item = try #require(
            store.resolvedPhysicalLayout(for: .right, totalHeight: 900.0)
                .first(where: { $0.pod.id == "calendar" })
        )
        let chipsTotal = item.chipSlots.reduce(0.0) { $0 + $1.height }
            + spacing * Double(max(item.chipSlots.count - 1, 0))
        #expect(abs(chipsTotal - item.spanH) < 0.5,
                "Pod span \(item.spanH) must cover chips \(chipsTotal)")
    }

    @Test("Hit testing follows the solver's chip positions")
    func testHitTestMatchesChips() throws {
        let store = makeStore()
        let provider = try #require(store.capabilityProvider(for: "calendar"))

        let secondId = try #require(provider.subItemId(at: 1, store: store))
        store.hoveredPodId = "calendar"
        store.activeDrawerPodId = "calendar"
        store.activeDrawerItemId = secondId
        store.invalidateLayoutCache()

        let height = 900.0
        let slots = calendarSlots(store)
        let active = try #require(slots.first(where: { $0.isActive }))
        let frames = store.activeDrawerCardFrames(for: .right, totalHeight: height)
        #expect(!frames.isEmpty, "An active chip must publish a hit box")

        // Card frames are reported bottom-up; convert the chip's top-down span.
        let expectedTop = height - active.top
        let expectedBottom = height - (active.top + active.height)
        let covers = frames.contains { frame in
            frame.minY <= expectedBottom + 8.0 && frame.maxY >= expectedTop - 8.0
        }
        #expect(covers, "Hit box must cover the expanded chip at y=\(active.top)")
    }
}
