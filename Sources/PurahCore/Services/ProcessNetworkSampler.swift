// Sources/PurahCore/Services/ProcessNetworkSampler.swift
import Foundation

/// One cumulative byte reading from `nettop`.
public struct ProcessNetworkByteCounts: Sendable, Equatable {
    public let bytesIn: UInt64
    public let bytesOut: UInt64

    public init(bytesIn: UInt64, bytesOut: UInt64) {
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
    }
}

/// Per-process network throughput derived from two cumulative samples.
public struct ProcessNetworkSpeed: Sendable, Equatable {
    public let downBytesPerSecond: Double
    public let upBytesPerSecond: Double

    public init(downBytesPerSecond: Double, upBytesPerSecond: Double) {
        self.downBytesPerSecond = downBytesPerSecond
        self.upBytesPerSecond = upBytesPerSecond
    }

    public static let zero = ProcessNetworkSpeed(downBytesPerSecond: 0, upBytesPerSecond: 0)
}

/// Samples cumulative per-process network counters with `nettop`.
///
/// The first call establishes a baseline and reports zeros. Later calls divide
/// byte deltas by the wall-clock time between samples. The runner and clock are
/// injectable so tests never launch a subprocess or depend on wall time.
public actor ProcessNetworkSampler {
    public typealias Runner = @Sendable () async -> String?
    public typealias Clock = @Sendable () -> Date

    private let runner: Runner
    private let clock: Clock
    private var previousCounts: [Int32: ProcessNetworkByteCounts]?
    private var previousTimestamp: Date?

    public init(
        runner: Runner? = nil,
        clock: @escaping Clock = { Date() }
    ) {
        self.runner = runner ?? Self.runNettop
        self.clock = clock
    }

    /// Clears the byte baseline so the next successful sample starts at zero.
    public func reset() {
        previousCounts = nil
        previousTimestamp = nil
    }

    public func sample() async -> [Int32: ProcessNetworkSpeed] {
        guard let output = await runner() else {
            resetBaseline()
            return [:]
        }
        let current = Self.parse(output)
        guard !current.isEmpty else {
            resetBaseline()
            return [:]
        }

        let timestamp = clock()
        defer {
            previousCounts = current
            previousTimestamp = timestamp
        }

        guard let previousCounts, let previousTimestamp else {
            return current.mapValues { _ in .zero }
        }

        let elapsed = timestamp.timeIntervalSince(previousTimestamp)
        guard elapsed > 0 else {
            return current.mapValues { _ in .zero }
        }

        return current.reduce(into: [:]) { speeds, entry in
            let (pid, counts) = entry
            guard let previous = previousCounts[pid] else {
                speeds[pid] = .zero
                return
            }

            let downDelta = counts.bytesIn >= previous.bytesIn
                ? counts.bytesIn - previous.bytesIn
                : 0
            let upDelta = counts.bytesOut >= previous.bytesOut
                ? counts.bytesOut - previous.bytesOut
                : 0
            speeds[pid] = ProcessNetworkSpeed(
                downBytesPerSecond: Double(downDelta) / elapsed,
                upBytesPerSecond: Double(upDelta) / elapsed
            )
        }
    }

    /// Parses the stable CSV shape emitted by `nettop -x -J bytes_in,bytes_out`.
    ///
    /// The first field is `name.pid`; using its final dot component keeps
    /// process names that contain dots intact. Bad rows are ignored rather than
    /// invalidating the rest of the sample.
    public nonisolated static func parse(_ output: String) -> [Int32: ProcessNetworkByteCounts] {
        var result: [Int32: ProcessNetworkByteCounts] = [:]

        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(
                separator: ",",
                omittingEmptySubsequences: false
            )
            guard fields.count >= 3,
                  let pidPart = fields[0].split(separator: ".").last,
                  let pid = Int32(pidPart),
                  pid > 0,
                  let bytesIn = UInt64(fields[1].trimmingCharacters(in: .whitespaces)),
                  let bytesOut = UInt64(fields[2].trimmingCharacters(in: .whitespaces))
            else { continue }

            let counts = ProcessNetworkByteCounts(bytesIn: bytesIn, bytesOut: bytesOut)
            if let existing = result[pid] {
                result[pid] = ProcessNetworkByteCounts(
                    bytesIn: existing.bytesIn &+ counts.bytesIn,
                    bytesOut: existing.bytesOut &+ counts.bytesOut
                )
            } else {
                result[pid] = counts
            }
        }

        return result
    }

    private func resetBaseline() {
        previousCounts = nil
        previousTimestamp = nil
    }

    private static func runNettop() async -> String? {
        await withCheckedContinuation { continuation in
            let result = NettopResultBox(continuation: continuation)
            DispatchQueue.global(qos: .utility).async {
                guard let executablePath = ProcessLaunchSanitizer.executablePath("/usr/bin/env") else {
                    result.resume(nil)
                    return
                }
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executablePath)
                process.arguments = ProcessLaunchSanitizer.argumentList([
                    "nettop", "-P", "-L", "1", "-x", "-J", "bytes_in,bytes_out"
                ])

                let output = Pipe()
                process.standardOutput = output
                process.standardError = FileHandle.nullDevice
                process.standardInput = FileHandle.nullDevice

                do {
                    try process.run()
                } catch {
                    result.resume(nil)
                    return
                }

                guard result.attach(process) else {
                    process.terminate()
                    return
                }

                let timeout = DispatchWorkItem {
                    result.terminateAndResume()
                }
                DispatchQueue.global(qos: .utility).asyncAfter(
                    deadline: .now() + 5,
                    execute: timeout
                )

                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                timeout.cancel()

                guard process.terminationStatus == 0 else {
                    result.resume(nil)
                    return
                }
                result.resume(String(data: data, encoding: .utf8))
            }
        }
    }
}

/// Keeps the continuation and process behind one lock so the normal exit and
/// the timeout race cannot resume twice or terminate a process that has
/// already been released.
private final class NettopResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String?, Never>?
    private var process: Process?
    private var hasResumed = false

    init(continuation: CheckedContinuation<String?, Never>) {
        self.continuation = continuation
    }

    func attach(_ process: Process) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !hasResumed else { return false }
        self.process = process
        return true
    }

    func resume(_ output: String?) {
        lock.lock()
        guard !hasResumed else {
            lock.unlock()
            return
        }
        hasResumed = true
        let continuation = self.continuation
        self.continuation = nil
        process = nil
        lock.unlock()
        continuation?.resume(returning: output)
    }

    func terminateAndResume() {
        lock.lock()
        guard !hasResumed else {
            lock.unlock()
            return
        }
        hasResumed = true
        let process = self.process
        self.process = nil
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()

        process?.terminate()
        continuation?.resume(returning: nil)
    }
}

/// Maps socket-owning helper processes back to an app row the inspector can
/// show. The walk starts at the measured PID, so a helper that is itself an
/// NSWorkspace app stays on its own row instead of rolling into its parent.
enum ProcessNetworkAttribution {
    static func resolveOwner(
        pid: Int32,
        parentPIDs: [Int32: Int32],
        appPIDs: Set<Int32>,
        maxDepth: Int = 32
    ) -> Int32? {
        guard pid > 0, maxDepth > 0 else { return nil }

        var current = pid
        var visited: Set<Int32> = []
        for _ in 0..<maxDepth {
            guard current > 0, visited.insert(current).inserted else { return nil }
            if appPIDs.contains(current) {
                return current
            }
            guard let parent = parentPIDs[current], parent != current else {
                return nil
            }
            current = parent
        }
        return nil
    }

    static func attribute(
        _ speeds: [Int32: ProcessNetworkSpeed],
        parentPIDs: [Int32: Int32],
        appPIDs: Set<Int32>,
        maxDepth: Int = 32
    ) -> [Int32: ProcessNetworkSpeed] {
        var attributed: [Int32: ProcessNetworkSpeed] = [:]

        for (pid, speed) in speeds {
            guard let owner = resolveOwner(
                pid: pid,
                parentPIDs: parentPIDs,
                appPIDs: appPIDs,
                maxDepth: maxDepth
            ) else { continue }

            let existing = attributed[owner] ?? .zero
            attributed[owner] = ProcessNetworkSpeed(
                downBytesPerSecond: existing.downBytesPerSecond + speed.downBytesPerSecond,
                upBytesPerSecond: existing.upBytesPerSecond + speed.upBytesPerSecond
            )
        }

        return attributed
    }
}
