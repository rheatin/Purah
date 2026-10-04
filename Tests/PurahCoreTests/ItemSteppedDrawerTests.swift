// Tests/PurahCoreTests/ItemSteppedDrawerTests.swift
import Testing
@testable import PurahCore

@Suite("Item-Level Stepped Drawer Tests")
struct ItemSteppedDrawerTests {
    @Test("Correctly assigns drawer states to active, neighbors, and distant items")
    func testSteppedStates() {
        let itemCount = 5
        let hoveredIndex = 2 // Hovering on item 2 (TEST2)

        let state0 = ItemSteppedDrawerCalculator.state(for: 0, activeIndex: hoveredIndex, totalCount: itemCount)
        let state1 = ItemSteppedDrawerCalculator.state(for: 1, activeIndex: hoveredIndex, totalCount: itemCount)
        let state2 = ItemSteppedDrawerCalculator.state(for: 2, activeIndex: hoveredIndex, totalCount: itemCount)
        let state3 = ItemSteppedDrawerCalculator.state(for: 3, activeIndex: hoveredIndex, totalCount: itemCount)
        let state4 = ItemSteppedDrawerCalculator.state(for: 4, activeIndex: hoveredIndex, totalCount: itemCount)

        // Item 2 is active full drawer
        #expect(state2 == .expandedDrawer)

        // Item 1 and Item 3 are immediate neighbors (peek tabs)
        #expect(state1 == .neighborPeek)
        #expect(state3 == .neighborPeek)

        // Item 0 and Item 4 remain flush/docked
        #expect(state0 == .dockedFlush)
        #expect(state4 == .dockedFlush)
    }

    @Test("Boundary conditions at top and bottom")
    func testBoundaryStates() {
        // Hovering at top (index 0)
        #expect(ItemSteppedDrawerCalculator.state(for: 0, activeIndex: 0, totalCount: 4) == .expandedDrawer)
        #expect(ItemSteppedDrawerCalculator.state(for: 1, activeIndex: 0, totalCount: 4) == .neighborPeek)
        #expect(ItemSteppedDrawerCalculator.state(for: 2, activeIndex: 0, totalCount: 4) == .dockedFlush)

        // Hovering at bottom (index 3)
        #expect(ItemSteppedDrawerCalculator.state(for: 3, activeIndex: 3, totalCount: 4) == .expandedDrawer)
        #expect(ItemSteppedDrawerCalculator.state(for: 2, activeIndex: 3, totalCount: 4) == .neighborPeek)
        #expect(ItemSteppedDrawerCalculator.state(for: 1, activeIndex: 3, totalCount: 4) == .dockedFlush)
    }
}
