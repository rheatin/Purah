// Tests/PurahCoreTests/ProcessNetworkSamplerTests.swift
import Testing
import Foundation
@testable import PurahCore

@Suite("Process Network Sampler")
struct ProcessNetworkSamplerTests {
    @Test("CSV parsing skips the header and preserves dotted process names")
    func parsesNettopCSV() {
        let output = """
        name.0,bytes_in,bytes_out,
        Safari.4242,1000,2000,
        com.example.Worker.77,300,400,
        Broken,10,20,
        Negative.-5,10,20,
        MissingColumns.88,10
        """

        let parsed = ProcessNetworkSampler.parse(output)

        #expect(parsed[4242] == ProcessNetworkByteCounts(bytesIn: 1_000, bytesOut: 2_000))
        #expect(parsed[77] == ProcessNetworkByteCounts(bytesIn: 300, bytesOut: 400))
        #expect(parsed.count == 2)
    }

    @Test("The first sample is a zero baseline and the second reports bytes per second")
    func derivesThroughputFromTwoSamples() async {
        let runner = ScriptedNetworkRunner(outputs: [
            "Safari.42,1000,500,\n",
            "Safari.42,3048,1524,\n"
        ])
        let clock = DateSequence([testDate(0), testDate(2)])
        let sampler = ProcessNetworkSampler(
            runner: { await runner.next() },
            clock: { clock.next() }
        )

        let first = await sampler.sample()
        #expect(first[42] == .zero)

        let second = await sampler.sample()
        #expect(second[42]?.downBytesPerSecond == 1_024)
        #expect(second[42]?.upBytesPerSecond == 512)
        #expect(await runner.callCount == 2)
    }

    @Test("Negative deltas clamp to zero and new or vanished pids do not reuse another process")
    func handlesCounterResetAndPIDChurn() async {
        let runner = ScriptedNetworkRunner(outputs: [
            "A.42,1000,1000,\n",
            "A.42,900,800,\nB.43,50,60,\n",
            "B.43,450,460,\n"
        ])
        let clock = DateSequence([testDate(0), testDate(2), testDate(4)])
        let sampler = ProcessNetworkSampler(
            runner: { await runner.next() },
            clock: { clock.next() }
        )

        _ = await sampler.sample()
        let second = await sampler.sample()
        #expect(second[42] == .zero)
        #expect(second[43] == .zero)

        let third = await sampler.sample()
        #expect(third[42] == nil)
        #expect(third[43]?.downBytesPerSecond == 200)
        #expect(third[43]?.upBytesPerSecond == 200)
    }

    @Test("A failed sample resets the baseline instead of carrying stale counters")
    func failedSampleResetsBaseline() async {
        let runner = ScriptedNetworkRunner(outputs: [
            "A.42,1000,1000,\n",
            nil,
            "A.42,2000,2000,\n"
        ])
        let clock = DateSequence([testDate(0), testDate(2), testDate(4)])
        let sampler = ProcessNetworkSampler(
            runner: { await runner.next() },
            clock: { clock.next() }
        )

        _ = await sampler.sample()
        let failed = await sampler.sample()
        #expect(failed.isEmpty)

        let restarted = await sampler.sample()
        #expect(restarted[42] == .zero)
    }

    @Test("Process inspector resource counters default to zero")
    func processMetricDefaultsAreZero() {
        let process = ProcessInfoItem(
            id: 42,
            name: "Worker",
            cpuPercent: 1,
            memoryPercent: 2
        )

        #expect(process.networkDownBytesPerSecond == 0)
        #expect(process.networkUpBytesPerSecond == 0)
        #expect(process.diskReadBytesPerSecond == 0)
        #expect(process.diskWriteBytesPerSecond == 0)
        #expect(process.energyWatts == 0)
    }

    @Test("Disk and energy counters diff against the same two-second baseline")
    func derivesDiskAndPowerRates() {
        let previous = ProcessResourceCounters(
            diskReadBytes: 1_000,
            diskWriteBytes: 2_000,
            energyNanojoules: 10_000_000_000
        )
        let current = ProcessResourceCounters(
            diskReadBytes: 6_000,
            diskWriteBytes: 3_000,
            energyNanojoules: 14_000_000_000
        )

        let rates = current.rates(since: previous, elapsed: 2)

        #expect(rates.diskReadBytesPerSecond == 2_500)
        #expect(rates.diskWriteBytesPerSecond == 500)
        #expect(rates.energyWatts == 2)
    }

    @Test("Counter resets never produce negative disk or energy rates")
    func resourceCounterResetClampsToZero() {
        let previous = ProcessResourceCounters(
            diskReadBytes: 10_000,
            diskWriteBytes: 10_000,
            energyNanojoules: 10_000
        )
        let current = ProcessResourceCounters(
            diskReadBytes: 5_000,
            diskWriteBytes: 4_000,
            energyNanojoules: 2_000
        )

        #expect(current.rates(since: previous, elapsed: 1) == .zero)
    }

    @Test("A socket owner already in the app set stays on its own row")
    func networkAttributionKeepsDirectAppOwner() {
        let owner = ProcessNetworkAttribution.resolveOwner(
            pid: 42,
            parentPIDs: [42: 1],
            appPIDs: [42]
        )

        #expect(owner == 42)
    }

    @Test("A two-level helper rolls up to its owning app")
    func networkAttributionWalksTwoLevels() {
        let owner = ProcessNetworkAttribution.resolveOwner(
            pid: 53496,
            parentPIDs: [53496: 53490, 53490: 53481, 53481: 1],
            appPIDs: [53481]
        )

        #expect(owner == 53481)
    }

    @Test("Sibling helpers contribute their throughput to one app row")
    func networkAttributionSumsSiblingHelpers() {
        let speeds: [Int32: ProcessNetworkSpeed] = [
            53496: ProcessNetworkSpeed(downBytesPerSecond: 8_000_000, upBytesPerSecond: 100_000),
            53497: ProcessNetworkSpeed(downBytesPerSecond: 2_000_000, upBytesPerSecond: 50_000)
        ]
        let attributed = ProcessNetworkAttribution.attribute(
            speeds,
            parentPIDs: [53496: 53481, 53497: 53481],
            appPIDs: [53481]
        )

        #expect(attributed[53481]?.downBytesPerSecond == 10_000_000)
        #expect(attributed[53481]?.upBytesPerSecond == 150_000)
    }

    @Test("A parent-cycle cannot hang or invent an owner")
    func networkAttributionGuardsCycles() {
        let owner = ProcessNetworkAttribution.resolveOwner(
            pid: 42,
            parentPIDs: [42: 43, 43: 44, 44: 42],
            appPIDs: [99]
        )

        #expect(owner == nil)
    }

    @Test("Measurement PIDs with no app ancestor are dropped")
    func networkAttributionDropsOrphans() {
        let speeds: [Int32: ProcessNetworkSpeed] = [
            42: ProcessNetworkSpeed(downBytesPerSecond: 1_000, upBytesPerSecond: 2_000)
        ]
        let attributed = ProcessNetworkAttribution.attribute(
            speeds,
            parentPIDs: [42: 1],
            appPIDs: [99]
        )

        #expect(attributed.isEmpty)
    }

    private func testDate(_ offset: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_900_000_000 + offset)
    }
}

private actor ScriptedNetworkRunner {
    private let outputs: [String?]
    private var index = 0
    private(set) var callCount = 0

    init(outputs: [String?]) {
        self.outputs = outputs
    }

    func next() -> String? {
        defer {
            index += 1
            callCount += 1
        }
        guard outputs.indices.contains(index) else { return nil }
        return outputs[index]
    }
}

private final class DateSequence: @unchecked Sendable {
    private let lock = NSLock()
    private let dates: [Date]
    private var index = 0

    init(_ dates: [Date]) {
        self.dates = dates
    }

    func next() -> Date {
        lock.lock()
        defer { lock.unlock() }
        guard dates.indices.contains(index) else {
            return dates.last ?? Date(timeIntervalSince1970: 0)
        }
        defer { index += 1 }
        return dates[index]
    }
}
