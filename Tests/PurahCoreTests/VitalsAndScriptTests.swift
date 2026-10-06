// Tests/PurahCoreTests/VitalsAndScriptTests.swift
import Testing
import Foundation
@testable import PurahCore

@Suite("Hardware Vitals and Script Runway Tests")
@MainActor
struct VitalsAndScriptTests {
    @Test("Hardware Vitals reads CPU, Memory, Disk, Power and Thermal accurately")
    func testHardwareVitals() {
        let service = HardwareVitalsService.shared
        service.refreshMetrics(includeProcesses: true)
        let metrics = service.metrics

        #expect(metrics.cpuUsage >= 0.0 && metrics.cpuUsage <= 1.0)
        #expect(metrics.memoryUsage >= 0.0 && metrics.memoryUsage <= 1.0)
        #expect(metrics.memoryUsedGB >= 0.0)
        #expect(metrics.memoryTotalGB > 0.0)
        #expect(metrics.diskFreeGB >= 0.0)
        #expect(metrics.diskTotalGB > 0.0)
        #expect(metrics.batteryLevel >= 0 && metrics.batteryLevel <= 100)
        #expect(!metrics.powerSource.isEmpty)
        #expect(!metrics.thermalStateDescription.isEmpty)
    }

    @Test("Hardware Vitals async refresh works correctly")
    func testHardwareVitalsAsync() async {
        let service = HardwareVitalsService.shared
        await service.refreshMetricsAsync(includeProcesses: true)
        let metrics = service.metrics
        #expect(metrics.diskTotalGB > 0.0)
        #expect(metrics.memoryTotalGB > 0.0)
    }

    @Test("Script Runway defines default maintenance actions")
    func testScriptActions() {
        let service = ScriptRunwayService.shared
        #expect(service.actions.count >= 3)
        #expect(service.actions.contains(where: { $0.id == "flush-dns" }))
        #expect(service.actions.contains(where: { $0.id == "empty-trash" }))
    }

    @Test("Script Runway manages custom actions and shortcuts")
    func testScriptRunwayCustomActionManagement() {
        let service = ScriptRunwayService()
        let customAction = ScriptActionItem(
            id: "test-shortcut",
            name: "Test Shortcut",
            systemIcon: "bolt.fill",
            commandType: .shortcut,
            scriptContent: "Meeting Mode",
            description: "Test description"
        )
        service.addAction(customAction)
        #expect(service.actions.contains(where: { $0.id == "test-shortcut" }))

        service.removeAction(id: "test-shortcut")
        #expect(!service.actions.contains(where: { $0.id == "test-shortcut" }))
    }

    @Test("ScriptRunwayService updateAction mutates existing action in-place")
    func testUpdateAction() {
        let service = ScriptRunwayService()
        let initialAction = ScriptActionItem(
            id: "test-action-1",
            name: "Old Name",
            systemIcon: "bolt",
            commandType: .shell,
            scriptContent: "echo old",
            description: "Old Desc"
        )
        service.addAction(initialAction)

        let updated = ScriptActionItem(
            id: "test-action-1",
            name: "New Name",
            systemIcon: "terminal.fill",
            commandType: .shortcut,
            scriptContent: "Run Shortcut",
            description: "New Desc"
        )
        service.updateAction(updated)

        let fetched = service.action(for: "test-action-1")
        #expect(fetched?.name == "New Name")
        #expect(fetched?.systemIcon == "terminal.fill")
        #expect(fetched?.commandType == .shortcut)
        #expect(fetched?.scriptContent == "Run Shortcut")
        #expect(fetched?.description == "New Desc")

        service.removeAction(id: "test-action-1")
    }

    @Test("Vitals metric decomposition settings and sub-metric models")
    @MainActor
    func testVitalsMetricDecompositionSettings() {
        let store = PurahWorkspaceStore()
        #expect(VitalsMetricType.allCases.count == 4)
        #expect(VitalsMetricType.cpu.displayName == "CPU Load")

        store.isVitalsDecomposed = true
        store.vitalsEnabledMetrics = [.cpu, .ram]
        store.savePersistentState()

        let reloaded = PurahWorkspaceStore()
        #expect(reloaded.isVitalsDecomposed == true)
        #expect(reloaded.vitalsEnabledMetrics.contains(.cpu))
        #expect(reloaded.vitalsEnabledMetrics.contains(.ram))

        // Reset
        store.isVitalsDecomposed = false
        store.vitalsEnabledMetrics = [.cpu, .ram, .power, .disk]
        store.savePersistentState()
    }
}
