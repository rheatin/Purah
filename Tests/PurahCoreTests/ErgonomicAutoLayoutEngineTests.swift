// Tests/PurahCoreTests/ErgonomicAutoLayoutEngineTests.swift
import Testing
@testable import PurahCore

@Suite("Ergonomic Auto-Layout Engine Tests")
struct ErgonomicAutoLayoutEngineTests {
    @Test("Calculates proportional distribution within safe bounds without overlap")
    func testProportionalDistribution() throws {
        let cal = SlotPod(
            id: "cal", name: "Calendar", systemIcon: "calendar", edge: .right,
            range: .init(start: 0, length: 0.1), ambientStyle: .progressTimeline,
            preferredZone: .goldenAction, ergonomicWeight: 40
        )
        let todo = SlotPod(
            id: "todo", name: "Todo", systemIcon: "checklist", edge: .right,
            range: .init(start: 0, length: 0.1), ambientStyle: .segmentGauge,
            preferredZone: .goldenAction, ergonomicWeight: 30
        )
        let music = SlotPod(
            id: "music", name: "Music", systemIcon: "music.note", edge: .right,
            range: .init(start: 0, length: 0.1), ambientStyle: .waveLevelMeter,
            preferredZone: .goldenAction, ergonomicWeight: 30
        )

        let safeBounds = 0.15...0.85
        let result = ErgonomicAutoLayoutEngine.layout(
            pods: [cal, todo, music],
            on: .right,
            safeBounds: safeBounds,
            gap: 0.02
        )

        #expect(result.count == 3)
        // Verify pods reside within safe bounds
        let firstPod = try #require(result.first)
        let lastPod = try #require(result.last)
        #expect(firstPod.range.start >= safeBounds.lowerBound)
        #expect(lastPod.range.end <= safeBounds.upperBound)

        // Verify zero-overlap invariant
        for i in 0..<(result.count - 1) {
            #expect(result[i].range.end <= result[i + 1].range.start)
        }
    }

    @Test("Sorts pods based on ergonomic zone hierarchy (Glance -> Action -> Flick)")
    func testZoneSorting() {
        let flick = SlotPod(
            id: "flick", name: "Music", systemIcon: "music.note", edge: .left,
            range: .init(start: 0, length: 0.1), ambientStyle: .waveLevelMeter,
            preferredZone: .quickFlick, ergonomicWeight: 20
        )
        let glance = SlotPod(
            id: "glance", name: "Clock", systemIcon: "clock", edge: .left,
            range: .init(start: 0, length: 0.1), ambientStyle: .ghostDot,
            preferredZone: .glance, ergonomicWeight: 20
        )
        let action = SlotPod(
            id: "action", name: "Shelf", systemIcon: "tray", edge: .left,
            range: .init(start: 0, length: 0.1), ambientStyle: .ghostDot,
            preferredZone: .goldenAction, ergonomicWeight: 40
        )

        let result = ErgonomicAutoLayoutEngine.layout(
            pods: [flick, glance, action],
            on: .left
        )

        #expect(result[0].id == "glance")
        #expect(result[1].id == "action")
        #expect(result[2].id == "flick")
    }

    @Test("Optimizes bilateral layout respecting user edge assignments by default")
    func testOptimizeBilateralLayoutPreservesUserEdges() {
        let vitals = SlotPod(
            id: "vitals", name: "Vitals", systemIcon: "waveform", edge: .right, defaultEdge: .left,
            range: .init(start: 0.1, length: 0.1), ambientStyle: .ghostDot,
            preferredZone: .quickFlick, ergonomicWeight: 30, isEnabled: true
        )
        let calendar = SlotPod(
            id: "calendar", name: "Calendar", systemIcon: "calendar", edge: .left, defaultEdge: .right,
            range: .init(start: 0.1, length: 0.1), ambientStyle: .progressTimeline,
            preferredZone: .glance, ergonomicWeight: 40, isEnabled: true
        )
        let disabledMusic = SlotPod(
            id: "music", name: "Music", systemIcon: "music.note", edge: .left,
            range: .init(start: 0.1, length: 0.1), ambientStyle: .waveLevelMeter,
            preferredZone: .quickFlick, ergonomicWeight: 20, isEnabled: false
        )

        // Default reassignEdges = false: user-assigned edges are 100% strictly respected!
        let userAssigned = ErgonomicAutoLayoutEngine.optimizeBilateralLayout(pods: [vitals, calendar, disabledMusic], reassignEdges: false)

        let userVitals = userAssigned.first(where: { $0.id == "vitals" })
        let userCal = userAssigned.first(where: { $0.id == "calendar" })
        let userMusic = userAssigned.first(where: { $0.id == "music" })

        #expect(userVitals?.edge == .right) // Vitals can be on the right!
        #expect(userCal?.edge == .left) // Calendar can be on the left!
        #expect(userMusic?.isEnabled == false)

        // Explicit reassignEdges = true: resets to default ergonomic partitions
        let repartitioned = ErgonomicAutoLayoutEngine.optimizeBilateralLayout(pods: [vitals, calendar, disabledMusic], reassignEdges: true)

        let optVitals = repartitioned.first(where: { $0.id == "vitals" })
        let optCal = repartitioned.first(where: { $0.id == "calendar" })

        #expect(optVitals?.edge == .left)
        #expect(optCal?.edge == .right)
    }
}
