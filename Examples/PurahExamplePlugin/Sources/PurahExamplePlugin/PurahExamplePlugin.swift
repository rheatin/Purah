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
    "isCommunity": true
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
