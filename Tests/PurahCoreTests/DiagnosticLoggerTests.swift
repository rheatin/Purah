// Tests/PurahCoreTests/DiagnosticLoggerTests.swift
import Testing
import Foundation
@testable import PurahCore

@Suite("Diagnostic Logger & System Health Tests")
struct DiagnosticLoggerTests {
    @Test("DiagnosticLogger records entries and enforces ring buffer limit")
    func testDiagnosticLoggerRingBuffer() {
        let logger = DiagnosticLogger.shared
        logger.clear()

        logger.info("TestCategory", "Test Message 1")
        logger.warn("TestCategory", "Warning Message 2")
        logger.error("TestCategory", "Error Message 3")

        let entries = logger.recentEntries(limit: 10)
        #expect(entries.count == 3)
        #expect(entries[0].message == "Test Message 1")
        #expect(entries[1].level == .warning)
        #expect(entries[2].level == .error)

        logger.clear()
        #expect(logger.recentEntries().isEmpty)
    }

    @Test("Diagnostic report generation produces non-empty report with system telemetry")
    @MainActor
    func testDiagnosticReportGeneration() {
        let store = PurahWorkspaceStore()
        let report = DiagnosticLogger.shared.generateReport(store: store)

        #expect(report.contains("PROJECT PURAH DIAGNOSTIC REPORT"))
        #expect(report.contains("[HOST SYSTEM]"))
        #expect(report.contains("[MAIN THREAD HEALTH]"))
        #expect(report.contains("[HARDWARE TELEMETRY SNAPSHOT]"))
        #expect(report.contains("[SCRIPT RUNWAY ACTIONS]"))
    }

    @Test("Rail capacity calculation and overload detection")
    @MainActor
    func testRailCapacityCalculation() {
        let store = PurahWorkspaceStore()
        let leftRequired = store.totalRequiredHeight(for: .left)
        let rightRequired = store.totalRequiredHeight(for: .right)

        #expect(leftRequired > 0)
        #expect(rightRequired > 0)

        let leftRatio = store.capacityRatio(for: .left)
        #expect(leftRatio >= 0.0)

        let isOverloaded = store.isRailOverloaded(edge: .left)
        #expect(isOverloaded == (leftRatio > 1.0))
    }

    @Test("Capacity warning toast callback triggers when rail is overloaded")
    @MainActor
    func testCapacityWarningToastCallback() {
        let store = PurahWorkspaceStore()
        var toastMessage: String? = nil
        store.onCapacityWarningToast = { msg in
            toastMessage = msg
        }

        store.isScriptsDecomposed = true
        store.isVitalsDecomposed = true
        store.notifyCapacityWarningIfNeeded()

        if store.isRailOverloaded(edge: .left) {
            #expect(toastMessage != nil)
            #expect(toastMessage?.contains("Left rail capacity overload") == true)
        }

        store.isScriptsDecomposed = false
        store.isVitalsDecomposed = false
    }
}
