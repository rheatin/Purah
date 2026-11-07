import Foundation
import Testing
@testable import PurahCore

@Suite("Vitals persisted history loading")
struct VitalsPersistenceLoadTests {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("purah-vitals-load-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("A version-1 single-array file loads into the fast tier")
    @MainActor
    func legacyFileLoadsThroughService() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let now = Date()
        let points = (0..<10).map { index in
            VitalsHistoryPoint(
                timestamp: now.addingTimeInterval(-Double(index)),
                value: 0.123
            )
        }
        let legacy = ["cpu": points]
        let data = try JSONEncoder().encode(legacy)
        try data.write(to: directory.appendingPathComponent("vitals_history.json"))

        let service = HardwareVitalsService(storageDirectory: directory)
        #expect(service.cpuHistory.contains { abs($0.value - 0.123) < 0.0001 })
        #expect(!service.columns(for: .cpu, scope: .realTime30s).isEmpty)
    }

    @Test("A malformed file leaves an empty history instead of crashing")
    @MainActor
    func malformedFileClearsHistory() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let service = HardwareVitalsService(storageDirectory: directory)
        #expect(!service.cpuHistory.isEmpty)

        try Data("{\"cpu\": 7}".utf8)
            .write(to: directory.appendingPathComponent("vitals_history.json"))
        service.loadHistoryFromDisk()

        #expect(service.cpuHistory.isEmpty)
        #expect(service.networkDownHistory.isEmpty)
        #expect(service.batteryStatePoints.isEmpty)
    }
}
