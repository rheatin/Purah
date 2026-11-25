// Tests/PurahCoreTests/RailSpatialEngineTests.swift
import Testing
import Foundation
import CoreGraphics
@testable import PurahCore

@Suite("Rail Spatial Engine Tests")
struct RailSpatialEngineTests {

    @Test("Sculptor strip hit zone stays flush to each screen edge")
    func testSculptorStripBounds() {
        let bounds = CGRect(x: 0, y: 0, width: 580, height: 900)
        #expect(RailSpatialEngine.isPointInsideSculptorStrip(CGPoint(x: 100, y: 400), bounds: bounds, edge: .left))
        #expect(!RailSpatialEngine.isPointInsideSculptorStrip(CGPoint(x: 260, y: 400), bounds: bounds, edge: .left))
        #expect(RailSpatialEngine.isPointInsideSculptorStrip(CGPoint(x: 500, y: 400), bounds: bounds, edge: .right))
        #expect(!RailSpatialEngine.isPointInsideSculptorStrip(CGPoint(x: 300, y: 400), bounds: bounds, edge: .right))
    }

    @Test("Page portal hit zone activates only when multiple pages exist and within top/bottom portal bands")
    func testPagePortalHitZone() {
        let bounds = CGRect(x: 0, y: 0, width: 580, height: 900)
        // AppKit y = 870 => top-down windowY = 30 (inside 20...44 top portal band)
        let topPortalLeft = CGPoint(x: 8, y: 870)
        #expect(!RailSpatialEngine.isPointOverPagePortal(topPortalLeft, bounds: bounds, edge: .left, railBarWidth: 8, pageCount: 1))
        #expect(RailSpatialEngine.isPointOverPagePortal(topPortalLeft, bounds: bounds, edge: .left, railBarWidth: 8, pageCount: 2))
        // Mid-rail y = 450 is outside both portal bands
        #expect(!RailSpatialEngine.isPointOverPagePortal(CGPoint(x: 8, y: 450), bounds: bounds, edge: .left, railBarWidth: 8, pageCount: 2))
    }

    @Test("Smart-fold stepped slice inserts +N More chip and collapses to full span on merged overview")
    func testSmartFoldAndMergedOverviewSlice() {
        let policy = PurahDecomposedPolicy(
            maxRailItems: 3,
            minChipHeight: 40.0,
            maxChipHeight: 185.0,
            spacing: 2.5,
            overflowStrategy: .smartFold
        )
        let items = (1...5).map { idx in
            PurahPluginSubItem(id: "ev-\(idx)", title: "Event \(idx)", systemIcon: "calendar")
        }

        let folded = RailSpatialEngine.resolveSteppedSlice(
            allItems: items,
            podId: "calendar",
            policy: policy,
            spanHeight: 200.0,
            isDynamicAccordion: false,
            activeDrawerItemId: nil,
            isItemPinned: { _ in false }
        )
        #expect(!folded.isMergedOverview)
        #expect(folded.displayItems.count == 3)
        #expect(folded.displayItems.last?.id == PurahPluginSubItem.moreItemsID(forPod: "calendar"))
        #expect(folded.displayItems.last?.badge == "3")

        let moreId = PurahPluginSubItem.moreItemsID(forPod: "calendar")
        let merged = RailSpatialEngine.resolveSteppedSlice(
            allItems: items,
            podId: "calendar",
            policy: policy,
            spanHeight: 200.0,
            isDynamicAccordion: false,
            activeDrawerItemId: moreId,
            isItemPinned: { _ in false }
        )
        #expect(merged.isMergedOverview)
        #expect(merged.displayItems.count == 1)
        #expect(merged.slotHeight == 200.0)
        #expect(merged.railChipIDs.count == 3)
    }

    @Test("Adjacent cluster grouping collapses multi-pod groups and preserves standalone pods")
    func testGroupAdjacentClusters() {
        let p1 = SlotPod(id: "a", name: "A", systemIcon: "star", edge: .left, range: NormalizedRange(start: 0.1, length: 0.2), ambientStyle: .ghostDot, preferredZone: .glance, ergonomicWeight: 20.0, majorGroupId: "g1")
        let p2 = SlotPod(id: "b", name: "B", systemIcon: "star", edge: .left, range: NormalizedRange(start: 0.3, length: 0.2), ambientStyle: .ghostDot, preferredZone: .glance, ergonomicWeight: 20.0, majorGroupId: "g1")
        let p3 = SlotPod(id: "c", name: "C", systemIcon: "star", edge: .left, range: NormalizedRange(start: 0.6, length: 0.2), ambientStyle: .ghostDot, preferredZone: .glance, ergonomicWeight: 20.0, majorGroupId: nil)

        let items = [
            ResolvedPodLayoutItem(pod: p1, startY: 90, spanH: 180, drawerStartY: 90, drawerSpanH: 360, majorGroupId: "g1"),
            ResolvedPodLayoutItem(pod: p2, startY: 270, spanH: 180, drawerStartY: 90, drawerSpanH: 360, majorGroupId: "g1"),
            ResolvedPodLayoutItem(pod: p3, startY: 540, spanH: 180, majorGroupId: nil)
        ]

        #expect(items[0].isSharedMajorSubBar == true)
        #expect(items[2].isSharedMajorSubBar == false)

        let clusters = RailSpatialEngine.groupAdjacentClusters(from: items)
        #expect(clusters.count == 2)
        #expect(clusters[0].groupId == "g1")
        #expect(clusters[0].items.count == 2)
        #expect(clusters[1].groupId == nil)
        #expect(clusters[1].id == "c")
    }

    @Test("resolveSteppedSlotHit matches resolveSteppedSlice pitch for chips, +N More fold slot, empty space, and composite fallback")
    @MainActor
    func testResolveSteppedSlotHitParityWithSlice() {
        let suiteName = "purah.test.spatial.hit.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = PurahWorkspaceStore(userDefaults: defaults)
        store.splitPodFromMajorGroup(id: "calendar")
        store.calendarOverflowStrategy = .smartFold
        store.calendarMaxRailEvents = 3
        store._calendarEvents = (1...5).map { idx in
            CalendarEventItem(
                id: "ev-\(idx)",
                title: "Meeting \(idx)",
                startTime: Date().addingTimeInterval(Double(idx) * 3600),
                endTime: Date().addingTimeInterval(Double(idx) * 3600 + 1800)
            )
        }

        let pod = store.pods.first(where: { $0.id == "calendar" })!
        let item = ResolvedPodLayoutItem(pod: pod, startY: 100.0, spanH: 200.0, majorGroupId: nil)
        let provider = store.capabilityProvider(for: "calendar")!
        let policy = provider.decomposedPolicy(store: store)

        let subItems = store._calendarEvents.map {
            PurahPluginSubItem(id: $0.id, title: $0.title, systemIcon: "calendar")
        }
        let slice = RailSpatialEngine.resolveSteppedSlice(
            allItems: subItems,
            podId: "calendar",
            policy: policy,
            spanHeight: 200.0,
            isDynamicAccordion: false,
            activeDrawerItemId: nil,
            isItemPinned: { _ in false }
        )

        let pitch = slice.slotHeight + policy.spacing
        let firstMidY = CGFloat(item.startY) + slice.slotHeight * 0.5
        #expect(
            RailSpatialEngine.resolveSteppedSlotHit(for: item, windowY: firstMidY, store: store, isBreathing: false)
            == .subItem("ev-1")
        )

        let lastSlotMidY = CGFloat(item.startY) + CGFloat(slice.displayItems.count - 1) * pitch + slice.slotHeight * 0.5
        #expect(
            RailSpatialEngine.resolveSteppedSlotHit(for: item, windowY: lastSlotMidY, store: store, isBreathing: false)
            == .subItem(PurahPluginSubItem.moreItemsID(forPod: "calendar"))
        )

        #expect(
            RailSpatialEngine.resolveSteppedSlotHit(for: item, windowY: CGFloat(item.startY) + slice.displaySpanHeight + 10.0, store: store, isBreathing: false)
            == .emptySpaceBelowChips
        )

        store._calendarEvents = []
        #expect(
            RailSpatialEngine.resolveSteppedSlotHit(for: item, windowY: firstMidY, store: store, isBreathing: false)
            == .composite
        )
    }
}
