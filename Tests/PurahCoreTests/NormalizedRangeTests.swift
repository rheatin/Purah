// Tests/PurahCoreTests/NormalizedRangeTests.swift
import Testing
@testable import PurahCore

@Suite("NormalizedRange Tests")
struct NormalizedRangeTests {
    @Test("Valid range clamping and geometry calculations")
    func testRangeGeometry() {
        let range = NormalizedRange(start: 0.20, length: 0.30)
        #expect(range.start == 0.20)
        #expect(range.length == 0.30)
        #expect(range.end == 0.50)
        #expect(range.center == 0.35)
        #expect(range.contains(0.25))
        #expect(!range.contains(0.55))
    }

    @Test("Overlap detection between ranges")
    func testRangeOverlap() {
        let r1 = NormalizedRange(start: 0.10, length: 0.20) // 0.10 ~ 0.30
        let r2 = NormalizedRange(start: 0.25, length: 0.15) // 0.25 ~ 0.40
        let r3 = NormalizedRange(start: 0.35, length: 0.20) // 0.35 ~ 0.55

        #expect(r1.overlaps(with: r2))
        #expect(r2.overlaps(with: r3))
        #expect(!r1.overlaps(with: r3))
    }

    @Test("Zone mapping based on vertical coordinate")
    func testZoneClassification() {
        #expect(ZoneType.zone(for: 0.10) == .glance)
        #expect(ZoneType.zone(for: 0.45) == .goldenAction)
        #expect(ZoneType.zone(for: 0.85) == .quickFlick)
    }
}
