// Tests/PurahCoreTests/VitalsTelemetryFormatterTests.swift
import Testing
import Foundation
@testable import PurahCore
@testable import PurahUI

@Suite("Vitals Telemetry Formatter & Service Injection Tests")
struct VitalsTelemetryFormatterTests {

    @Test("formatRate produces compact and spaced units across B, K, and M thresholds")
    func testFormatRateUnits() {
        #expect(VitalsTelemetryFormatter.formatRate(0, style: .compact) == "0B/s")
        #expect(VitalsTelemetryFormatter.formatRate(512, style: .compact) == "512B/s")
        #expect(VitalsTelemetryFormatter.formatRate(2048, style: .compact) == "2K/s")
        #expect(VitalsTelemetryFormatter.formatRate(1_572_864, style: .compact) == "1.5M/s")

        #expect(VitalsTelemetryFormatter.formatRate(512, style: .spaced) == "512 B/s")
        #expect(VitalsTelemetryFormatter.formatRate(2048, style: .spaced) == "2 KB/s")
        #expect(VitalsTelemetryFormatter.formatRate(1_572_864, style: .spaced) == "1.5 MB/s")
    }

    @Test("compactGB and compactSwap drop whole-number decimals and scale megabytes to gigabytes")
    func testCompactGBAndSwap() {
        #expect(VitalsTelemetryFormatter.compactGB(16.0) == "16")
        #expect(VitalsTelemetryFormatter.compactGB(16.04) == "16")
        #expect(VitalsTelemetryFormatter.compactGB(16.46) == "16.5")

        #expect(VitalsTelemetryFormatter.compactSwap(0.4) == "0")
        #expect(VitalsTelemetryFormatter.compactSwap(512) == "512M")
        #expect(VitalsTelemetryFormatter.compactSwap(1536) == "1.5G")
        #expect(VitalsTelemetryFormatter.compactSwap(2048) == "2G")
    }

    @Test("systemWatts prefers SMC watts, zeroes AC power fallback, and negates battery discharge")
    func testSystemWattsFallback() {
        var info = HardwareVitalsInfo()
        info.powerSystemWatts = 14.2
        info.powerSource = "Battery"
        info.batteryChargeWatts = -9.5
        #expect(VitalsTelemetryFormatter.systemWatts(info) == 14.2)

        info.powerSystemWatts = 0
        #expect(VitalsTelemetryFormatter.systemWatts(info) == 9.5)

        info.powerSource = "AC Power"
        #expect(VitalsTelemetryFormatter.systemWatts(info) == 0)
    }

    @Test("VitalsPluginState binds to its injected HardwareVitalsService rather than global shared")
    @MainActor
    func testVitalsPluginStateInjectedService() throws {
        let suiteName = "purah.test.vitals.inject.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("purah-vitals-inject-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let customService = HardwareVitalsService(
            storageDirectory: tempDir,
            processNetworkSampler: ProcessNetworkSampler(runner: { nil }),
            diskIOProbe: { (readBytesPerSec: 0, writeBytesPerSec: 0, readTotalGB: 0, writeTotalGB: 0) },
            batteryProbe: {
                (
                    level: 73,
                    isCharging: false,
                    source: "Battery",
                    healthPercent: 95,
                    cycleCount: 42,
                    temperatureCelsius: 31.0,
                    isPresent: true,
                    voltageVolts: 12.1,
                    chargeWatts: -8.5,
                    timeRemainingMinutes: 240,
                    condition: "Normal",
                    systemWatts: 11.2,
                    systemVolts: 12.1,
                    systemAmps: 0.9,
                    adapterWatts: 0.0,
                    maxCapacityMAh: 5000,
                    designCapacityMAh: 5200
                )
            }
        )
        let state = VitalsPluginState(
            storage: ScopedPluginStorage(pluginId: "vitals", defaults: defaults),
            vitalsService: customService
        )
        customService.isDrawerVisible = true
        state.refreshMetrics(includeProcesses: false)
        #expect(state.vitalsService === customService)
        #expect(state.vitalsService !== HardwareVitalsService.shared)
        #expect(state.metrics.batteryLevel == 73)
        #expect(state.ratio(for: .power) == 0.73)
    }
}
