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
        PurahExternalSettingsCard(
            title: "Zen Counter Configuration",
            subtitle: "Configure target cycles and step increments",
            icon: "flame.fill",
            iconColor: accentColor
        ) {
            VStack(alignment: .leading, spacing: 12) {
                PurahExternalSettingStepperRow(
                    title: "Daily Target Goal",
                    subtitle: "Cycles required to achieve daily focus",
                    badgeText: "\(state.targetGoal) cycles",
                    value: Binding(
                        get: { Double(state.targetGoal) },
                        set: { state.targetGoal = Int($0) }
                    ),
                    range: 1...100,
                    step: 1
                )

                PurahExternalSettingStepperRow(
                    title: "Increment Step Size",
                    subtitle: "Amount added per focus cycle completion",
                    badgeText: "+\(state.stepSize)",
                    value: Binding(
                        get: { Double(state.stepSize) },
                        set: { state.stepSize = Int($0) }
                    ),
                    range: 1...10,
                    step: 1
                )

                Divider()

                PurahExternalSettingActionRow(
                    title: "Host Toast Notification",
                    subtitle: "Test Purah HostBridge toast action",
                    buttonTitle: "Test Toast",
                    systemIcon: "sparkles",
                    role: "accent"
                ) {
                    PurahHostBridge.shared.showToast(pluginId: pluginId, message: "Target goal: \(state.targetGoal) cycles")
                    PurahHostBridge.shared.performHaptic(pluginId: pluginId, type: "levelChange")
                }

                PurahExternalSettingActionRow(
                    title: "Toggle Drawer Pin",
                    subtitle: "Pin or unpin this drawer card on screen",
                    buttonTitle: "Toggle Pin",
                    systemIcon: "pin.fill"
                ) {
                    PurahHostBridge.shared.togglePin(pluginId: pluginId)
                }
            }
        }
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
    "defaultDecomposed": true,
    "pollingInterval": 5.0
}
"""

@_cdecl("purahPluginManifestJSON")
public func purahPluginManifestJSON() -> UnsafePointer<CChar> {
    return (manifestJSON as NSString).utf8String!
}

/// Composite rail bar state: Purah owns the 8pt edge bar and renders a vertical
/// gauge fill from this JSON descriptor. Plugins never return an `NSView` for the rail.
@MainActor
@_cdecl("purahRailBarStateJSON")
public func purahRailBarStateJSON(contextJSON: UnsafePointer<CChar>) -> UnsafePointer<CChar>? {
    _ = PurahExternalContext.decode(from: contextJSON)
    let state = ZenCounterState.shared
    let ratio = Double(state.count) / Double(max(state.targetGoal, 1))
    return PurahExternalRailBarState(
        style: "gauge",
        ratio: min(max(ratio, 0.0), 1.0),
        minimumVisibleFill: 4.0,
        accessibilityValueLabel: "\(state.count) of \(state.targetGoal) cycles"
    ).toCString()
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
@_cdecl("purahHeaderAccessoryJSON")
public func purahHeaderAccessoryJSON(contextJSON: UnsafePointer<CChar>) -> UnsafePointer<CChar>? {
    _ = PurahExternalContext.decode(from: contextJSON)
    let state = ZenCounterState.shared
    return PurahExternalHeaderAccessory.badge("\(state.count) ZEN", colorHex: "#FF6B6B").toCString()
}

@MainActor
@_cdecl("purahHeaderTrailingItemsJSON")
public func purahHeaderTrailingItemsJSON(contextJSON: UnsafePointer<CChar>) -> UnsafePointer<CChar>? {
    _ = PurahExternalContext.decode(from: contextJSON)
    let state = ZenCounterState.shared
    let items = [
        PurahExternalHeaderTrailingItem.button(
            id: "increment",
            systemIcon: "plus",
            help: "Quick increment +\(state.stepSize)",
            colorHex: "#FF6B6B"
        )
    ]
    return PurahExternalHeaderTrailingItem.encodeListToCString(items)
}

@MainActor
@_cdecl("purahOnHeaderAction")
public func purahOnHeaderAction(
    contextJSON: UnsafePointer<CChar>,
    actionIdPtr: UnsafePointer<CChar>
) {
    let actionId = String(cString: actionIdPtr)
    if actionId == "increment" {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        ZenCounterState.shared.increment()
    }
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
// individual rail chips. Purah owns the 8pt chip bars AND the expanded
// single-row card chrome (icon block, title, badge, subtitle, gear/pin).
// The plugin contributes an inline row accessory button and optional
// progressive-disclosure body content when the chip is stretched tall.

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

    let items = ZenSessions.all.map { session in
        PurahExternalSubItem(
            id: "com.example.focus-\(session.id)",
            title: session.title,
            subtitle: "\(session.minutes) min session",
            systemIcon: "timer",
            badge: "\(session.minutes)m",
            state: "normal",
            gaugeRatio: Double(session.minutes) / 50.0,
            gaugeStyle: "solid"
        )
    }
    return PurahExternalSubItem.encodeListToCString(items)
}

@MainActor
@_cdecl("purahDecomposedPolicyJSON")
public func purahDecomposedPolicyJSON(contextJSON: UnsafePointer<CChar>) -> UnsafePointer<CChar>? {
    _ = PurahExternalContext.decode(from: contextJSON)

    return PurahExternalDecomposedPolicy(
        maxRailItems: 3,
        minChipHeight: 56.0,
        maxChipHeight: 185.0,
        spacing: 2.5,
        overflowStrategy: "smartFold"
    ).toCString()
}

/// Inline row accessory placed inside the host's single-row stepped card,
/// immediately to the left of the host's gear/pin tools.
@MainActor
@_cdecl("purahCreateSteppedRowAccessoryWithContext")
public func purahCreateSteppedRowAccessoryWithContext(
    contextJSON: UnsafePointer<CChar>,
    subItemId: UnsafePointer<CChar>
) -> UnsafeMutableRawPointer? {
    _ = PurahExternalContext.decode(from: contextJSON)
    let id = String(cString: subItemId)
    guard let session = ZenSessions.session(for: id) else { return nil }
    return PurahViewHost.retain(ZenSessionRowAccessoryView(session: session))
}

/// Progressive-disclosure body content rendered below the host's stepped row
/// ONLY when the chip is stretched tall (`bodyHeight >= 48pt`). Never repeat
/// the chip's icon, title, or badge here — the host row already draws them.
@MainActor
@_cdecl("purahCreateSteppedDrawerContentWithContext")
public func purahCreateSteppedDrawerContentWithContext(
    contextJSON: UnsafePointer<CChar>,
    subItemId: UnsafePointer<CChar>
) -> UnsafeMutableRawPointer? {
    _ = PurahExternalContext.decode(from: contextJSON)
    let id = String(cString: subItemId)
    guard let session = ZenSessions.session(for: id) else { return nil }
    return PurahViewHost.retain(ZenSessionBodyView(session: session))
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

struct ZenSessionRowAccessoryView: View {
    let session: ZenSession
    private let accentColor = Color(red: 1.0, green: 0.42, blue: 0.42)

    var body: some View {
        Button {
            ZenCounterState.shared.startSession(session)
            ZenCounterState.shared.increment()
            PurahHostBridge.shared.performHaptic(pluginId: "com.example.focus", type: "alignment")
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "play.fill")
                    .font(.system(size: 8, weight: .bold))
                Text("Start")
                    .font(.system(size: 9.5, weight: .semibold))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(accentColor.opacity(0.18)))
            .foregroundColor(accentColor)
        }
        .buttonStyle(.plain)
    }
}

struct ZenSessionBodyView: View {
    let session: ZenSession

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Focus for \(session.minutes) minutes without context switching.")
                .font(.system(size: 10.5))
                .foregroundColor(.secondary)
                .lineLimit(2)

            Spacer(minLength: 0)
        }
        .padding(.top, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
