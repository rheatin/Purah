// Tests/PurahCoreTests/VitalsBandBudgetTests.swift
import Testing
import CoreGraphics
@testable import PurahUI

/// The drawer's height rule: a chart grows up to twice its natural height,
/// every remaining point goes to a list-like band, and the result always sums
/// to the height that was available.
@Suite("Vitals Band Budget")
struct VitalsBandBudgetTests {
    private func sum(_ values: [CGFloat]) -> CGFloat {
        values.reduce(0, +)
    }

    @Test("A short drawer shrinks every band by the same share instead of keeping a floor")
    func shortDrawer() {
        let bands: [VitalsBandBudget.Band] = [
            .chart(natural: 200),
            .chart(natural: 100),
            .chart(natural: 50)
        ]
        let heights = VitalsBandBudget.allocate(available: 300, bands: bands)

        #expect(abs(sum(heights) - 300) < 0.001)
        #expect(abs(heights[0] - 200 * 300 / 350) < 0.001)
        #expect(abs(heights[1] - 100 * 300 / 350) < 0.001)
        #expect(abs(heights[2] - 50 * 300 / 350) < 0.001)
        #expect(heights[0] < 200, "no band may keep its natural size when the drawer is short")
    }

    @Test("Exactly natural draws every band at its natural height")
    func exactlyNatural() {
        let bands: [VitalsBandBudget.Band] = [
            .chart(natural: 120),
            .chart(natural: 80),
            .list(natural: 50)
        ]
        let heights = VitalsBandBudget.allocate(available: 250, bands: bands)

        #expect(heights == [120, 80, 50])
        #expect(abs(sum(heights) - 250) < 0.001)
    }

    @Test("A tall drawer caps the charts at twice natural and the list absorbs the rest")
    func tallDrawer() {
        let bands: [VitalsBandBudget.Band] = [
            .chart(natural: 100),
            .chart(natural: 100),
            .list(natural: 80)
        ]
        let heights = VitalsBandBudget.allocate(available: 700, bands: bands)

        #expect(abs(sum(heights) - 700) < 0.001)
        #expect(heights[0] <= 200.0001)
        #expect(heights[1] <= 200.0001)
        #expect(abs(heights[2] - 300) < 0.001, "the list takes every point the charts could not")
    }

    @Test("The capped share is redistributed rather than dropped when one chart hits its cap first")
    func unevenCharts() {
        let bands: [VitalsBandBudget.Band] = [
            .chart(natural: 40),
            .chart(natural: 100),
            .list(natural: 60)
        ]
        let heights = VitalsBandBudget.allocate(available: 600, bands: bands)

        #expect(abs(sum(heights) - 600) < 0.001)
        #expect(heights[0] <= 80.0001)
        #expect(heights[1] <= 200.0001)
    }

    @Test("A fixed band (a hairline, a pinned footer) never grows")
    func fixedBandsDoNotGrow() {
        let bands: [VitalsBandBudget.Band] = [
            .chart(natural: 100),
            .fixed(1),
            .list(natural: 50)
        ]
        let heights = VitalsBandBudget.allocate(available: 400, bands: bands)

        #expect(abs(heights[1] - 1) < 0.0001)
        #expect(abs(sum(heights) - 400) < 0.001)
    }

    @Test("A tab of nothing but capped charts still fills its height")
    func allChartsCapped() {
        let bands: [VitalsBandBudget.Band] = [
            .chart(natural: 142),
            .chart(natural: 89),
            .chart(natural: 103)
        ]
        let heights = VitalsBandBudget.allocate(available: 816, bands: bands)

        #expect(abs(sum(heights) - 816) < 0.001)
        #expect(heights[0] > 284 - 0.001, "the spare points must land somewhere")
    }

    @Test("An empty drawer returns nothing")
    func emptyInput() {
        #expect(VitalsBandBudget.allocate(available: 300, bands: []).isEmpty)
    }

    @Test("A short body keeps the natural height and scrolls instead of squashing content")
    func drawingHeightKeepsContentLegible() {
        let bands: [VitalsBandBudget.Band] = [
            .chart(natural: 62),
            .chart(natural: 62),
            .fixed(0.6),
            .chart(natural: 54)
        ]
        let short = VitalsBandBudget.drawingHeight(available: 112, bands: bands)
        let tall = VitalsBandBudget.drawingHeight(available: 400, bands: bands)

        #expect(abs(short - 178.6) < 0.001, "the sheet keeps its content height and the host scrolls it")
        #expect(abs(tall - 400) < 0.001)
        #expect(abs(sum(VitalsBandBudget.allocate(available: short, bands: bands)) - short) < 0.001)
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

@Suite("Vitals Tab Layout")
struct VitalsTabLayoutTests {
    @Test("A short drawer keeps the instruments legible and shows no list")
    func shortDrawerKeepsNaturalContent() {
        let split = VitalsTabLayout.split(
            available: 100,
            naturalContent: 300,
            growthCap: 220
        )
        #expect(split.content == 300)
        #expect(split.list == 0)
    }

    @Test("A tall drawer stops the instruments at the growth cap and gives the rest to the list")
    func tallDrawerFillsWithTheList() {
        let split = VitalsTabLayout.split(
            available: 800,
            naturalContent: 200,
            growthCap: 220
        )
        #expect(split.content == 220)
        #expect(split.list == 580)
    }

    @Test("A capped list never makes the instruments shorter than they draw")
    func naturalContentAboveTheCapWins() {
        let split = VitalsTabLayout.split(
            available: 800,
            naturalContent: 334,
            growthCap: 220
        )
        #expect(split.content == 334)
        #expect(split.list == 466)
    }

    @Test("Exactly natural gives the whole drawer to the instruments")
    func exactlyNatural() {
        let split = VitalsTabLayout.split(
            available: 200,
            naturalContent: 200,
            growthCap: 220
        )
        #expect(split.content == 200)
        #expect(split.list == 0)
    }
}
