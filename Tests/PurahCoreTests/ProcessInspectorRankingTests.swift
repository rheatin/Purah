import Testing
import Foundation
@testable import PurahCore

@Suite("Process Inspector Ranking")
struct ProcessInspectorRankingTests {
    @Test("CPU reports multi-core usage without the old 100 percent clamp")
    func multiCoreCPUIsUnclamped() {
        let percent = ProcessCPUPercent.calculate(
            previous: 0,
            current: 14_560_000_000,
            elapsed: 2,
            coreCount: 10
        )

        #expect(abs(percent - 728) < 0.000_001)
    }

    @Test("Mach ticks are converted to nanoseconds before reporting CPU")
    func machTickConversionIsApplied() {
        let ticks: UInt64 = 356_582_367
        let conversion = 125.0 / 3.0
        let expected = (Double(ticks) * conversion / 1_000_000_000.0 / 2.0) * 100.0

        let converted = ProcessCPUPercent.calculate(
            previous: 0,
            current: ticks,
            elapsed: 2,
            coreCount: 10,
            tickConversion: conversion
        )
        let unconverted = ProcessCPUPercent.calculate(
            previous: 0,
            current: ticks,
            elapsed: 2,
            coreCount: 10,
            tickConversion: 1.0
        )

        #expect(abs(converted - expected) < 0.000_001)
        #expect(abs(unconverted - 17.829_118_35) < 0.000_001)
    }

    @Test("CPU is capped at the number of active cores times one hundred")
    func CPUIsCappedAtCoreCapacity() {
        let percent = ProcessCPUPercent.calculate(
            previous: 0,
            current: 30_000_000_000,
            elapsed: 2,
            coreCount: 10,
            tickConversion: 125.0 / 3.0
        )

        #expect(percent == 1_000)
    }

    @Test("Short intervals and counter resets produce zero CPU")
    func invalidCPUSamplesProduceZero() {
        let shortInterval = ProcessCPUPercent.calculate(
            previous: 0,
            current: 1_000_000_000,
            elapsed: 0.05,
            coreCount: 10
        )
        let resetCounter = ProcessCPUPercent.calculate(
            previous: 2_000_000_000,
            current: 1_000_000_000,
            elapsed: 2,
            coreCount: 10
        )
        let invalidConversion = ProcessCPUPercent.calculate(
            previous: 0,
            current: 1_000_000_000,
            elapsed: 2,
            coreCount: 10,
            tickConversion: .infinity
        )

        #expect(shortInterval == 0)
        #expect(resetCounter == 0)
        #expect(invalidConversion == 0)
    }

    @Test("Ranking selects the top rows for every process metric")
    func rankingUsesEveryMetric() {
        let samples = [
            process(id: 10, name: "CPU", cpu: 728, memoryMB: 100),
            process(id: 20, name: "Memory", cpu: 1, memoryMB: 8_192),
            process(id: 30, name: "Network", cpu: 1, memoryMB: 100, networkDown: 8_000, networkUp: 2_000),
            process(id: 40, name: "Disk", cpu: 1, memoryMB: 100, diskRead: 5_000, diskWrite: 15_000),
            process(id: 50, name: "Power", cpu: 1, memoryMB: 100, energyWatts: 6)
        ]

        #expect(ProcessInspectorRanking.ranked(samples, by: .cpu, limit: 2).first?.id == 10)
        #expect(ProcessInspectorRanking.ranked(samples, by: .memory, limit: 2).first?.id == 20)
        #expect(ProcessInspectorRanking.ranked(samples, by: .network, limit: 2).first?.id == 30)
        #expect(ProcessInspectorRanking.ranked(samples, by: .disk, limit: 2).first?.id == 40)
        #expect(ProcessInspectorRanking.ranked(samples, by: .power, limit: 2).first?.id == 50)
        #expect(ProcessInspectorRanking.ranked(samples, by: .cpu, limit: 2).count == 2)
    }

    @Test("Ranking uses case-insensitive names and then PID as its tiebreak")
    func rankingTiebreaksDeterministically() {
        let samples = [
            process(id: 30, name: "bravo", cpu: 10),
            process(id: 20, name: "alpha", cpu: 10),
            process(id: 10, name: "Alpha", cpu: 10)
        ]

        let ranked = ProcessInspectorRanking.ranked(samples, by: .cpu, limit: 3)

        #expect(ranked.map(\.id) == [10, 20, 30])
    }

    @Test("A limit larger than the list is safe")
    func oversizedLimitIsSafe() {
        let samples = [
            process(id: 10, name: "One", cpu: 1),
            process(id: 20, name: "Two", cpu: 2)
        ]

        let ranked = ProcessInspectorRanking.ranked(samples, by: .cpu, limit: 100)

        #expect(ranked.map(\.id) == [20, 10])
    }

    private func process(
        id: Int32,
        name: String,
        cpu: Double = 0,
        memoryMB: Double = 0,
        networkDown: Double = 0,
        networkUp: Double = 0,
        diskRead: Double = 0,
        diskWrite: Double = 0,
        energyWatts: Double = 0
    ) -> ProcessInfoItem {
        ProcessInfoItem(
            id: id,
            name: name,
            cpuPercent: cpu,
            memoryPercent: 0,
            memoryMB: memoryMB,
            networkDownBytesPerSecond: networkDown,
            networkUpBytesPerSecond: networkUp,
            diskReadBytesPerSecond: diskRead,
            diskWriteBytesPerSecond: diskWrite,
            energyWatts: energyWatts
        )
    }
}
