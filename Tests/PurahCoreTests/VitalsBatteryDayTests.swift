import Foundation
import SwiftUI
import Testing
@testable import PurahCore
@testable import PurahUI

@Suite("Vitals battery day")
@MainActor
struct VitalsBatteryDayTests {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    private func bucket(_ offset: TimeInterval, width: TimeInterval = 600) -> VitalsBucket {
        let start = base.addingTimeInterval(offset)
        return VitalsBucket(start: start, end: start.addingTimeInterval(width), mean: 0.5)
    }

    private func statePoint(_ offset: TimeInterval, _ state: Int) -> VitalsHistoryPoint {
        VitalsHistoryPoint(timestamp: base.addingTimeInterval(offset), value: Double(state))
    }

    @Test("A state change between buckets applies at the next bucket start")
    func stateJoinFollowsBucketStarts() {
        let buckets = (0..<6).map { bucket(TimeInterval($0) * 600) }
        let points = [
            statePoint(0, 1),
            statePoint(900, 2),
            statePoint(1_500, 0),
            statePoint(2_700, 1)
        ]

        #expect(
            VitalsStateHistory.stateValues(for: buckets, points: points)
                == [1, 1, 2, 0, 0, 1]
        )
    }

    @Test("A gap longer than one state interval carries the last state forward")
    func stateJoinCarriesAcrossGap() {
        let buckets = (0..<5).map { bucket(TimeInterval($0) * 600) }
        let points = [
            statePoint(0, 1),
            statePoint(2_400, 0)
        ]

        #expect(
            VitalsStateHistory.stateValues(for: buckets, points: points)
                == [1, 1, 1, 1, 0]
        )
    }

    @Test("Buckets older than the state history have no claimed state")
    func stateJoinLeavesOlderBucketsUnknown() {
        let buckets = [bucket(-1_200), bucket(-600)]
        let points = [statePoint(0, 1)]

        #expect(
            VitalsStateHistory.stateValues(for: buckets, points: points)
                == [nil, nil]
        )
    }

    @Test("Ribbon readout uses the full cell span and its localized state")
    func ribbonReadoutFormatsFullAndOldestCells() {
        let oldest = VitalsStateCell(
            start: localDate(hour: 9, minute: 30),
            end: localDate(hour: 9, minute: 40),
            state: 2
        )
        let newest = VitalsStateCell(
            start: localDate(hour: 9, minute: 40),
            end: localDate(hour: 9, minute: 50),
            state: 1
        )
        let cells = [oldest, newest]

        #expect(
            VitalsColumnFormatting.batteryRibbonReadout(cells: cells, index: 0)
                == "09:30 – 09:40 · \("vitals.power.fullyCharged".localized)"
        )
        #expect(
            VitalsColumnFormatting.batteryRibbonReadout(cells: cells, index: 1)
                == "09:40 – 09:50 · \("vitals.power.charging".localized)"
        )
        #expect(VitalsColumnFormatting.batteryRibbonReadout(cells: cells, index: 2) == nil)
        #expect(VitalsColumnFormatting.batteryRibbonReadout(cells: cells, index: -1) == nil)
    }

    @Test("Per-bucket colours win and a nil override keeps the alert palette")
    func bucketColorsWinOverMetricAlerts() {
        let custom = Color(red: 0.11, green: 0.22, blue: 0.33)
        let thresholds = VitalsColorThresholds()
        let sample = [bucket(0, width: 1)]

        let overridden = VitalsColumnStrip(
            buckets: sample,
            domain: .percentage,
            tint: VitalsColorResolver.cpuIdentity,
            bucketColors: [custom],
            metric: .cpu,
            thresholds: thresholds,
            hoveredIndex: .constant(nil)
        )
        #expect(overridden.color(for: 0.9, index: 0) == custom)

        let plain = VitalsColumnStrip(
            buckets: sample,
            domain: .percentage,
            tint: VitalsColorResolver.cpuIdentity,
            metric: .cpu,
            thresholds: thresholds,
            hoveredIndex: .constant(nil)
        )
        #expect(plain.color(for: 0.4, index: 0) == VitalsColorResolver.cpuIdentity)
        #expect(plain.color(for: 0.9, index: 0) == VitalsColorResolver.dangerRed)
    }

    private func localDate(hour: Int, minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 15,
            hour: hour,
            minute: minute
        )) ?? base
    }
}
