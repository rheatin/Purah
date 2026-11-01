// Tests/PurahCoreTests/VitalsPluginStatePersistenceTests.swift
import Testing
import Foundation
@testable import PurahCore
@testable import PurahUI

@MainActor
@Suite("Vitals Header Metric Persistence")
struct VitalsPluginStatePersistenceTests {
    private func makeStorage(
        suite: String
    ) throws -> (defaults: UserDefaults, storage: ScopedPluginStorage) {
        let defaults = try #require(UserDefaults(suiteName: suite))
        return (
            defaults,
            ScopedPluginStorage(pluginId: "vitals-header-metric", defaults: defaults)
        )
    }

    @Test("No stored metric uses the first enabled metric")
    func testDefaultUsesFirstEnabledMetric() throws {
        let suite = "vitals_header_default_\(UUID().uuidString)"
        let (defaults, storage) = try makeStorage(suite: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        storage.setCodable([VitalsMetricType.ram, .cpu], forKey: "enabledMetrics")
        let state = VitalsPluginState(storage: storage)

        #expect(state.headerMetric == .ram)
        #expect(storage.string(forKey: "headerMetric") == VitalsMetricType.ram.rawValue)
    }

    @Test("A chosen metric persists immediately and across a new state instance")
    func testChosenMetricPersists() throws {
        let suite = "vitals_header_persist_\(UUID().uuidString)"
        let (defaults, storage) = try makeStorage(suite: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        storage.setCodable([VitalsMetricType.ram, .gpu], forKey: "enabledMetrics")
        let state = VitalsPluginState(storage: storage)
        state.setHeaderMetric(.gpu)

        #expect(storage.string(forKey: "headerMetric") == VitalsMetricType.gpu.rawValue)
        #expect(VitalsPluginState(storage: storage).headerMetric == .gpu)
    }

    @Test("save persists the selected header metric")
    func testSavePersistsHeaderMetric() throws {
        let suite = "vitals_header_save_\(UUID().uuidString)"
        let (defaults, storage) = try makeStorage(suite: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        storage.setCodable([VitalsMetricType.ram, .power], forKey: "enabledMetrics")
        let state = VitalsPluginState(storage: storage)
        state.headerMetric = .power
        state.save()

        #expect(VitalsPluginState(storage: storage).headerMetric == .power)
    }

    @Test("A persisted metric that is no longer enabled falls back and is rewritten")
    func testDisabledMetricFallsBack() throws {
        let suite = "vitals_header_disabled_\(UUID().uuidString)"
        let (defaults, storage) = try makeStorage(suite: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        storage.setCodable([VitalsMetricType.ram, .disk], forKey: "enabledMetrics")
        storage.set(VitalsMetricType.cpu.rawValue, forKey: "headerMetric")

        let state = VitalsPluginState(storage: storage)

        #expect(state.headerMetric == .ram)
        #expect(storage.string(forKey: "headerMetric") == VitalsMetricType.ram.rawValue)
    }

    @Test("A garbage stored metric falls back safely")
    func testGarbageMetricFallsBack() throws {
        let suite = "vitals_header_garbage_\(UUID().uuidString)"
        let (defaults, storage) = try makeStorage(suite: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        storage.setCodable([VitalsMetricType.network, .power], forKey: "enabledMetrics")
        storage.set("not-a-vitals-metric", forKey: "headerMetric")

        let state = VitalsPluginState(storage: storage)

        #expect(state.headerMetric == .network)
        #expect(storage.string(forKey: "headerMetric") == VitalsMetricType.network.rawValue)
    }
}
