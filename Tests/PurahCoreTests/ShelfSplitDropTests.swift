// Tests/PurahCoreTests/ShelfSplitDropTests.swift
import Testing
@testable import PurahUI

/// The Drop Shelf routes a drag by where the pointer is in the card: top half
/// stashes, bottom half AirDrops. Getting this wrong does not look like a
/// layout bug — it silently sends someone's file to a nearby device.
@Suite("Drop Shelf Split Routing Tests")
@MainActor
struct ShelfSplitDropTests {

    @Test("The top half stashes and the bottom half AirDrops")
    func halvesRouteToTheirZone() {
        #expect(ShelfSplitDropDelegate.zone(at: 10, cardHeight: 200) == .stash)
        #expect(ShelfSplitDropDelegate.zone(at: 190, cardHeight: 200) == .airDrop)
    }

    @Test("An exactly centred pointer belongs to AirDrop")
    func centreBelongsToAirDrop() {
        #expect(ShelfSplitDropDelegate.zone(at: 100, cardHeight: 200) == .airDrop)
        #expect(ShelfSplitDropDelegate.zone(at: 99.9, cardHeight: 200) == .stash)
    }

    @Test("A card that reports no height yet cannot AirDrop by accident")
    func unmeasuredCardDoesNotAirDrop() {
        // A drag can arrive before the first layout pass. Dividing by zero is
        // guarded, but the guard has to land on stash: silently beaming a file
        // to a nearby device is not a survivable default for a mis-measured card.
        #expect(ShelfSplitDropDelegate.zone(at: 0, cardHeight: 0) == .stash)
        #expect(ShelfSplitDropDelegate.zone(at: 120, cardHeight: 0) == .airDrop)
    }
}
