// Tests/PurahCoreTests/VitalsTabLayoutTests.swift
import Testing
import CoreGraphics
@testable import PurahUI

/// The drawer's height rule: the instruments draw at their natural size, and
/// every point above that belongs to the process list below them.
@Suite("Vitals Tab Layout")
struct VitalsTabLayoutTests {
    @Test("A short drawer keeps its instruments at natural height and lists nothing")
    func shortDrawerKeepsNaturalContent() {
        let split = VitalsTabLayout.split(available: 100, naturalContent: 300)

        #expect(split.content == 300)
        #expect(split.list == 0)
    }

    @Test("A tall drawer stops the instruments at natural height and gives the rest to the list")
    func tallDrawerFillsWithTheList() {
        let split = VitalsTabLayout.split(available: 800, naturalContent: 200)

        #expect(split.content == 200)
        #expect(split.list == 600)
    }

    @Test("Exactly natural gives the whole drawer to the instruments")
    func exactlyNatural() {
        let split = VitalsTabLayout.split(available: 200, naturalContent: 200)

        #expect(split.content == 200)
        #expect(split.list == 0)
    }

    @Test("A drawer smaller than zero lists nothing")
    func negativeAvailable() {
        let split = VitalsTabLayout.split(available: -40, naturalContent: 120)

        #expect(split.content == 120)
        #expect(split.list == 0)
    }
}

@Suite("Vitals Process List Budget")
struct VitalsProcessListBudgetTests {
    @Test("The inspector shows what fits, never fewer than twelve")
    func rowCounts() {
        #expect(VitalsProcessListBudget.visibleRowCount(available: 1200, total: 646) == 42)
        #expect(VitalsProcessListBudget.visibleRowCount(available: 1200, total: 20) == 20)
        #expect(VitalsProcessListBudget.visibleRowCount(available: 120, total: 646) == 12)
    }

    @Test("A short drawer knows its real fit even when twelve rows are forced")
    func fitIsIndependentOfTheMinimum() {
        let fit = VitalsProcessListBudget.rowsThatFit(available: 120)
        let shown = VitalsProcessListBudget.visibleRowCount(available: 120, total: 646)
        #expect(fit < shown, "the view scrolls the overflow instead of clipping it")
    }
}
