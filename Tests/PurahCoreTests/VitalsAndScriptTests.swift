// Tests/PurahCoreTests/VitalsAndScriptTests.swift
import Testing
import Foundation
import SwiftUI
@testable import PurahCore
@testable import PurahUI

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

    @Test("VitalsMetricType includes GPU, Thermal, Network cases")
    func testExtendedMetricTypes() {
        let all = VitalsMetricType.allCases
        #expect(all.contains(.gpu))
        #expect(all.contains(.thermal))
        #expect(all.contains(.network))
        #expect(VitalsMetricType.gpu.systemIcon == "display")
        #expect(VitalsMetricType.thermal.systemIcon == "thermometer.medium")
        #expect(VitalsMetricType.network.systemIcon == "network")

        let service = HardwareVitalsService.shared
        service.refreshMetrics(includeProcesses: false)
        let metrics = service.metrics
        #expect(metrics.gpuUsage >= 0.0 && metrics.gpuUsage <= 1.0)
        #expect(metrics.networkDownSpeed >= 0.0)
        #expect(metrics.networkUpSpeed >= 0.0)
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
        #expect(VitalsMetricType.allCases.count == 7)
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

    @Test("PurahWorkspaceStore scripts decomposition state and dynamic height")
    func testScriptsDecompositionState() {
        let store = PurahWorkspaceStore()
        store.isScriptsDecomposed = true
        store.scriptsEnabledActionIds = ["a1", "a2", "a3"]

        let height = store.minimumDrawerHeight(for: "scripts")
        // 3 items * 56.0 + 2 gaps * 2.5 = 168.0 + 5.0 = 173.0
        #expect(height >= 168.0)
        #expect(store.isScriptsDecomposed == true)

        // Test persistence roundtrip
        store.savePersistentState()
        let reloaded = PurahWorkspaceStore()
        #expect(reloaded.isScriptsDecomposed == true)
        #expect(reloaded.scriptsEnabledActionIds == ["a1", "a2", "a3"])

        // Reset
        store.isScriptsDecomposed = false
        store.scriptsEnabledActionIds = ScriptRunwayService.shared.actions.map(\.id)
        store.savePersistentState()
    }

    @Test("VitalsColorThresholds defaults and store serialization")
    func testVitalsColorThresholds() {
        var thresholds = VitalsColorThresholds()
        #expect(thresholds.cpuWarning == 0.50)
        #expect(thresholds.cpuDanger == 0.80)
        #expect(thresholds.ramWarning == 0.70)
        #expect(thresholds.ramDanger == 0.85)

        thresholds.cpuWarning = 0.60
        let store = PurahWorkspaceStore()
        store.vitalsThresholds = thresholds
        store.savePersistentState()
        #expect(store.vitalsThresholds.cpuWarning == 0.60)

        let reloaded = PurahWorkspaceStore()
        #expect(reloaded.vitalsThresholds.cpuWarning == 0.60)

        // Reset
        store.vitalsThresholds = VitalsColorThresholds()
        store.savePersistentState()
    }

    @Test("VitalsColorResolver evaluates healthy state for all metrics")
    func testVitalsColorResolverHealthy() {
        let thresholds = VitalsColorThresholds()
        let healthyVitals = HardwareVitalsInfo(
            cpuUsage: 0.15,
            gpuUsage: 0.10,
            memoryUsage: 0.40,
            diskFreeGB: 250.0,
            diskTotalGB: 500.0,
            batteryLevel: 95,
            isCharging: true,
            thermalStateDescription: "Nominal",
            isUnderThermalPressure: false,
            networkDownSpeed: 500_000.0,
            networkUpSpeed: 100_000.0
        )

        for metric in VitalsMetricType.allCases {
            let color = VitalsColorResolver.color(for: metric, vitals: healthyVitals, thresholds: thresholds)
            #expect(color == VitalsColorResolver.healthyGreen)
        }

        let overall = VitalsColorResolver.overallVitalsColor(vitals: healthyVitals, thresholds: thresholds)
        #expect(overall == VitalsColorResolver.healthyGreen)
    }

    @Test("VitalsColorResolver evaluates warning thresholds accurately")
    func testVitalsColorResolverWarning() {
        let thresholds = VitalsColorThresholds()

        // CPU Warning
        let cpuWarn = HardwareVitalsInfo(cpuUsage: 0.65)
        #expect(VitalsColorResolver.color(for: .cpu, vitals: cpuWarn, thresholds: thresholds) == VitalsColorResolver.warningYellow)
        #expect(VitalsColorResolver.overallVitalsColor(vitals: cpuWarn, thresholds: thresholds) == VitalsColorResolver.warningYellow)

        // GPU Warning
        let gpuWarn = HardwareVitalsInfo(gpuUsage: 0.60)
        #expect(VitalsColorResolver.color(for: .gpu, vitals: gpuWarn, thresholds: thresholds) == VitalsColorResolver.warningYellow)

        // RAM Warning
        let ramWarn = HardwareVitalsInfo(memoryUsage: 0.75)
        #expect(VitalsColorResolver.color(for: .ram, vitals: ramWarn, thresholds: thresholds) == VitalsColorResolver.warningYellow)

        // Thermal Fair Warning
        let thermalWarn = HardwareVitalsInfo(thermalStateDescription: "Fair", isUnderThermalPressure: false)
        #expect(VitalsColorResolver.color(for: .thermal, vitals: thermalWarn, thresholds: thresholds) == VitalsColorResolver.warningYellow)

        // Battery Low Warning (Unplugged, battery <= 20%, > 10%)
        let batteryWarn = HardwareVitalsInfo(batteryLevel: 15, isCharging: false)
        #expect(VitalsColorResolver.color(for: .power, vitals: batteryWarn, thresholds: thresholds) == VitalsColorResolver.warningYellow)

        // Network Warning (> 10MB/s)
        let netWarn = HardwareVitalsInfo(networkDownSpeed: 15 * 1_048_576.0, networkUpSpeed: 0)
        #expect(VitalsColorResolver.color(for: .network, vitals: netWarn, thresholds: thresholds) == VitalsColorResolver.warningYellow)

        // Disk Warning (> 80% used and <= 90% used)
        let diskWarn85 = HardwareVitalsInfo(diskFreeGB: 75.0, diskTotalGB: 500.0) // 85% used
        #expect(VitalsColorResolver.color(for: .disk, vitals: diskWarn85, thresholds: thresholds) == VitalsColorResolver.warningYellow)
    }

    @Test("VitalsColorResolver evaluates danger thresholds accurately")
    func testVitalsColorResolverDanger() {
        let thresholds = VitalsColorThresholds()

        // CPU Danger
        let cpuDanger = HardwareVitalsInfo(cpuUsage: 0.88)
        #expect(VitalsColorResolver.color(for: .cpu, vitals: cpuDanger, thresholds: thresholds) == VitalsColorResolver.dangerRed)
        #expect(VitalsColorResolver.overallVitalsColor(vitals: cpuDanger, thresholds: thresholds) == VitalsColorResolver.dangerRed)

        // GPU Danger
        let gpuDanger = HardwareVitalsInfo(gpuUsage: 0.85)
        #expect(VitalsColorResolver.color(for: .gpu, vitals: gpuDanger, thresholds: thresholds) == VitalsColorResolver.dangerRed)

        // RAM Danger
        let ramDanger = HardwareVitalsInfo(memoryUsage: 0.90)
        #expect(VitalsColorResolver.color(for: .ram, vitals: ramDanger, thresholds: thresholds) == VitalsColorResolver.dangerRed)

        // Thermal Pressure / Serious / Critical
        let thermalSerious = HardwareVitalsInfo(thermalStateDescription: "Serious", isUnderThermalPressure: true)
        #expect(VitalsColorResolver.color(for: .thermal, vitals: thermalSerious, thresholds: thresholds) == VitalsColorResolver.dangerRed)
        #expect(VitalsColorResolver.overallVitalsColor(vitals: thermalSerious, thresholds: thresholds) == VitalsColorResolver.dangerRed)

        // Critical Battery (<= 10% unplugged)
        let batteryDanger = HardwareVitalsInfo(batteryLevel: 8, isCharging: false)
        #expect(VitalsColorResolver.color(for: .power, vitals: batteryDanger, thresholds: thresholds) == VitalsColorResolver.dangerRed)

        // Network Danger (> 50MB/s)
        let netDanger = HardwareVitalsInfo(networkDownSpeed: 60 * 1_048_576.0, networkUpSpeed: 0)
        #expect(VitalsColorResolver.color(for: .network, vitals: netDanger, thresholds: thresholds) == VitalsColorResolver.dangerRed)

        // Disk Danger (> 90% used)
        let diskDanger = HardwareVitalsInfo(diskFreeGB: 40.0, diskTotalGB: 500.0) // 92% used
        #expect(VitalsColorResolver.color(for: .disk, vitals: diskDanger, thresholds: thresholds) == VitalsColorResolver.dangerRed)
    }

    @Test("Custom thresholds override defaults in VitalsColorResolver")
    func testCustomThresholds() {
        let custom = VitalsColorThresholds(
            cpuWarning: 0.30,
            cpuDanger: 0.50,
            gpuWarning: 0.30,
            gpuDanger: 0.50
        )
        let vitals = HardwareVitalsInfo(cpuUsage: 0.35, gpuUsage: 0.55)
        #expect(VitalsColorResolver.color(for: .cpu, vitals: vitals, thresholds: custom) == VitalsColorResolver.warningYellow)
        #expect(VitalsColorResolver.color(for: .gpu, vitals: vitals, thresholds: custom) == VitalsColorResolver.dangerRed)
    }

    @Test("ThemePalette podColor for vitals ignores static custom color and uses dynamic resolution")
    func testVitalsIgnoresStaticCustomColor() {
        let store = PurahWorkspaceStore()
        store.setPodColorHex(podId: "vitals", hex: "#FF0000") // Red hex
        let palette = ThemePalette.palette(for: .native)

        let resolved = palette.podColor(for: "vitals", store: store)
        // Should NOT be red (#FF0000); should be dynamically resolved to current system vitals overall color
        #expect(resolved != Color(hex: "#FF0000"))
        let expected = VitalsColorResolver.overallVitalsColor(
            vitals: HardwareVitalsService.shared.metrics,
            thresholds: store.vitalsThresholds,
            palette: palette
        )
        #expect(resolved == expected)

        // Reset
        store.customPodColors.removeValue(forKey: "vitals")
    }
}
