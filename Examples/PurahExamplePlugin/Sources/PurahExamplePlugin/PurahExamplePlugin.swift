// Examples/PurahExamplePlugin/Sources/PurahExamplePlugin/PurahExamplePlugin.swift
import SwiftUI
import AppKit

// MARK: - State Container
@MainActor
final class ZenCounterState: ObservableObject {
    static let shared = ZenCounterState()

    @Published var count: Int = 0
    @Published var targetGoal: Int = 10 {
        didSet {
            UserDefaults.standard.set(targetGoal, forKey: "purah.plugin.com.example.focus.targetGoal")
        }
    }
    @Published var stepSize: Int = 1 {
        didSet {
            UserDefaults.standard.set(stepSize, forKey: "purah.plugin.com.example.focus.stepSize")
        }
    }
    /// Evidence that the host-driven polling path is alive; shown in settings.
    @Published var pollTickCount: Int = 0
    @Published var activeSessionTitle: String?

    func notePollTick() {
        pollTickCount += 1
    }

    func noteContext(_ context: PurahExternalContext, for view: NSView) {
        // A real plugin would re-render from these values. The example only
        // proves the payload arrives with the fields it expects.
        _ = context.isExpanded
        _ = context.visibleSubItemIds
        _ = view
    }

    func startSession(_ session: ZenSession) {
        activeSessionTitle = session.title
    }

    init() {
        self.count = UserDefaults.standard.integer(forKey: "purah.plugin.com.example.focus.currentCount")
        let savedGoal = UserDefaults.standard.integer(forKey: "purah.plugin.com.example.focus.targetGoal")
        self.targetGoal = savedGoal > 0 ? savedGoal : 10
        let savedStep = UserDefaults.standard.integer(forKey: "purah.plugin.com.example.focus.stepSize")
        self.stepSize = savedStep > 0 ? savedStep : 1
    }

    func increment() {
        count += stepSize
        UserDefaults.standard.set(count, forKey: "purah.plugin.com.example.focus.currentCount")
    }

    func decrement() {
        count = max(count - stepSize, 0)
        UserDefaults.standard.set(count, forKey: "purah.plugin.com.example.focus.currentCount")
    }

    func reset() {
        count = 0
        UserDefaults.standard.set(count, forKey: "purah.plugin.com.example.focus.currentCount")
    }
}

// MARK: - SwiftUI Views
struct ZenRailView: View {
    @ObservedObject private var state = ZenCounterState.shared
    private let accentColor = Color(red: 1.0, green: 0.42, blue: 0.42)

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: "flame.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(accentColor)
            Text("\(state.count)")
                .font(.system(size: 8, weight: .heavy, design: .monospaced))
                .foregroundColor(.white)
        }
        .frame(width: 8, height: 60)
        .background(accentColor.opacity(0.85))
        .clipShape(Capsule())
    }
}

struct ZenDrawerView: View {
    @ObservedObject private var state = ZenCounterState.shared
    private let accentColor = Color(red: 1.0, green: 0.42, blue: 0.42)

    var body: some View {
        VStack(spacing: 12) {
            Spacer()

            // Large Hero Counter Display
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(0.15))
                        .frame(width: 52, height: 52)
                    Image(systemName: "flame.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(accentColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(state.count)")
                            .font(.system(size: 34, weight: .heavy, design: .rounded))
                            .foregroundColor(.primary)
                        Text("/ \(state.targetGoal)")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    Text("Completed Focus Cycles")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(10)
            .background(Color.primary.opacity(0.035))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 0.6)
            )

            // Tactile Action Buttons
            HStack(spacing: 8) {
                Button {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                    state.decrement()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "minus")
                            .font(.system(size: 9, weight: .bold))
                        Text("Minus")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.12))
                    .foregroundColor(.secondary)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)

                Button {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                    state.increment()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "plus")
                            .font(.system(size: 9, weight: .bold))
                        Text("Add")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)

                Button {
                    NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
                    state.reset()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.12))
                        .foregroundColor(.secondary)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help("Reset counter to 0")
            }

            Spacer()
        }
        .padding(.horizontal, 2)
    }
}

struct ZenHeaderAccessoryView: View {
    @ObservedObject private var state = ZenCounterState.shared
    private let accentColor = Color(red: 1.0, green: 0.42, blue: 0.42)

    var body: some View {
        Text("\(state.count) ZEN")
            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(accentColor.opacity(0.18))
            .foregroundColor(accentColor)
            .cornerRadius(3)
    }
}

struct ZenHeaderTrailingView: View {
    @ObservedObject private var state = ZenCounterState.shared
    private let accentColor = Color(red: 1.0, green: 0.42, blue: 0.42)

    var body: some View {
        Button {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            state.increment()
        } label: {
            HStack(spacing: 2) {
                Image(systemName: "plus")
                    .font(.system(size: 8, weight: .bold))
                Text("\(state.stepSize)")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
            }
            .padding(.horizontal, 4.5)
            .padding(.vertical, 1.5)
            .background(accentColor.opacity(0.16))
            .foregroundColor(accentColor)
            .cornerRadius(3.5)
        }
        .buttonStyle(.plain)
        .help("Quick increment +\(state.stepSize)")
    }
}

struct ZenSettingsView: View {
    @ObservedObject private var state = ZenCounterState.shared
    private let pluginId = "com.example.focus"
    private let accentColor = Color(red: 1.0, green: 0.42, blue: 0.42)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "flame.fill")
                    .foregroundColor(accentColor)
                    .font(.system(size: 14, weight: .bold))
                Text("Zen Counter Configuration")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
            }

            Divider()

            // Daily Target Goal
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Daily Target Goal")
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                    Text("\(state.targetGoal) cycles")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(accentColor)
                }

                Stepper("", value: $state.targetGoal, in: 1...100)
                    .labelsHidden()
            }

            // Step Size
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Increment Step Size")
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                    Text("+\(state.stepSize)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(accentColor)
                }

                Stepper("", value: $state.stepSize, in: 1...10)
                    .labelsHidden()
            }

            Divider()

            // Host Actions Test Controls
            VStack(alignment: .leading, spacing: 8) {
                Text("Host SDK Bridge Actions")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    Button {
                        PurahHostBridge.shared.showToast(pluginId: pluginId, message: "Target goal saved: \(state.targetGoal) cycles")
                        PurahHostBridge.shared.performHaptic(pluginId: pluginId, type: "levelChange")
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                            Text("Test Toast")
                        }
                        .font(.system(size: 10, weight: .medium))
                    }

                    Button {
                        PurahHostBridge.shared.togglePin(pluginId: pluginId)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "pin")
                            Text("Toggle Pin")
                        }
                        .font(.system(size: 10, weight: .medium))
                    }
                }
            }

            Spacer()
        }
        .padding(14)
        .frame(minWidth: 260, minHeight: 220)
    }
}

// MARK: - ABI C Entry Points
private let manifestJSON = """
{
    "id": "com.example.focus",
    "displayName": "Zen Counter",
    "systemIcon": "flame.fill",
    "author": "Purah Community",
    "version": "1.0.0",
    "description": "Dynamic SPM example plugin: ambient habit counter & focus tracking",
    "defaultEdge": "right",
    "preferredZone": "goldenAction",
    "ergonomicWeight": 30.0,
    "minLengthRatio": 0.15,
    "defaultColorHex": "#FF6B6B",
    "defaultDrawerWidth": 290.0,
    "category": "Lightweight",
    "permissions": [],
    "tags": ["Focus", "Counter", "Ambient"],
    "isCommunity": true,
    "minimumDrawerHeight": 140.0,
    "preferredDrawerHeight": 320.0,
    "pollingInterval": 5.0
}
"""

@_cdecl("purahPluginManifestJSON")
public func purahPluginManifestJSON() -> UnsafePointer<CChar> {
    return (manifestJSON as NSString).utf8String!
}

@MainActor
@_cdecl("purahCreateRailView")
public func purahCreateRailView() -> UnsafeMutableRawPointer {
    PurahViewHost.retain(ZenRailView())
}

@MainActor
@_cdecl("purahCreateRailViewWithContext")
public func purahCreateRailViewWithContext(contextJSON: UnsafePointer<CChar>) -> UnsafeMutableRawPointer {
    _ = PurahExternalContext.decode(from: contextJSON)
    return PurahViewHost.retain(ZenRailView())
}

@MainActor
@_cdecl("purahCreateDrawerView")
public func purahCreateDrawerView() -> UnsafeMutableRawPointer {
    PurahViewHost.retain(ZenDrawerView())
}

@MainActor
@_cdecl("purahCreateDrawerViewWithContext")
public func purahCreateDrawerViewWithContext(contextJSON: UnsafePointer<CChar>) -> UnsafeMutableRawPointer {
    _ = PurahExternalContext.decode(from: contextJSON)
    return PurahViewHost.retain(ZenDrawerView())
}

@MainActor
@_cdecl("purahCreateSettingsView")
public func purahCreateSettingsView() -> UnsafeMutableRawPointer {
    PurahViewHost.retain(ZenSettingsView())
}

@MainActor
@_cdecl("purahCreateSettingsViewWithContext")
public func purahCreateSettingsViewWithContext(contextJSON: UnsafePointer<CChar>) -> UnsafeMutableRawPointer {
    _ = PurahExternalContext.decode(from: contextJSON)
    return PurahViewHost.retain(ZenSettingsView())
}

@MainActor
@_cdecl("purahCreateHeaderAccessoryView")
public func purahCreateHeaderAccessoryView() -> UnsafeMutableRawPointer {
    PurahViewHost.retain(ZenHeaderAccessoryView())
}

@MainActor
@_cdecl("purahCreateHeaderTrailingView")
public func purahCreateHeaderTrailingView() -> UnsafeMutableRawPointer {
    PurahViewHost.retain(ZenHeaderTrailingView())
}

@MainActor
@_cdecl("purahOnRailBarTap")
public func purahOnRailBarTap() {
    ZenCounterState.shared.increment()
}

@MainActor
@_cdecl("purahOnMount")
public func purahOnMount() {
    // Optional mount lifecycle hook
}

@MainActor
@_cdecl("purahOnUnmount")
public func purahOnUnmount() {
    // Optional unmount lifecycle hook
}

// MARK: - Host-driven polling & context updates
//
// The host owns the timer. It stops ticking when the pod is disabled,
// unmounted, or the rails are frozen — a plugin must never start its own
// recurring timer, or those guarantees are lost.

/// Called on the host's schedule (manifest `pollingInterval`). Must return
/// quickly; heavy work belongs on a background queue.
@MainActor
@_cdecl("purahOnPollingTick")
public func purahOnPollingTick(contextJSON: UnsafePointer<CChar>) {
    _ = PurahExternalContext.decode(from: contextJSON)
    ZenCounterState.shared.notePollTick()
}

/// Push a fresh context into a view the plugin already created. Without this
/// the factory runs once and the view never learns that the drawer opened or
/// the pod got pinned.
@MainActor
@_cdecl("purahUpdateContext")
public func purahUpdateContext(viewPtr: UnsafeMutableRawPointer, contextJSON: UnsafePointer<CChar>) {
    guard let context = PurahExternalContext.decode(from: contextJSON) else { return }
    let view = Unmanaged<NSView>.fromOpaque(viewPtr).takeUnretainedValue()
    ZenCounterState.shared.noteContext(context, for: view)
}

/// Stepped-mode rail tap with the clicked chip's identity.
///
/// Returning non-zero means "handled": the host will not add its default
/// haptic + drawer expansion. Returning zero falls back to that default.
@MainActor
@_cdecl("purahOnRailBarTapWithContext")
public func purahOnRailBarTapWithContext(
    contextJSON: UnsafePointer<CChar>,
    subItemId: UnsafePointer<CChar>
) -> Int32 {
    _ = PurahExternalContext.decode(from: contextJSON)
    let id = String(cString: subItemId)

    if let session = ZenSessions.session(for: id) {
        ZenCounterState.shared.startSession(session)
        PurahHostBridge.shared.showToast(
            pluginId: "com.example.focus",
            message: "Started \(session.title) (\(session.minutes) min)"
        )
        // Handled: a chip tap starts a session instead of opening a drawer.
        return 1
    }
    return 0
}

// MARK: - Stepped Mode (per-session chips)
//
// Demonstrates the optional stepped ABI: three focus sessions rendered as
// individual rail chips, each with its own drawer. A plugin that exports none
// of these symbols simply has no stepped mode.

struct ZenSession: Identifiable {
    let id: String
    let title: String
    let minutes: Int
}

@MainActor
enum ZenSessions {
    static let all: [ZenSession] = [
        ZenSession(id: "deep", title: "Deep Work", minutes: 50),
        ZenSession(id: "short", title: "Short Break", minutes: 5),
        ZenSession(id: "review", title: "Review", minutes: 15)
    ]

    static func session(for subItemId: String) -> ZenSession? {
        all.first { "com.example.focus-\($0.id)" == subItemId }
    }
}

@MainActor
@_cdecl("purahSteppedItemsJSON")
public func purahSteppedItemsJSON(contextJSON: UnsafePointer<CChar>) -> UnsafePointer<CChar>? {
    _ = PurahExternalContext.decode(from: contextJSON)

    let payload: [[String: Any]] = ZenSessions.all.map { session in
        [
            "id": "com.example.focus-\(session.id)",
            "title": session.title,
            "subtitle": "\(session.minutes) min",
            "systemIcon": "timer",
            "badge": "\(session.minutes)m",
            "state": "normal",
            "gaugeRatio": Double(session.minutes) / 50.0,
            "gaugeStyle": "solid"
        ]
    }

    guard let data = try? JSONSerialization.data(withJSONObject: payload),
          let json = String(data: data, encoding: .utf8) else { return nil }
    return (json as NSString).utf8String
}

@MainActor
@_cdecl("purahDecomposedPolicyJSON")
public func purahDecomposedPolicyJSON(contextJSON: UnsafePointer<CChar>) -> UnsafePointer<CChar>? {
    _ = PurahExternalContext.decode(from: contextJSON)

    let policy: [String: Any] = [
        "maxRailItems": 3,
        "minChipHeight": 56.0,
        "maxChipHeight": 185.0,
        "spacing": 2.5,
        "overflowStrategy": "smartFold"
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: policy),
          let json = String(data: data, encoding: .utf8) else { return nil }
    return (json as NSString).utf8String
}

@MainActor
@_cdecl("purahCreateSteppedDrawerViewWithContext")
public func purahCreateSteppedDrawerViewWithContext(
    contextJSON: UnsafePointer<CChar>,
    subItemId: UnsafePointer<CChar>
) -> UnsafeMutableRawPointer? {
    _ = PurahExternalContext.decode(from: contextJSON)
    let id = String(cString: subItemId)
    guard let session = ZenSessions.session(for: id) else { return nil }
    return PurahViewHost.retain(ZenSessionDrawerView(session: session))
}

/// Dynamic telemetry: the bar turns amber once the session goal is reached.
@MainActor
@_cdecl("purahDynamicBarColorHex")
public func purahDynamicBarColorHex(contextJSON: UnsafePointer<CChar>) -> UnsafePointer<CChar>? {
    _ = PurahExternalContext.decode(from: contextJSON)
    let reachedGoal = ZenCounterState.shared.count >= ZenCounterState.shared.targetGoal
    return (reachedGoal ? "#FFD166" : "#FF6B6B" as NSString).utf8String
}

/// Accent colour follows the same signal, so the drawer tint agrees with the
/// rail bar instead of the two disagreeing at the goal boundary.
@MainActor
@_cdecl("purahDynamicAccentColorHex")
public func purahDynamicAccentColorHex(contextJSON: UnsafePointer<CChar>) -> UnsafePointer<CChar>? {
    _ = PurahExternalContext.decode(from: contextJSON)
    let reachedGoal = ZenCounterState.shared.count >= ZenCounterState.shared.targetGoal
    return (reachedGoal ? "#FFD166" : "#FF6B6B" as NSString).utf8String
}

struct ZenSessionDrawerView: View {
    let session: ZenSession
    private let accentColor = Color(red: 1.0, green: 0.42, blue: 0.42)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "timer")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(accentColor)
                Text(session.title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                Spacer()
                Text("\(session.minutes)m")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Text("Focus for \(session.minutes) minutes. Chips like this one are contributed per sub-item through the stepped ABI.")
                .font(.system(size: 10.5))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
