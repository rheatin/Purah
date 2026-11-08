import Foundation
import Testing
@testable import PurahCore
@testable import PurahUI

@Suite("Vitals column strip")
struct VitalsColumnLayoutTests {
    private func bucket(_ value: Double) -> VitalsBucket {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        return VitalsBucket(start: start, end: start.addingTimeInterval(1), mean: value)
    }

    @Test("Zero buckets produce no bar geometry")
    func zeroBucketsDrawNothing() {
        let bars = VitalsColumnStripLayout.bars(
            buckets: [bucket(0), bucket(0), bucket(0)],
            domain: .percentage,
            size: CGSize(width: 120, height: 40)
        )
        #expect(bars.isEmpty)
    }

    @Test("A non-zero bucket is a bottom-anchored column with a 1.5pt floor")
    func nonZeroBucketDrawsColumn() throws {
        let bars = VitalsColumnStripLayout.bars(
            buckets: [bucket(0.5), bucket(0.000_01)],
            domain: .percentage,
            size: CGSize(width: 100, height: 40)
        )
        #expect(bars.count == 2)
        let half = try #require(bars.first)
        #expect(abs(half.rect.height - 20) < 0.001)
        #expect(abs(half.rect.maxY - 40) < 0.001)
        let floor = try #require(bars.last)
        #expect(floor.rect.height == 1.5)
    }

    @Test("The percentage domain is the rail's fixed 0…1 scale")
    func percentageDomainIsFixed() {
        #expect(VitalsColumnDomain.percentage.height(for: 0) == 0)
        #expect(VitalsColumnDomain.percentage.height(for: 0.01) == 0.01)
        #expect(VitalsColumnDomain.percentage.height(for: 0.54) == 0.54)
        #expect(VitalsColumnDomain.percentage.height(for: 1.4) == 1)
    }

    @Test("The log domain is 1 KB/s to the shared nice-number ceiling")
    func logDomainMatchesThroughputDomain() {
        let lower = 1_024.0
        let ceilingBytes = VitalsThroughputDomain.ceiling(for: 1_048_576)
        let domain = VitalsColumnDomain.log(lower: lower, upper: ceilingBytes)

        #expect(abs(domain.height(for: 5_120) - 0.232_5) < 0.002)
        #expect(abs(domain.height(for: 1_048_576) - 1.0) < 0.0001)
        #expect(domain.height(for: 0) == 0)
    }

    @Test("Slot width comes from the grid, not the samples")
    func barsUseEqualSlotGeometry() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let buckets = (0..<60).map { index in
            let slotStart = start.addingTimeInterval(Double(index) * 0.5)
            return VitalsBucket(
                start: slotStart,
                end: slotStart.addingTimeInterval(0.5),
                mean: index.isMultiple(of: 5) ? 0.5 : 0
            )
        }

        let bars = VitalsColumnStripLayout.bars(
            buckets: buckets,
            domain: .percentage,
            size: CGSize(width: 240, height: 40)
        )

        #expect(bars.count == 12)
        let firstWidth = try #require(bars.first).rect.width
        #expect(bars.allSatisfy { abs($0.rect.width - firstWidth) < 0.0001 })
        for pair in zip(bars, bars.dropFirst()) {
            #expect(abs(pair.1.rect.minX - pair.0.rect.minX - 20.0) < 0.0001)
        }
    }

    @Test("Hovered detail keeps the range and follows the scope's time format")
    @MainActor
    func hoveredDetailUsesScopeTimeFormat() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let bucket = VitalsBucket(
            start: start,
            end: start.addingTimeInterval(30),
            mean: 0.5
        )

        for scope in [VitalsTimeScope.realTime30s, .minutes5] {
            let text = VitalsColumnFormatting.hoverDetail(
                for: bucket,
                scope: scope,
                rangeLabel: "30 sec"
            )
            let time = VitalsColumnFormatting.time(start, scope: scope)
            #expect(text == "\(time) · 30 sec")
            #expect(time.split(separator: ":").count == 3)
        }

        for scope in [VitalsTimeScope.hour1, .hours12] {
            let text = VitalsColumnFormatting.hoverDetail(
                for: bucket,
                scope: scope,
                rangeLabel: "1 hr"
            )
            let time = VitalsColumnFormatting.time(start, scope: scope)
            #expect(text == "\(time) · 1 hr")
            #expect(time.split(separator: ":").count == 2)
        }
    }
}
