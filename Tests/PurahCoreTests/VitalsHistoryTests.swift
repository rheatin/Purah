import Foundation
import Testing
@testable import PurahCore

@Suite("Vitals tiered history")
struct VitalsHistoryTests {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    private func point(_ offset: TimeInterval, _ value: Double) -> VitalsHistoryPoint {
        VitalsHistoryPoint(timestamp: base.addingTimeInterval(offset), value: value)
    }

    @Test("Sixty one-second samples become one minute mean at the boundary")
    func minuteBucketClosesAtBoundary() {
        var buffer = VitalsHistoryBuffer()
        for index in 0..<60 {
            buffer.append(point(TimeInterval(index), 1.0))
        }
        buffer.append(point(60, 9.0))

        #expect(buffer.tiers.minute.count == 1)
        #expect(buffer.tiers.minute.first?.timestamp == base)
        #expect(buffer.tiers.minute.first?.value == 1.0)
    }

    @Test("A minute with 61 samples does not double-count the boundary sample")
    func sixtyOneSamplesStayOneBucket() {
        var buffer = VitalsHistoryBuffer()
        for index in 0..<60 {
            buffer.append(point(TimeInterval(index), 1.0))
        }
        buffer.append(point(30.5, 1.0))
        buffer.append(point(60, 7.0))

        #expect(buffer.tiers.minute.count == 1)
        #expect(buffer.tiers.minute.first?.value == 1.0)
    }

    @Test("An hour of history yields sixty minute buckets")
    func hourColumns() {
        var buffer = VitalsHistoryBuffer()
        for index in 0...3600 {
            buffer.append(point(TimeInterval(index), 1.0))
        }

        let buckets = VitalsHistoryBuffer.columns(
            tiers: buffer.tiers,
            scope: .hour1,
            now: base.addingTimeInterval(3600)
        )
        #expect(buckets.count == 60)
        #expect(buckets.allSatisfy { abs($0.mean - 1.0) < 0.0001 })
        #expect(buckets.last?.end == base.addingTimeInterval(3600))
    }

    @Test("Ten minutes under twelve hours draws ten one-minute columns")
    func shortHistoryWidensTwelveHourSlots() {
        var buffer = VitalsHistoryBuffer()
        for index in 0...600 {
            buffer.append(point(TimeInterval(index), 1.0))
        }

        let now = base.addingTimeInterval(600)
        let buckets = VitalsHistoryBuffer.columns(
            tiers: buffer.tiers,
            scope: .hours12,
            now: now
        )
        #expect(buckets.count == 10)
        #expect(buckets.first?.start == now.addingTimeInterval(-600))
        #expect(buckets.allSatisfy { $0.mean > 0.99 })
        #expect(buckets.last?.end == now)
        #expect(abs(buckets[1].end.timeIntervalSince(buckets[1].start) - 60) < 0.001)
    }

    @Test("Twenty minutes under an hour draws twenty one-minute columns")
    func shortHistoryWidensHourBuckets() {
        var buffer = VitalsHistoryBuffer()
        for index in 0...1200 {
            buffer.append(point(TimeInterval(index), 1.0))
        }

        let now = base.addingTimeInterval(1200)
        let buckets = VitalsHistoryBuffer.columns(
            tiers: buffer.tiers,
            scope: .hour1,
            now: now
        )
        #expect(buckets.count == 20)
        #expect(buckets.first?.start == now.addingTimeInterval(-1200))
        #expect(buckets.last?.end == now)
        let width = buckets[1].end.timeIntervalSince(buckets[1].start)
        #expect(abs(width - 60) < 0.001)
    }

    @Test("An empty series produces no buckets")
    func emptySeriesHasNoColumns() {
        let buckets = VitalsHistoryBuffer.columns(
            tiers: VitalsTieredHistory(),
            scope: .hour1
        )
        #expect(buckets.isEmpty)
    }

    @Test("Sparse samples widen their slots to the cadence and stay equal")
    func sparseSamplesKeepEqualSlots() throws {
        let now = base.addingTimeInterval(30)
        let dense = (0...30).map { point(TimeInterval($0), 1.0) }
        let sparse = stride(from: 0, through: 30, by: 5).map {
            point(TimeInterval($0), 1.0)
        }

        let denseBuckets = VitalsHistoryBuffer.columns(
            fast: dense,
            scope: .realTime30s,
            now: now
        )
        let sparseBuckets = VitalsHistoryBuffer.columns(
            fast: sparse,
            scope: .realTime30s,
            now: now
        )

        #expect(denseBuckets.count == 30)
        #expect(sparseBuckets.count == 6)
        let firstWidth = try #require(sparseBuckets.first).end.timeIntervalSince(
            sparseBuckets[0].start
        )
        #expect(abs(firstWidth - 5) < 0.0001)
        #expect(sparseBuckets.allSatisfy {
            abs($0.end.timeIntervalSince($0.start) - firstWidth) < 0.0001
        })
        #expect(denseBuckets.allSatisfy { abs($0.mean - 1) < 0.0001 })
        #expect(sparseBuckets.allSatisfy { abs($0.mean - 1) < 0.0001 })
    }

    @Test("Fast-tier capacity follows the sampling interval, not the range")
    func fastCapacityTracksSamplingInterval() {
        #expect(VitalsHistoryBuffer.fastCapacity(forInterval: 1) == 300)
        #expect(VitalsHistoryBuffer.fastCapacity(forInterval: 2) == 150)
        #expect(VitalsHistoryBuffer.fastCapacity(forInterval: 5) == 60)
    }

    @Test("A five-second sampler draws six five-second columns")
    func slowSamplerShowsFewerColumns() {
        let now = base.addingTimeInterval(30)
        let points = stride(from: 0, through: 30, by: 5).map {
            point(TimeInterval($0), 1)
        }

        let buckets = VitalsHistoryBuffer.columns(
            fast: points,
            scope: .realTime30s,
            now: now,
            fastResolution: 5
        )

        #expect(buckets.count == 6)
        #expect(buckets.allSatisfy { abs($0.mean - 1) < 0.0001 })
        let width = buckets[1].end.timeIntervalSince(buckets[1].start)
        #expect(abs(width - 5) < 0.0001)
        #expect(buckets.allSatisfy {
            abs($0.end.timeIntervalSince($0.start) - width) < 0.0001
        })
    }

    @Test("Slot count follows cadence and every slot carries a sample")
    func slotsFollowCadence() {
        let oneSecond = (0...30).map { point(TimeInterval($0), 1.0) }
        let thirtySeconds = VitalsHistoryBuffer.columns(
            fast: oneSecond,
            scope: .realTime30s,
            now: base.addingTimeInterval(30)
        )
        #expect(thirtySeconds.count == 30)
        #expect(thirtySeconds.allSatisfy { $0.mean > 0 })

        let fiveSeconds = stride(from: 0, through: 30, by: 5).map {
            point(TimeInterval($0), 1.0)
        }
        let sparseThirtySeconds = VitalsHistoryBuffer.columns(
            fast: fiveSeconds,
            scope: .realTime30s,
            now: base.addingTimeInterval(30)
        )
        #expect(sparseThirtySeconds.count == 6)
        #expect(sparseThirtySeconds.allSatisfy { $0.mean > 0 })

        let minutes = (0...20).map { point(TimeInterval($0) * 60, 1.0) }
        let twentyMinutes = VitalsHistoryBuffer.columns(
            tiers: VitalsTieredHistory(minute: minutes),
            scope: .hour1,
            now: base.addingTimeInterval(1200)
        )
        #expect(twentyMinutes.count == 20)
        #expect(twentyMinutes.allSatisfy { $0.mean > 0 })
        #expect(abs(twentyMinutes[1].end.timeIntervalSince(twentyMinutes[1].start) - 60) < 0.001)

        let fiveMinutesOfSamples = (0...300).map { point(TimeInterval($0), 1.0) }
        let fiveMinutes = VitalsHistoryBuffer.columns(
            fast: fiveMinutesOfSamples,
            scope: .minutes5,
            now: base.addingTimeInterval(300)
        )
        #expect(fiveMinutes.count == 60)
        #expect(fiveMinutes.allSatisfy { $0.mean > 0 })

        let coarse = (0..<60).map { point(TimeInterval($0) * 720, 1.0) }
        let twelveHours = VitalsHistoryBuffer.columns(
            tiers: VitalsTieredHistory(coarse: coarse),
            scope: .hours12,
            now: base.addingTimeInterval(43_200)
        )
        #expect(twelveHours.count == 60)
        #expect(twelveHours.allSatisfy { $0.mean > 0 })
        #expect(abs(twelveHours[1].end.timeIntervalSince(twelveHours[1].start) - 720) < 0.001)
    }

    @Test("The Overview bar budget caps twelve-hour coarse history at thirty")
    func overviewBarBudgetCapsCoarseHistory() {
        let coarse = (0..<60).map { point(TimeInterval($0) * 720, 1.0) }
        let now = base.addingTimeInterval(43_200)
        let tiers = VitalsTieredHistory(coarse: coarse)

        let limited = VitalsHistoryBuffer.columns(
            tiers: tiers,
            scope: .hours12,
            now: now,
            maximumColumns: 30
        )
        #expect(limited.count == 30)
        #expect(limited.first?.start == now.addingTimeInterval(-43_200))
        #expect(limited.last?.end == now)
        #expect(limited.allSatisfy { $0.mean > 0.99 })
        let width = limited[1].end.timeIntervalSince(limited[1].start)
        #expect(abs(width - 1_440) < 0.001)

        let unbounded = VitalsHistoryBuffer.columns(
            tiers: tiers,
            scope: .hours12,
            now: now
        )
        #expect(unbounded.count == 60)
    }

    @Test("Fast-tier capacity is a ceiling over the coverage window, not a rule")
    func changingCadenceKeepsFastCoverage() throws {
        // A slow sampler's history is older than the fast tier's contract and
        // must not survive a switch to a faster cadence's larger capacity.
        var slow = VitalsHistoryBuffer(maximumFastSamples: 300)
        for index in 0...1_200 {
            slow.append(point(TimeInterval(index) * 5, 1))
        }
        slow.setFastCapacity(300, now: base.addingTimeInterval(6_000))
        // The ceiling is 300 points; the five-minute coverage window removes
        // the older samples first, leaving the boundary point plus 60.
        #expect(slow.tiers.fast.count == 61)
        let slowCoverage = base.addingTimeInterval(6_000)
            .timeIntervalSince(try #require(slow.tiers.fast.first).timestamp)
        #expect(slowCoverage <= VitalsHistoryBuffer.fastCoverage)
        #expect(slowCoverage > 290)

        // Five-second samples at the sixty-point ceiling still describe the
        // full five-minute contract.
        var fast = VitalsHistoryBuffer(maximumFastSamples: 300)
        for index in 0..<120 {
            fast.append(point(TimeInterval(index) * 5, 1))
        }
        fast.setFastCapacity(VitalsHistoryBuffer.fastCapacity(forInterval: 5),
                             now: base.addingTimeInterval(600))
        #expect(fast.tiers.fast.count == 60)
        let covered = base.addingTimeInterval(600)
            .timeIntervalSince(try #require(fast.tiers.fast.first).timestamp)
        #expect(covered >= VitalsHistoryBuffer.fastCoverage)
    }

    @Test("A version-2 ratio history migrates to bytes per second")
    func v2ThroughputMigratesToBytes() throws {
        let legacy = VitalsPersistedHistory(
            version: 2,
            cpu: VitalsTieredHistory(fast: [point(0, 0.42)]),
            networkDown: VitalsTieredHistory(
                fast: [point(0, 1.0)],
                minute: [point(0, 0.5)],
                coarse: [point(0, 0.25)]
            ),
            networkUp: VitalsTieredHistory(fast: [point(0, 0.1)]),
            diskRead: VitalsTieredHistory(fast: [point(0, 0.2)]),
            diskWrite: VitalsTieredHistory(fast: [point(0, 0.3)])
        )
        let decoded = try JSONDecoder().decode(
            VitalsPersistedHistory.self,
            from: JSONEncoder().encode(legacy)
        )

        #expect(decoded.version == 2)
        #expect(decoded.networkDown.fast.first?.value == 10_485_760)
        #expect(decoded.networkDown.minute.first?.value == 5_242_880)
        #expect(decoded.networkDown.coarse.first?.value == 2_621_440)
        #expect(decoded.networkUp.fast.first?.value == 1_048_576)
        #expect(decoded.diskRead.fast.first?.value == 2_097_152)
        #expect(decoded.diskWrite.fast.first?.value == 3_145_728)
        #expect(decoded.cpu.fast.first?.value == 0.42)
    }

    @Test("A version-3 file keeps its raw throughput values")
    func v3ThroughputRoundTrips() throws {
        let value = 52_428_800.0
        let history = VitalsPersistedHistory(
            networkDown: VitalsTieredHistory(fast: [point(0, value)])
        )
        let decoded = try JSONDecoder().decode(
            VitalsPersistedHistory.self,
            from: JSONEncoder().encode(history)
        )
        #expect(decoded.version == VitalsPersistedHistory.currentVersion)
        #expect(decoded.networkDown.fast.first?.value == value)
    }

    @Test("A persisted pending bucket is completed exactly once on reload")
    func pendingBucketSurvivesReload() throws {
        var buffer = VitalsHistoryBuffer()
        for index in 0..<30 {
            buffer.append(point(TimeInterval(index), 1.0))
        }
        let pending = try #require(buffer.pendingMinuteBucket)

        let container = VitalsPersistedHistory(
            cpu: buffer.tiers,
            pendingMinute: ["cpu": pending]
        )
        let decoded = try JSONDecoder().decode(
            VitalsPersistedHistory.self,
            from: JSONEncoder().encode(container)
        )
        var restored = VitalsHistoryBuffer(
            tiers: decoded.cpu,
            pendingMinute: decoded.pendingMinute?["cpu"]
        )
        restored.append(point(60, 3.0))

        let completed = restored.tiers.minute.filter { $0.timestamp == base }
        #expect(completed.count == 1)
        #expect(completed.first?.value == 1.0)
    }

    @Test("A pending bucket older than the newest completed one is dropped")
    func stalePendingBucketIsDropped() {
        let buffer = VitalsHistoryBuffer(
            tiers: VitalsTieredHistory(minute: [point(120, 1)]),
            pendingMinute: VitalsPendingBucket(start: base, sum: 5, count: 1)
        )
        #expect(buffer.pendingMinuteBucket == nil)
    }

    @Test("A v1 single-array payload loads into the fast tier")
    func legacyPayloadLoadsIntoFastTier() throws {
        let legacy = ["cpu": [point(0, 0.25), point(1, 0.5)]]
        let data = try JSONEncoder().encode(legacy)
        let decoded = try JSONDecoder().decode(VitalsPersistedHistory.self, from: data)

        #expect(decoded.version == 1)
        #expect(decoded.cpu.fast.count == 2)
        #expect(decoded.cpu.fast.last?.value == 0.5)
        #expect(decoded.cpu.minute.isEmpty)
        #expect(decoded.cpu.coarse.isEmpty)
    }

    @Test("A malformed payload fails to decode instead of inventing history")
    func malformedPayloadThrows() {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(
                VitalsPersistedHistory.self,
                from: Data("{\"cpu\": 7}".utf8)
            )
        }
    }

    @Test("Battery cells keep ten-minute width and put the live state in the current bucket")
    func batteryStateCellsFillTheRange() {
        var history = VitalsStateHistory()
        for index in 0..<5 {
            history.appendCompleted(
                start: base.addingTimeInterval(Double(index - 5) * 600),
                state: index % 3
            )
        }

        let cells = history.cells(
            range: 3600,
            now: base,
            currentState: 2
        )
        #expect(cells.count == 6)
        #expect(cells.first?.start == base.addingTimeInterval(-3000))
        #expect(cells.last?.start == base)
        #expect(cells.last?.state == 2)
        #expect(cells.first?.state == 0)
        #expect(cells.allSatisfy { $0.end.timeIntervalSince($0.start) == 600 })

        let short = history.cells(
            range: 1200,
            now: base,
            currentState: 1
        )
        #expect(short.count == 2)
        #expect(short.last?.state == 1)
    }
}
