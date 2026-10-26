// Examples/PurahNetPulsePlugin/Sources/PurahNetPulsePlugin/PurahNetPulsePlugin.swift
//
// Net Pulse — a complete external plugin built against the zero-dependency
// C-ABI in `PurahExternalPluginSDK.swift`. It is deliberately not a toy: it
// runs a real probe loop, keeps a rolling latency history on disk inside the
// sandbox the host hands it, and reproduces the built-in card anatomy
// (header / body / footer, tactile buttons, telemetry colouring).
//
// Load it with Settings → Plugins → "Dev: Load Package..." and pick this
// folder (the one containing Package.swift).

import SwiftUI
import AppKit
import Foundation

// MARK: - Model

struct LatencySample: Codable, Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    /// Round-trip time in milliseconds. `nil` means the probe failed.
    let milliseconds: Double?
    let note: String?

    init(timestamp: Date = Date(), milliseconds: Double?, note: String? = nil) {
        self.id = UUID()
        self.timestamp = timestamp
        self.milliseconds = milliseconds
        self.note = note
    }

    var isFailure: Bool { milliseconds == nil }
}

enum ProbeTarget: String, Codable, CaseIterable, Identifiable, Sendable {
    case gateway = "Gateway"
    case cloudflare = "1.1.1.1"
    case google = "8.8.8.8"
    case custom = "Custom"

    var id: String { rawValue }

    func host(customHost: String) -> String {
        switch self {
        case .gateway: return Self.defaultGateway() ?? "1.1.1.1"
        case .cloudflare: return "1.1.1.1"
        case .google: return "8.8.8.8"
        case .custom: return customHost
        }
    }

    /// The host's own default route, so "Gateway" measures the local network
    /// rather than an internet endpoint.
    static func defaultGateway() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/route")
        process.arguments = ["-n", "get", "default"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }
        for line in output.split(separator: "\n") where line.contains("gateway:") {
            return line.split(separator: ":").last?.trimmingCharacters(in: .whitespaces)
        }
        return nil
    }
}

// MARK: - State

@MainActor
final class NetPulseState: ObservableObject {
    static let shared = NetPulseState()

    // Config
    @Published var target: ProbeTarget = .cloudflare {
        didSet { persistConfig() }
    }
    @Published var customHost: String = "example.com" {
        didSet { persistConfig() }
    }
    @Published var intervalSeconds: Double = 5.0 {
        didSet {
            persistConfig()
            restartLoopIfRunning()
        }
    }
    @Published var timeoutMilliseconds: Int = 1000 {
        didSet { persistConfig() }
    }

    // Live data
    @Published private(set) var samples: [LatencySample] = []
    @Published private(set) var isProbing: Bool = false

    private var loopTask: Task<Void, Never>?
    private var storagePath: String?
    private let historyLimit = 240

    private init() {}

    // MARK: Derived metrics

    private var recentSuccessful: [Double] {
        samples.compactMap(\.milliseconds).suffix(60).map { $0 }
    }

    var latest: LatencySample? { samples.first }

    var latestMilliseconds: Double? { latest?.milliseconds }

    var average: Double? {
        let values = recentSuccessful
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    var minimum: Double? { recentSuccessful.min() }
    var maximum: Double? { recentSuccessful.max() }

    /// Mean absolute difference between consecutive probes — the number that
    /// actually predicts whether a video call will stutter.
    var jitter: Double? {
        let values = recentSuccessful
        guard values.count >= 2 else { return nil }
        var total = 0.0
        for index in 1..<values.count {
            total += abs(values[index] - values[index - 1])
        }
        return total / Double(values.count - 1)
    }

    var failureCount: Int { samples.prefix(60).filter(\.isFailure).count }

    var healthColor: Color {
        guard let latestMilliseconds else {
            return samples.isEmpty ? Color.secondary : Color(red: 1.0, green: 0.27, blue: 0.23)
        }
        switch latestMilliseconds {
        case ..<50: return Color(red: 0.19, green: 0.82, blue: 0.35)
        case ..<120: return Color(red: 1.0, green: 0.72, blue: 0.10)
        default: return Color(red: 1.0, green: 0.27, blue: 0.23)
        }
    }

    var healthLabel: String {
        guard let latestMilliseconds else {
            return samples.isEmpty ? "idle" : "offline"
        }
        switch latestMilliseconds {
        case ..<50: return "fast"
        case ..<120: return "ok"
        default: return "slow"
        }
    }

    private var accent: Color { Color(red: 0.0, green: 0.78, blue: 0.94) }

    // MARK: Lifetime

    /// Called from every view factory so the plugin works no matter which
    /// view the host happens to build first.
    func bind(storageDirectoryPath: String) {
        if storagePath != storageDirectoryPath {
            storagePath = storageDirectoryPath
            loadFromDisk()
        }
        startLoopIfNeeded()
    }

    private var historyURL: URL? {
        guard let storagePath else { return nil }
        return URL(fileURLWithPath: storagePath).appendingPathComponent("netpulse-history.json")
    }

    private var configURL: URL? {
        guard let storagePath else { return nil }
        return URL(fileURLWithPath: storagePath).appendingPathComponent("netpulse-config.json")
    }

    private struct Config: Codable {
        var target: ProbeTarget
        var customHost: String
        var intervalSeconds: Double
        var timeoutMilliseconds: Int
    }

    private func loadFromDisk() {
        if let configURL,
           let data = try? Data(contentsOf: configURL),
           let decoded = try? JSONDecoder().decode(Config.self, from: data) {
            target = decoded.target
            customHost = decoded.customHost
            intervalSeconds = min(max(decoded.intervalSeconds, 1.0), 60.0)
            timeoutMilliseconds = min(max(decoded.timeoutMilliseconds, 200), 5000)
        }
        if let historyURL,
           let data = try? Data(contentsOf: historyURL),
           let decoded = try? JSONDecoder().decode([LatencySample].self, from: data) {
            samples = Array(decoded.prefix(historyLimit))
        }
    }

    private func persistConfig() {
        guard let configURL else { return }
        let config = Config(
            target: target,
            customHost: customHost,
            intervalSeconds: intervalSeconds,
            timeoutMilliseconds: timeoutMilliseconds
        )
        guard let data = try? JSONEncoder().encode(config) else { return }
        try? data.write(to: configURL, options: .atomic)
    }

    private func persistHistory() {
        guard let historyURL else { return }
        guard let data = try? JSONEncoder().encode(Array(samples.prefix(historyLimit))) else { return }
        try? data.write(to: historyURL, options: .atomic)
    }

    private func restartLoopIfRunning() {
        loopTask?.cancel()
        loopTask = nil
        startLoopIfNeeded()
    }

    private func startLoopIfNeeded() {
        guard loopTask == nil else { return }
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.probeOnce()
                let interval = self.intervalSeconds
                try? await Task.sleep(nanoseconds: UInt64(max(interval, 1.0) * 1_000_000_000))
            }
        }
    }

    func stopLoop() {
        loopTask?.cancel()
        loopTask = nil
    }

    // MARK: Probing

    func probeOnce() async {
        guard !isProbing else { return }
        isProbing = true
        defer { isProbing = false }

        let host = target.host(customHost: customHost)
        guard !host.isEmpty else {
            record(LatencySample(milliseconds: nil, note: "no host"))
            return
        }
        let timeout = timeoutMilliseconds
        let result = await Self.ping(host: host, timeoutMilliseconds: timeout)
        record(result)
    }

    private func record(_ sample: LatencySample) {
        samples.insert(sample, at: 0)
        if samples.count > historyLimit {
            samples = Array(samples.prefix(historyLimit))
        }
        persistHistory()
    }

    /// `/sbin/ping -c 1` and read `time=… ms` out of the reply line.
    nonisolated private static func ping(host: String, timeoutMilliseconds: Int) async -> LatencySample {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/sbin/ping")
                process.arguments = ["-c", "1", "-n", "-W", "\(timeoutMilliseconds)", host]

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: LatencySample(milliseconds: nil, note: "ping unavailable"))
                    return
                }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                let output = String(data: data, encoding: .utf8) ?? ""
                if let milliseconds = parseMilliseconds(from: output) {
                    continuation.resume(returning: LatencySample(milliseconds: milliseconds))
                } else {
                    let note = process.terminationStatus == 0 ? "no reply" : "timeout"
                    continuation.resume(returning: LatencySample(milliseconds: nil, note: note))
                }
            }
        }
    }

    /// Parses the first `time=12.3 ms` in a ping reply.
    nonisolated static func parseMilliseconds(from output: String) -> Double? {
        guard let range = output.range(of: "time=") else { return nil }
        let tail = output[range.upperBound...]
        let numeric = tail.prefix { $0.isNumber || $0 == "." }
        return Double(numeric)
    }
}

// MARK: - Sparkline

/// Hand-drawn latency trace. No host component is available to an external
/// plugin, so it draws its own — and honours Reduce Motion by dropping the
/// shimmering head dot.
struct LatencySparkline: View {
    let samples: [LatencySample]
    let accent: Color

    private var ceiling: Double {
        max(samples.compactMap(\.milliseconds).max() ?? 100, 40) * 1.15
    }

    var body: some View {
        GeometryReader { geo in
            let ordered = Array(samples.reversed())
            if ordered.isEmpty {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.04))
                    .overlay(
                        Text("Waiting for first probe…")
                            .font(.system(size: 9.5))
                            .foregroundColor(.secondary)
                    )
            } else {
                let stepX = ordered.count > 1
                    ? geo.size.width / CGFloat(ordered.count - 1)
                    : geo.size.width

                ZStack(alignment: .bottomLeading) {
                    // Failure bands make packet loss visible at a glance.
                    ForEach(Array(ordered.enumerated()), id: \.element.id) { index, sample in
                        if sample.isFailure {
                            Rectangle()
                                .fill(Color.red.opacity(0.16))
                                .frame(width: max(stepX, 1.5), height: geo.size.height)
                                .offset(x: CGFloat(index) * stepX)
                        }
                    }

                    Path { path in
                        var started = false
                        for (index, sample) in ordered.enumerated() {
                            guard let milliseconds = sample.milliseconds else {
                                started = false
                                continue
                            }
                            let x = CGFloat(index) * stepX
                            let ratio = min(milliseconds / ceiling, 1.0)
                            let y = geo.size.height - CGFloat(ratio) * (geo.size.height - 6) - 3
                            if started {
                                path.addLine(to: CGPoint(x: x, y: y))
                            } else {
                                path.move(to: CGPoint(x: x, y: y))
                                started = true
                            }
                        }
                    }
                    .stroke(accent, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .background(Color.primary.opacity(0.035))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.6)
        )
    }
}

// MARK: - Rail Bar

struct NetPulseRailView: View {
    @ObservedObject private var state = NetPulseState.shared
    let context: PurahExternalContext?

    private var accent: Color { state.healthColor }

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: state.failureCount > 0 ? "wifi.exclamationmark" : "wifi")
                .font(.system(size: 7.5, weight: .bold))
                .foregroundColor(.white.opacity(0.95))

            if let milliseconds = state.latestMilliseconds {
                Text("\(Int(milliseconds.rounded()))")
                    .font(.system(size: 7, weight: .heavy, design: .monospaced))
                    .foregroundColor(.white)
            }
        }
        .frame(
            width: max(CGFloat(context?.railWidth ?? 8.0), 6),
            height: max(CGFloat(context?.slotHeight ?? 60.0), 24)
        )
        .background(accent.opacity(0.9))
        .clipShape(Capsule())
    }
}

// MARK: - Drawer

struct NetPulseDrawerView: View {
    @ObservedObject private var state = NetPulseState.shared
    let context: PurahExternalContext?

    private var accent: Color { state.healthColor }
    private var drawerWidth: CGFloat { CGFloat(context?.drawerWidth ?? 300.0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Right rail = card extends leftward, so the text hugs the rail side.
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(state.latestMilliseconds.map { "\(Int($0.rounded()))" } ?? "—")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundColor(accent)
                Text("ms")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 1) {
                    Text(state.target.rawValue)
                        .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Text(state.healthLabel.uppercased())
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundColor(accent)
                }
            }

            LatencySparkline(samples: Array(state.samples.prefix(90)), accent: accent)
                .frame(maxWidth: .infinity, minHeight: 46, maxHeight: .infinity)

            HStack(spacing: 6) {
                metricCell("min", state.minimum)
                metricCell("avg", state.average)
                metricCell("max", state.maximum)
                metricCell("jit", state.jitter)
            }

            HStack(spacing: 6) {
                if let latest = state.latest {
                    Text(latest.timestamp.formatted(date: .omitted, time: .standard))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                    if let note = latest.note {
                        Text("· \(note)")
                            .font(.system(size: 9))
                            .foregroundColor(.red.opacity(0.85))
                    }
                    if state.failureCount > 0 {
                        Text("· \(state.failureCount) lost")
                            .font(.system(size: 9))
                            .foregroundColor(.red.opacity(0.85))
                    }
                } else {
                    Text("Probing \(state.target.host(customHost: state.customHost))…")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: 4)

                Button {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                    Task { await state.probeOnce() }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 8.5, weight: .bold))
                        Text("Probe")
                            .font(.system(size: 9.5, weight: .semibold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(accent.opacity(0.16))
                    .foregroundColor(accent)
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)
                .disabled(state.isProbing)
            }
        }
        .padding(.horizontal, 2)
        .frame(width: max(drawerWidth - 20, 180), alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func metricCell(_ label: String, _ value: Double?) -> some View {
        VStack(spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: 7, weight: .bold))
                .foregroundColor(.secondary)
            Text(value.map { "\(Int($0.rounded()))" } ?? "—")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(5)
    }
}

// MARK: - Settings

struct NetPulseSettingsView: View {
    @ObservedObject private var state = NetPulseState.shared
    private let pluginId = "com.example.netpulse"
    private let accent = Color(red: 0.0, green: 0.78, blue: 0.94)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: "wifi")
                    .foregroundColor(accent)
                    .font(.system(size: 13, weight: .bold))
                Text("Net Pulse")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(state.healthLabel.uppercased())
                    .font(.system(size: 8, weight: .heavy, design: .monospaced))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(state.healthColor.opacity(0.16))
                    .foregroundColor(state.healthColor)
                    .cornerRadius(3)
            }

            Divider()

            VStack(alignment: .leading, spacing: 5) {
                Text("Probe target")
                    .font(.system(size: 10.5, weight: .medium))
                Picker("", selection: $state.target) {
                    ForEach(ProbeTarget.allCases) { target in
                        Text(target.rawValue).tag(target)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if state.target == .custom {
                    TextField("host or IP", text: $state.customHost)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                }
            }

            HStack {
                Text("Interval")
                    .font(.system(size: 10.5, weight: .medium))
                Spacer()
                Text("\(Int(state.intervalSeconds))s")
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .foregroundColor(accent)
            }
            Slider(value: $state.intervalSeconds, in: 1...30, step: 1)

            HStack {
                Text("Timeout")
                    .font(.system(size: 10.5, weight: .medium))
                Spacer()
                Text("\(state.timeoutMilliseconds)ms")
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .foregroundColor(accent)
            }
            Slider(
                value: Binding(
                    get: { Double(state.timeoutMilliseconds) },
                    set: { state.timeoutMilliseconds = Int($0) }
                ),
                in: 200...3000,
                step: 100
            )

            Divider()

            HStack(spacing: 8) {
                Button {
                    PurahHostBridge.shared.showToast(
                        pluginId: pluginId,
                        message: "Avg \(state.average.map { "\(Int($0.rounded()))ms" } ?? "—"), jitter \(state.jitter.map { "\(Int($0.rounded()))ms" } ?? "—")"
                    )
                    PurahHostBridge.shared.performHaptic(pluginId: pluginId, type: "levelChange")
                } label: {
                    Label("Test Host Toast", systemImage: "sparkles")
                        .font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(.plain)

                Button {
                    PurahHostBridge.shared.togglePin(pluginId: pluginId)
                } label: {
                    Label("Toggle Pin", systemImage: "pin")
                        .font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(.plain)

                Spacer()
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(minWidth: 300, minHeight: 330)
    }
}

// MARK: - Header slots

struct NetPulseHeaderAccessoryView: View {
    @ObservedObject private var state = NetPulseState.shared

    var body: some View {
        Text(state.latestMilliseconds.map { "\(Int($0.rounded()))ms" } ?? "—")
            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(state.healthColor.opacity(0.18))
            .foregroundColor(state.healthColor)
            .cornerRadius(3)
    }
}

struct NetPulseHeaderTrailingView: View {
    @ObservedObject private var state = NetPulseState.shared
    private let pluginId = "com.example.netpulse"

    var body: some View {
        Button {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            Task { await state.probeOnce() }
        } label: {
            HStack(spacing: 2) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 8, weight: .bold))
                Text("\(Int(state.intervalSeconds))s")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
            }
            .padding(.horizontal, 4.5)
            .padding(.vertical, 1.5)
            .background(Color(red: 0.0, green: 0.78, blue: 0.94).opacity(0.16))
            .foregroundColor(Color(red: 0.0, green: 0.78, blue: 0.94))
            .cornerRadius(3.5)
        }
        .buttonStyle(.plain)
        .help("Probe now")
    }
}

// MARK: - ABI

private let manifestJSON = """
{
    "id": "com.example.netpulse",
    "displayName": "Net Pulse",
    "systemIcon": "wifi",
    "author": "Purah Community",
    "version": "1.0.0",
    "description": "Live network latency, jitter, and packet-loss trace along your bezel.",
    "defaultEdge": "right",
    "preferredZone": "glance",
    "ergonomicWeight": 28.0,
    "minLengthRatio": 0.14,
    "defaultColorHex": "#00C7F0",
    "defaultDrawerWidth": 300.0,
    "category": "Lightweight",
    "permissions": ["Shell Execution"],
    "tags": ["network", "latency", "ping", "jitter", "diagnostics"],
    "isCommunity": true
}
"""

@_cdecl("purahPluginABIVersion")
public func purahPluginABIVersion() -> UnsafePointer<CChar> {
    ("1" as NSString).utf8String!
}

@_cdecl("purahPluginManifestJSON")
public func purahPluginManifestJSON() -> UnsafePointer<CChar> {
    (manifestJSON as NSString).utf8String!
}

@MainActor
@_cdecl("purahCreateRailViewWithContext")
public func purahCreateRailViewWithContext(contextJSON: UnsafePointer<CChar>) -> UnsafeMutableRawPointer {
    let context = PurahExternalContext.decode(from: contextJSON)
    if let path = context?.storageDirectoryPath {
        NetPulseState.shared.bind(storageDirectoryPath: path)
    }
    return PurahViewHost.retain(NetPulseRailView(context: context))
}

@MainActor
@_cdecl("purahCreateDrawerViewWithContext")
public func purahCreateDrawerViewWithContext(contextJSON: UnsafePointer<CChar>) -> UnsafeMutableRawPointer {
    let context = PurahExternalContext.decode(from: contextJSON)
    if let path = context?.storageDirectoryPath {
        NetPulseState.shared.bind(storageDirectoryPath: path)
    }
    return PurahViewHost.retain(NetPulseDrawerView(context: context))
}

@MainActor
@_cdecl("purahCreateSettingsViewWithContext")
public func purahCreateSettingsViewWithContext(contextJSON: UnsafePointer<CChar>) -> UnsafeMutableRawPointer {
    let context = PurahExternalContext.decode(from: contextJSON)
    if let path = context?.storageDirectoryPath {
        NetPulseState.shared.bind(storageDirectoryPath: path)
    }
    return PurahViewHost.retain(NetPulseSettingsView())
}

@MainActor
@_cdecl("purahCreateHeaderAccessoryView")
public func purahCreateHeaderAccessoryView() -> UnsafeMutableRawPointer {
    PurahViewHost.retain(NetPulseHeaderAccessoryView())
}

@MainActor
@_cdecl("purahCreateHeaderTrailingView")
public func purahCreateHeaderTrailingView() -> UnsafeMutableRawPointer {
    PurahViewHost.retain(NetPulseHeaderTrailingView())
}

@MainActor
@_cdecl("purahOnRailBarTap")
public func purahOnRailBarTap() {
    Task { await NetPulseState.shared.probeOnce() }
}

@MainActor
@_cdecl("purahOnMount")
public func purahOnMount() {
    // Nothing to do: the first view factory starts the probe loop.
}

@MainActor
@_cdecl("purahOnUnmount")
public func purahOnUnmount() {
    NetPulseState.shared.stopLoop()
}
