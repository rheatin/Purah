import Foundation
import Testing
@testable import PurahCore

@MainActor
@Suite("Vitals service state machine")
struct VitalsServiceStateMachineTests {
    /// The service records a state bucket on init, so start inside the bucket
    /// that is current right now instead of an arbitrary past instant.
    private let base = Date(
        timeIntervalSince1970: floor(Date().timeIntervalSince1970 / 600) * 600
    )

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("purah-vitals-state-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func batteryProbe(isPresent: Bool) -> () -> (
        level: Int,
        isCharging: Bool,
        source: String,
        healthPercent: Int,
        cycleCount: Int,
        temperatureCelsius: Double,
        isPresent: Bool,
        voltageVolts: Double,
        chargeWatts: Double,
        timeRemainingMinutes: Int?,
        condition: String,
        systemWatts: Double,
        systemVolts: Double,
        systemAmps: Double,
        adapterWatts: Double,
        maxCapacityMAh: Double,
        designCapacityMAh: Double
    ) {
        {
            (
                level: 80,
                isCharging: false,
                source: "Battery",
                healthPercent: 90,
                cycleCount: 100,
                temperatureCelsius: 30,
                isPresent: isPresent,
                voltageVolts: 12,
                chargeWatts: 8,
                timeRemainingMinutes: 200,
                condition: "Normal",
                systemWatts: 8,
                systemVolts: 12,
                systemAmps: 0.67,
                adapterWatts: 0,
                maxCapacityMAh: 5_000,
                designCapacityMAh: 5_500
            )
        }
    }

    private func makeService(
        directory: URL,
        batteryPresent: Bool = true
    ) -> HardwareVitalsService {
        HardwareVitalsService(
            storageDirectory: directory,
            processNetworkSampler: ProcessNetworkSampler(runner: { nil }),
            diskIOProbe: {
                (
                    readBytesPerSec: 50 * 1_048_576,
                    writeBytesPerSec: 20 * 1_048_576,
                    readTotalGB: 1,
                    writeTotalGB: 1
                )
            },
            batteryProbe: batteryProbe(isPresent: batteryPresent)
        )
    }

    @Test("Under XCTest the default Vitals storage is a temporary directory")
    func defaultStorageIsTemporaryUnderTests() {
        let resolved = HardwareVitalsService.defaultStorageDirectory.standardizedFileURL
        let temporary = FileManager.default.temporaryDirectory.standardizedFileURL
        #expect(resolved.path.hasPrefix(temporary.path))
        #expect(!resolved.path.contains("Library/Application Support/Purah/Vitals"))
    }

    @Test("Throughput is appended raw, in bytes per second")
    func throughputAppendsRawBytes() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = makeService(directory: directory)

        service.isDrawerVisible = true
        service.refreshMetrics(includeProcesses: false)

        #expect(service.diskReadHistory.last?.value == 52_428_800.0)
        #expect(service.diskWriteHistory.last?.value == 20_971_520.0)
    }

    @Test("A cadence restart keeps the Processes tab visible")
    func restartKeepsProcessesTabVisible() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = makeService(directory: directory)
        defer { service.stopMonitoring() }

        service.startMonitoring(interval: 1)
        service.setProcessesTabVisible(true)
        #expect(service.isProcessesTabVisible)

        service.restartMonitoring(interval: 2)
        #expect(service.samplingInterval == 2)
        #expect(service.isProcessesTabVisible)

        service.setProcessesTabVisible(false)
        service.restartMonitoring(interval: 1)
        #expect(service.samplingInterval == 1)
        #expect(!service.isProcessesTabVisible)
    }

    @Test("Starting on the same interval does not restart the monitor")
    func sameIntervalDoesNotRestart() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = makeService(directory: directory)
        defer { service.stopMonitoring() }

        service.startMonitoring(interval: 1)
        let file = directory.appendingPathComponent("vitals_history.json")
        try? FileManager.default.removeItem(at: file)

        service.startMonitoring(interval: 1)
        #expect(service.isMonitoring)
        #expect(!FileManager.default.fileExists(atPath: file.path))

        service.restartMonitoring(interval: 1)
        #expect(!FileManager.default.fileExists(atPath: file.path))

        service.restartMonitoring(interval: 2)
        #expect(service.samplingInterval == 2)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test("The save budget is a wall-clock cadence with a one-tick floor")
    func saveIntervalTicksFollowTheInterval() {
        #expect(HardwareVitalsService.saveIntervalTicks(for: 1) == 600)
        #expect(HardwareVitalsService.saveIntervalTicks(for: 2) == 300)
        #expect(HardwareVitalsService.saveIntervalTicks(for: 5) == 120)
        #expect(HardwareVitalsService.saveIntervalTicks(for: 0) >= 1)
        #expect(HardwareVitalsService.saveIntervalTicks(for: -5) >= 1)
    }

    @Test("Crossing a ten-minute boundary records the previous state")
    func batteryStateRolloverRecordsPreviousState() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = makeService(directory: directory)

        service.recordBatteryState(1, at: base)
        service.recordBatteryState(2, at: base.addingTimeInterval(300))
        #expect(service.batteryStatePoints.isEmpty)

        service.recordBatteryState(0, at: base.addingTimeInterval(600))
        #expect(service.batteryStatePoints.count == 1)
        #expect(service.batteryStatePoints.first?.timestamp == base)
        #expect(service.batteryStatePoints.first?.value == 2)
    }

    @Test("A three-interval gap records one cell, not three")
    func batteryStateGapRecordsOneCell() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = makeService(directory: directory)

        service.recordBatteryState(1, at: base)
        service.recordBatteryState(0, at: base.addingTimeInterval(1_800))

        #expect(service.batteryStatePoints.count == 1)
        #expect(service.batteryStatePoints.first?.timestamp == base)
        #expect(service.batteryStatePoints.first?.value == 1)
    }

    @Test("A Mac without a battery records no state")
    func desktopRecordsNoBatteryState() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = makeService(directory: directory, batteryPresent: false)

        service.isDrawerVisible = true
        service.refreshMetrics(includeProcesses: false)

        #expect(!service.metrics.batteryIsPresent)
        #expect(service.batteryStatePoints.isEmpty)
    }
}
