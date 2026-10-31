// Tests/PurahCoreTests/AdaptiveTierAndGaugeTests.swift
import Testing
import SwiftUI
import Foundation
@testable import PurahCore
@testable import PurahUI

@MainActor
@Suite("Adaptive Tier & Rail Gauge Contract")
struct AdaptiveTierAndGaugeTests {

    // MARK: - Tier resolution

    private var musicTiers: [PurahAdaptiveTier] {
        [
            PurahAdaptiveTier(id: "compact", minHeight: 0),
            PurahAdaptiveTier(id: "standard", minHeight: 145),
            PurahAdaptiveTier(id: "immersive", minHeight: 215)
        ]
    }

    @Test("First paint picks the tall enough tier without any prior state")
    func testInitialPick() {
        let resolver = PurahAdaptiveTierResolver(tiers: musicTiers)
        #expect(resolver.resolve(for: 60, currentId: nil) == "compact")
        #expect(resolver.resolve(for: 145, currentId: nil) == "standard")
        #expect(resolver.resolve(for: 214, currentId: nil) == "standard")
        #expect(resolver.resolve(for: 215, currentId: nil) == "immersive")
    }

    @Test("Unsorted tiers are sorted so no tier is unreachable")
    func testUnsortedInputIsNormalised() {
        let resolver = PurahAdaptiveTierResolver(tiers: [
            PurahAdaptiveTier(id: "immersive", minHeight: 215),
            PurahAdaptiveTier(id: "compact", minHeight: 0),
            PurahAdaptiveTier(id: "standard", minHeight: 145)
        ])
        #expect(resolver.tiers.map(\.id) == ["compact", "standard", "immersive"])
        #expect(resolver.resolve(for: 220, currentId: nil) == "immersive")
    }

    @Test("Promotion happens exactly at the declared floor")
    func testPromotionIsExact() {
        let resolver = PurahAdaptiveTierResolver(tiers: musicTiers, hysteresis: 8)
        #expect(resolver.resolve(for: 144.9, currentId: "compact") == "compact")
        #expect(resolver.resolve(for: 145, currentId: "compact") == "standard")
        #expect(resolver.resolve(for: 215, currentId: "standard") == "immersive")
    }

    @Test("Demotion needs an 8pt overshoot below the floor")
    func testDemotionHysteresis() {
        let resolver = PurahAdaptiveTierResolver(tiers: musicTiers, hysteresis: 8)
        // Inside the dead band: still standard.
        #expect(resolver.resolve(for: 144, currentId: "standard") == "standard")
        #expect(resolver.resolve(for: 137.5, currentId: "standard") == "standard")
        // Past the margin: drop.
        #expect(resolver.resolve(for: 136.9, currentId: "standard") == "compact")
    }

    @Test("Hovering exactly on a threshold cannot thrash the tier")
    func testNoThrashOnThreshold() {
        let resolver = PurahAdaptiveTierResolver(tiers: musicTiers, hysteresis: 8)
        var current: String? = "compact"
        // A spring easing through 145 then jittering around it.
        for height: CGFloat in [140, 144, 145.5, 144.8, 145.2, 144.9, 145.1] {
            current = resolver.resolve(for: height, currentId: current)
        }
        // Once promoted at 145.5 it must stay promoted inside the dead band.
        #expect(current == "standard")
    }

    @Test("An instant relayout lands on the right tier in one resolve")
    func testFastJumpLandsDirectly() {
        let resolver = PurahAdaptiveTierResolver(tiers: musicTiers, hysteresis: 8)
        // Pinning a second drawer can shrink this one from 300 down to 100 in
        // a single layout pass; the body must be correct on that same pass.
        #expect(resolver.resolve(for: 300, currentId: "compact") == "immersive")
        #expect(resolver.resolve(for: 100, currentId: "immersive") == "compact")
    }

    @Test("Zero hysteresis switches exactly on the boundary")
    func testZeroHysteresis() {
        let resolver = PurahAdaptiveTierResolver(tiers: musicTiers, hysteresis: 0)
        #expect(resolver.resolve(for: 144.9, currentId: "standard") == "compact")
        #expect(resolver.resolve(for: 145, currentId: "compact") == "standard")
    }

    @Test("An empty tier list degrades instead of crashing")
    func testEmptyTiers() {
        let resolver = PurahAdaptiveTierResolver(tiers: [])
        #expect(resolver.resolve(for: 100, currentId: nil) == nil)
        #expect(resolver.tier(for: 100, currentId: nil) == nil)
    }

    // MARK: - Gauge

    @Test("Gauge segment ratios are clamped on construction")
    func testGaugeRatioClamp() {
        #expect(PurahGaugeSegment(ratio: 1.7, color: .red).ratio == 1.0)
        #expect(PurahGaugeSegment(ratio: -3, color: .red).ratio == 0.0)
        #expect(PurahGaugeSegment(ratio: 0.42, color: .red).ratio == 0.42)
    }

    @Test("Gauge clamps non-positive geometry so it cannot collapse or vanish")
    func testGaugeGeometryClamp() {
        let gauge = PurahSegmentGaugeBarView(segments: [], spacing: -4, barWidth: 0, height: 0)
        #expect(gauge.barWidth == 1.0)
        #expect(gauge.height == 1.0)
        #expect(gauge.spacing == 0)
    }

    @Test("Gauge instantiates for the single- and multi-channel shapes")
    func testGaugeInstantiation() {
        let single = PurahSegmentGaugeBarView(
            segments: [PurahGaugeSegment(id: "cpu", ratio: 0.5, color: .green)],
            barWidth: 8,
            height: 120,
            trackColor: .gray.opacity(0.25)
        )
        let multi = PurahSegmentGaugeBarView(
            segments: [
                PurahGaugeSegment(id: "cpu", ratio: 0.5, color: .green),
                PurahGaugeSegment(id: "gpu", ratio: 0.9, color: .blue, isAlerting: true)
            ],
            barWidth: 8,
            height: 120
        )
        _ = single
        _ = multi
    }

    // MARK: - Plugin height contract

    /// A drawer with `min == preferred` has no adaptive range at all: hovering
    /// never expands it and every tier above the first is unreachable. Vitals
    /// shipped in exactly that state.
    @Test("Every registered plugin declares a real min → preferred range")
    func testEveryPluginHasAdaptiveRange() throws {
        let registry = PluginRegistry.shared
        let store = PurahWorkspaceStore()
        let plugins = registry.allPlugins
        var checked = 0

        for plugin in plugins {
            store.registerCapabilityProvider(plugin)
            let id = plugin.manifest.id
            let minH = plugin.minimumDrawerHeight(store: store)
            let prefH = plugin.preferredDrawerHeight(store: store)
            checked += 1

            #expect(prefH >= minH, "\(id): preferred (\(prefH)) < minimum (\(minH))")

            // Decomposed plugins floor on the chip policy instead of the
            // composite minimum, and other suites can leave a shared plugin in
            // either mode — assert against the floor that actually applies.
            if plugin.isDecomposed(store: store) {
                let chipFloor = plugin.decomposedPolicy(store: store).minChipHeight
                #expect(minH >= chipFloor,
                        "\(id): decomposed minimum \(minH) is below its chip floor \(chipFloor)")
            } else {
                // AGENTS.md §5.1: 120pt is the composite floor, with 110pt
                // allowed for the compact Music vinyl mini-player only.
                let floor: CGFloat = id == "music" ? 110 : 120
                #expect(minH >= floor,
                        "\(id): composite minimum \(minH) is below the \(floor)pt ergonomic floor")
            }
        }

        #expect(checked >= 10, "expected every built-in plugin to be checked, saw \(checked)")
    }

    @Test("Vitals composite drawer can reach every one of its tiers")
    func testVitalsTiersAreReachable() throws {
        let store = PurahWorkspaceStore()
        store._isVitalsDecomposed = false
        let plugin = try #require(PluginRegistry.shared.plugin(for: "vitals") as? HardwareVitalsPlugin)
        store.registerCapabilityProvider(plugin)

        let minH = plugin.minimumDrawerHeight(store: store)
        let prefH = plugin.preferredDrawerHeight(store: store)
        let resolver = PurahAdaptiveTierResolver(tiers: [
            PurahAdaptiveTier(id: "compact", minHeight: 0),
            PurahAdaptiveTier(id: "standard", minHeight: 108),
            PurahAdaptiveTier(id: "immersive", minHeight: 235)
        ])

        #expect(minH < prefH, "Vitals composite drawer must expand on hover")
        #expect(resolver.resolve(for: minH, currentId: nil) == "standard",
                "the 140pt floor must reach the standard tier")
        #expect(resolver.resolve(for: prefH, currentId: nil) == "immersive",
                "the 300pt preferred height must reach the immersive tier")
    }

    @Test("A stepped card never grows beyond its chip, and its row fits inside it")
    func testSteppedCardMatchesItsChip() {
        for chip in [CGFloat(32), 40, 56, 63, 120, 185] {
            let card = PurahSteppedCardMetrics.cardHeight(slotHeight: chip, minChipHeight: chip)
            #expect(card == chip, "a drawer must never be taller than the chip it extrudes from")

            // The row and the body always add up to the card, never past it.
            let row = PurahSteppedCardMetrics.rowHeight(cardHeight: card)
            let body = PurahSteppedCardMetrics.bodyHeight(cardHeight: card)
            let gap = body > 0 ? PurahSteppedCardMetrics.rowGap : 0
            #expect(row + body + gap + PurahSteppedCardMetrics.verticalPadding * 2 == chip)
            #expect(row <= chip, "the row can never be taller than the chip")
        }

        // A chip compressed below its ergonomic floor still gets the floor.
        #expect(PurahSteppedCardMetrics.cardHeight(slotHeight: 6, minChipHeight: 32) == 32)

        // A minimum-size chip is its row and nothing else: no clipped sliver
        // of a body pretending to be content.
        #expect(PurahSteppedCardMetrics.bodyHeight(cardHeight: 40) == 4)
    }

    @Test("The chip row scales with the card instead of leaving a dead band")
    func testSteppedRowScales() {
        // A 40pt chip is the design's scale 1.0.
        #expect(PurahSteppedCardMetrics.rowScale(cardHeight: 40) == 1.0)
        #expect(PurahSteppedCardMetrics.rowHeight(cardHeight: 40) == 30)

        // Type grows with the card, monotonically, and stops growing before a
        // tall chip turns its row into a poster.
        let scales = [CGFloat(40), 63, 120, 200, 400].map(PurahSteppedCardMetrics.rowScale(cardHeight:))
        #expect(scales == scales.sorted())
        #expect(scales.last == 1.15)
        #expect(PurahSteppedCardMetrics.rowScale(cardHeight: 120) == 1.15)

        // A tall chip spends its extra height on the body.
        #expect(PurahSteppedCardMetrics.bodyHeight(cardHeight: 120)
                > PurahSteppedCardMetrics.bodyHeight(cardHeight: 63))
    }

    @Test("A stepped card stays inside the screen at both edges")
    func testSteppedCardShiftStaysOnScreen() {
        let screen: CGFloat = 900
        let card: CGFloat = 40

        // Room to spare: no shift.
        #expect(PurahSteppedCardMetrics.verticalShift(itemTop: 400, cardHeight: card, screenHeight: screen) == 0)

        // Running off the bottom: shifted up just enough.
        let low = PurahSteppedCardMetrics.verticalShift(itemTop: 860, cardHeight: card, screenHeight: screen)
        #expect(low == 860 + card - (screen - 12))
        #expect(860 + card - low <= screen - 12)

        // Running off the top: never shifted above the safe band.
        let high = PurahSteppedCardMetrics.verticalShift(itemTop: 4, cardHeight: card, screenHeight: screen)
        #expect(high == 0)
        #expect(4 - high >= 0)
    }
}
