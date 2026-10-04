// Tests/PurahCoreTests/VitalsAndScriptTests.swift
import Testing
import Foundation
@testable import PurahCore

@Suite("Hardware Vitals and Script Runway Tests")
struct VitalsAndScriptTests {
    @Test("Hardware Vitals reads CPU and Memory load accurately")
    func testHardwareVitals() {
        let service = HardwareVitalsService.shared
        service.refreshMetrics()
        #expect(service.metrics.cpuUsage >= 0.0 && service.metrics.cpuUsage <= 1.0)
        #expect(service.metrics.memoryUsage >= 0.0 && service.metrics.memoryUsage <= 1.0)
    }

    @Test("Script Runway defines default maintenance actions")
    func testScriptActions() {
        let service = ScriptRunwayService.shared
        #expect(service.actions.count >= 3)
        #expect(service.actions.contains(where: { $0.id == "flush-dns" }))
        #expect(service.actions.contains(where: { $0.id == "empty-trash" }))
    }
}
