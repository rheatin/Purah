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
        // 验证位于安全区间内
        let firstPod = try #require(result.first)
        let lastPod = try #require(result.last)
        #expect(firstPod.range.start >= safeBounds.lowerBound)
        #expect(lastPod.range.end <= safeBounds.upperBound)

        // 验证绝不重叠 (No Overlap Guarantee)
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
}
