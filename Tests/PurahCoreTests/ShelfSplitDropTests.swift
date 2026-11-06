// Tests/PurahCoreTests/ShelfSplitDropTests.swift
import Testing
import Foundation
@testable import PurahUI

/// The Drop Shelf routes a drag by where the pointer is in the card: Link,
/// Move, then AirDrop. Getting this wrong can move someone's file or send it to
/// a nearby device, so every boundary is pinned.
@Suite("Drop Shelf Split Routing Tests")
@MainActor
struct ShelfSplitDropTests {

    @Test("Three equal zones route Link, Move, then AirDrop")
    func thirdsRouteToTheirZone() {
        let linkMove: CGFloat = ShelfDropZoneGeometry.linkMoveBoundary(forCardHeight: 300)
        let moveAirDrop: CGFloat = ShelfDropZoneGeometry.moveAirDropBoundary(forCardHeight: 300)
        #expect(ShelfSplitDropDelegate.zone(at: 0, cardHeight: 300) == .link)
        #expect(ShelfSplitDropDelegate.zone(at: linkMove - 0.001, cardHeight: 300) == .link)
        #expect(ShelfSplitDropDelegate.zone(at: linkMove, cardHeight: 300) == .move)
        #expect(ShelfSplitDropDelegate.zone(at: moveAirDrop - 0.001, cardHeight: 300) == .move)
        #expect(ShelfSplitDropDelegate.zone(at: moveAirDrop, cardHeight: 300) == .airDrop)
        #expect(ShelfSplitDropDelegate.zone(at: 300, cardHeight: 300) == .airDrop)
    }

    @Test("A pointer inside a drawn box routes to that box's own zone")
    func drawnBoxesRouteToTheirZone() {
        // The boxes are drawn between padding and spacing rather than on plain
        // thirds, so aiming at a visible box must never slip into its neighbour.
        for height in [150.0, 130.0] {
            let padding: CGFloat = ShelfDropZoneGeometry.padding
            let spacing: CGFloat = ShelfDropZoneGeometry.spacing
            let box: CGFloat = ShelfDropZoneGeometry.zoneHeight(forCardHeight: height)
            let linkTop: CGFloat = padding
            let moveTop: CGFloat = padding + box + spacing

            #expect(ShelfSplitDropDelegate.zone(at: linkTop + 1, cardHeight: height) == .link)
            #expect(ShelfSplitDropDelegate.zone(at: linkTop + box - 1, cardHeight: height) == .link)
            #expect(ShelfSplitDropDelegate.zone(at: moveTop + 1, cardHeight: height) == .move)
            #expect(ShelfSplitDropDelegate.zone(at: moveTop + box - 1, cardHeight: height) == .move)
        }
    }

    @Test("A card that reports no height yet cannot AirDrop by accident")
    func unmeasuredCardDoesNotAirDrop() {
        // A drag can arrive before the first layout pass. With no height there
        // are no drawn boxes to aim at, so every point resolves to Link — the
        // top third, and the only zone that touches neither the person's disk
        // (Move, the middle third) nor a nearby device (AirDrop, the bottom
        // third).
        #expect(ShelfSplitDropDelegate.zone(at: 0, cardHeight: 0) == .link)
        #expect(ShelfSplitDropDelegate.zone(at: 0.2, cardHeight: 0) == .link)
        #expect(ShelfSplitDropDelegate.zone(at: 0.4, cardHeight: 0) == .link)
        #expect(ShelfSplitDropDelegate.zone(at: 120, cardHeight: 0) == .link)
    }
}
