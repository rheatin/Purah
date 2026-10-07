// Sources/PurahCore/Diagnostics/DiagnosticLogger.swift
import Foundation
import os

public enum DiagnosticLogLevel: String, Codable, Sendable {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
}

public struct DiagnosticLogEntry: Identifiable, Sendable, Codable {
    public let id: UUID
    public let timestamp: Date
    public let level: DiagnosticLogLevel
    public let category: String
    public let message: String

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        level: DiagnosticLogLevel,
        category: String,
        message: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.message = message
    }

    public var formattedLine: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withTime, .withColonSeparatorInTime]
        let timeStr = formatter.string(from: timestamp)
        return "[\(timeStr)] [\(level.rawValue)] [\(category)] \(message)"
    }
}

public final class DiagnosticLogger: Sendable {
    public static let shared = DiagnosticLogger()

    private let storage: OSAllocatedUnfairLock<[DiagnosticLogEntry]>
    private let stats: OSAllocatedUnfairLock<(stalls: Int, maxStallMs: Double)>
    private let maxEntries = 1000

    public var mainThreadStallsCount: Int {
        stats.withLock { $0.stalls }
    }
    public var maxStallDurationMs: Double {
        stats.withLock { $0.maxStallMs }
    }

    public init() {
        self.storage = OSAllocatedUnfairLock(initialState: [])
        self.stats = OSAllocatedUnfairLock(initialState: (stalls: 0, maxStallMs: 0.0))
        log(level: .info, category: "Kernel", message: "DiagnosticLogger initialized")
        startWatchdog()
    }

    public func log(level: DiagnosticLogLevel, category: String, message: String) {
        let entry = DiagnosticLogEntry(level: level, category: category, message: message)
        storage.withLock { entries in
            entries.append(entry)
            if entries.count > maxEntries {
                entries.removeFirst(entries.count - maxEntries)
            }
        }
    }

    public func debug(_ category: String, _ message: String) {
        log(level: .debug, category: category, message: message)
    }

    public func info(_ category: String, _ message: String) {
        log(level: .info, category: category, message: message)
    }

    public func warn(_ category: String, _ message: String) {
        log(level: .warning, category: category, message: message)
    }

    public func error(_ category: String, _ message: String) {
        log(level: .error, category: category, message: message)
    }

    public func recentEntries(limit: Int = 100) -> [DiagnosticLogEntry] {
        storage.withLock { entries in
            let count = min(entries.count, limit)
            return Array(entries.suffix(count))
        }
    }

    public func clear() {
        storage.withLock { entries in
            entries.removeAll()
        }
    }

    // MARK: - Main Thread Watchdog
    public func startWatchdog() {
        Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                let start = Date()
                let didRespond = await withTaskCancellationHandler {
                    await withCheckedContinuation { continuation in
                        Task { @MainActor in
                            continuation.resume(returning: true)
                        }
                    }
                } onCancel: {}

                let elapsedMs = Date().timeIntervalSince(start) * 1000.0
                if didRespond && elapsedMs > 1200.0 {
                    self?.recordStall(durationMs: elapsedMs)
                }
            }
        }
    }

    private func recordStall(durationMs: Double) {
        stats.withLock { current in
            current.stalls += 1
            current.maxStallMs = max(current.maxStallMs, durationMs)
        }

        warn("Watchdog", "MainActor unresponsive stall detected: \(Int(durationMs))ms")
    }

    // MARK: - Diagnostic Report Generation
    @MainActor
    public func generateReport(store: PurahWorkspaceStore? = nil) -> String {
        var report = "=== PROJECT PURAH DIAGNOSTIC REPORT ===\n"
        report += "Generated: \(Date().description(with: .current))\n\n"

        // 1. Host System
        report += "-- [HOST SYSTEM] --\n"
        report += "OS Version: \(ProcessInfo.processInfo.operatingSystemVersionString)\n"
        report += "Physical Memory: \(ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)) GB\n"
        report += "Processors: \(ProcessInfo.processInfo.processorCount) cores (active: \(ProcessInfo.processInfo.activeProcessorCount))\n"
        report += "Thermal State: \(HardwareVitalsService.shared.metrics.thermalStateDescription)\n\n"

        // 2. MainActor Watchdog
        let (stalls, maxStall) = stats.withLock { ($0.stalls, $0.maxStallMs) }
        report += "-- [MAIN THREAD HEALTH] --\n"
        report += "Total MainActor Stalls: \(stalls)\n"
        report += "Max Stall Duration: \(String(format: "%.1f", maxStall))ms\n"
        report += "Watchdog Status: \(stalls > 0 ? "⚠️ Stalls Encountered" : "✅ Healthy (No Stalls)")\n\n"

        // 3. Telemetry Snapshot
        let vitals = HardwareVitalsService.shared.metrics
        report += "-- [HARDWARE TELEMETRY SNAPSHOT] --\n"
        report += "CPU: \(Int(vitals.cpuUsage * 100))%\n"
        report += "GPU: \(Int(vitals.gpuUsage * 100))%\n"
        report += "RAM: \(String(format: "%.1f", vitals.memoryUsedGB)) / \(String(format: "%.1f", vitals.memoryTotalGB)) GB (\(Int(vitals.memoryUsage * 100))%)\n"
        report += "Power: \(vitals.batteryLevel)% (\(vitals.isCharging ? "Charging" : "Battery"), \(vitals.powerSource))\n"
        report += "Disk: \(String(format: "%.1f", vitals.diskFreeGB)) GB Free / \(String(format: "%.1f", vitals.diskTotalGB)) GB Total\n"
        report += "Network: ↓ \(String(format: "%.1f", vitals.networkDownSpeed / 1024)) KB/s · ↑ \(String(format: "%.1f", vitals.networkUpSpeed / 1024)) KB/s\n\n"

        // 4. Scripts Runway
        let runway = ScriptRunwayService.shared
        report += "-- [SCRIPT RUNWAY ACTIONS] --\n"
        report += "Action Count: \(runway.actions.count)\n"
        for (idx, a) in runway.actions.enumerated() {
            report += "[\(idx + 1)] \(a.name) (\(a.commandType.rawValue.uppercased())): \(a.scriptContent)\n"
        }
        if let lastOutput = runway.lastOutput {
            report += "Last Output: \(lastOutput)\n"
        }
        report += "\n"

        // 5. Recent Diagnostic Logs
        report += "-- [RECENT EVENT LOGS (\(recentEntries(limit: 100).count) entries)] --\n"
        for entry in recentEntries(limit: 200) {
            report += "\(entry.formattedLine)\n"
        }
        report += "=== END OF REPORT ===\n"

        return report
    }
}
