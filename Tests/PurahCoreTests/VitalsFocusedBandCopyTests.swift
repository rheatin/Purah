// Tests/PurahCoreTests/VitalsFocusedBandCopyTests.swift
import Testing
import PurahCore
@testable import PurahUI

/// The focused chip drawer prints one fact once: the header carries the
/// metric's real magnitude, and the footer keeps the time context plus the
/// range instead of repeating the reading.
@Suite("Vitals Focused Band Copy")
struct VitalsFocusedBandCopyTests {
    private func metrics() -> HardwareVitalsInfo {
        HardwareVitalsInfo(
            cpuUsage: 0.16,
            gpuUsage: 0.26,
            memoryUsage: 0.57,
            memoryUsedGB: 9.7,
            memoryTotalGB: 16,
            diskFreeGB: 109,
            diskTotalGB: 245,
            powerSource: "AC Power",
            networkDownSpeed: 20_480,
            networkUpSpeed: 10_240,
            gpuMemoryInUseMB: 282,
            powerSystemWatts: 5.1
        )
    }

    private func copy(_ metric: VitalsMetricType) -> VitalsFocusedBandCopy {
        VitalsFocusedBandCopy.make(
            metric: metric,
            metrics: metrics(),
            nowLabel: "now",
            rangeFooter: "1 hr"
        )
    }

    @Test("Every metric still has a reading in the header")
    func everyMetricReads() {
        for metric in VitalsMetricType.allCases {
            #expect(!copy(metric).reading.isEmpty)
        }
    }

    @Test("The header's fact is never printed again in the footer")
    func noDuplicatedFact() {
        for metric in VitalsMetricType.allCases {
            let band = copy(metric)
            #expect(!band.reading.isEmpty)
            #expect(band.reading != band.footerLeading)
            #expect(!band.footerLeading.contains(band.reading),
                    "\(metric) repeats \(band.reading) in \(band.footerLeading)")
            #expect(band.reading != band.footerTrailing)
            #expect(band.footerLeading != band.footerTrailing)
        }
    }

    @Test("Disk and RAM print the used/total magnitude once, in the header")
    func magnitudesLiveInTheHeader() {
        #expect(copy(.disk).reading == "136 / 245 GB")
        #expect(copy(.disk).footerLeading == "now")
        #expect(copy(.ram).reading == "9.7 / 16 GB")
        #expect(copy(.ram).footerLeading == "now")
    }

    @Test("Power prints watts, network prints the rate, CPU/GPU keep the percentage")
    func readingsMatchTheMetric() {
        #expect(copy(.power).reading == "5.1 W")
        #expect(copy(.network).reading == "30K/s")
        #expect(copy(.cpu).reading == "16%")
        #expect(copy(.gpu).reading == "26%")
        #expect(copy(.gpu).footerLeading == "now · 282 M")
    }
}
