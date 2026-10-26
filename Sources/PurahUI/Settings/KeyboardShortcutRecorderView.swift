// Sources/PurahUI/Settings/KeyboardShortcutRecorderView.swift
import SwiftUI
import AppKit
import Carbon
import PurahCore

public enum HotKeyTarget: Sendable {
    case freeze
    case sculptor
}

@MainActor
@Observable
public final class ShortcutRecorderState {
    public var isRecording: Bool = false
    public var pulseOutline: Bool = false
    public var target: HotKeyTarget
    private var localMonitor: Any? = nil

    public init(target: HotKeyTarget = .freeze) {
        self.target = target
    }

    public func startRecording(store: PurahWorkspaceStore) {
        isRecording = true
        pulseOutline = true
        stopLocalMonitor()
        guard !PurahWorkspaceStore.isTestingEnvironment else { return }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak store] event in
            guard let self = self, let store = store else { return event }
            return self.handleKeyDown(event, store: store)
        }
    }

    public func stopRecording() {
        isRecording = false
        pulseOutline = false
        stopLocalMonitor()
    }

    public func stopLocalMonitor() {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    @discardableResult
    public func handleKeyDown(_ event: NSEvent, store: PurahWorkspaceStore) -> NSEvent? {
        guard isRecording else { return event }

        // Escape (keyCode 53) cancels recording and retains previous shortcut
        if event.keyCode == 53 {
            stopRecording()
            return nil
        }

        let carbonMods = KeyboardShortcutRecorderView.carbonModifiers(from: event.modifierFlags)
        let isFn = KeyboardShortcutRecorderView.isFunctionKey(keyCode: event.keyCode)

        // Validation: Must contain at least one modifier unless it's a function key
        guard carbonMods != 0 || isFn else {
            return nil
        }

        let shortcut = HotKeyShortcut(keyCode: UInt32(event.keyCode), modifiers: carbonMods)
        applyShortcut(shortcut, store: store)
        stopRecording()
        return nil
    }

    public func applyShortcut(_ shortcut: HotKeyShortcut, store: PurahWorkspaceStore) {
        switch target {
        case .freeze:
            store.hotKeyShortcut = shortcut
            store.savePersistentState()
            GlobalHotKeyManager.shared.register(shortcut: shortcut)
        case .sculptor:
            store.sculptorHotKeyShortcut = shortcut
            store.savePersistentState()
            GlobalHotKeyManager.shared.registerSculptor(shortcut: shortcut)
        }
    }

    public func resetToDefault(store: PurahWorkspaceStore) {
        if isRecording {
            stopRecording()
        }
        switch target {
        case .freeze:
            applyShortcut(.defaultShortcut, store: store)
        case .sculptor:
            applyShortcut(.defaultSculptorShortcut, store: store)
        }
    }
}

@MainActor
public struct KeyboardShortcutRecorderView: View {
    public let store: PurahWorkspaceStore
    public let target: HotKeyTarget
    @State public var state: ShortcutRecorderState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public var isRecording: Bool {
        state.isRecording
    }

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    private var currentShortcut: HotKeyShortcut {
        switch target {
        case .freeze:
            return store.hotKeyShortcut
        case .sculptor:
            return store.sculptorHotKeyShortcut
        }
    }

    private var defaultShortcut: HotKeyShortcut {
        switch target {
        case .freeze:
            return .defaultShortcut
        case .sculptor:
            return .defaultSculptorShortcut
        }
    }

    private var titleText: String {
        switch target {
        case .freeze:
            return "interaction.hotkeys.freeze.title".localized
        case .sculptor:
            return "interaction.hotkeys.sculptor.title".localized
        }
    }

    private var subtitleText: String {
        if state.isRecording {
            return "interaction.hotkeys.recordingSubtitle".localized
        }
        switch target {
        case .freeze:
            return "interaction.hotkeys.freeze.subtitle".localized
        case .sculptor:
            return "interaction.hotkeys.sculptor.subtitle".localized
        }
    }

    private var iconName: String {
        switch target {
        case .freeze:
            return "command"
        case .sculptor:
            return "viewfinder.rectangular"
        }
    }

    public init(store: PurahWorkspaceStore, state: ShortcutRecorderState = ShortcutRecorderState()) {
        self.store = store
        self.target = state.target
        self._state = State(initialValue: state)
    }

    public init(store: PurahWorkspaceStore, target: HotKeyTarget) {
        self.store = store
        self.target = target
        self._state = State(initialValue: ShortcutRecorderState(target: target))
    }

    public var body: some View {
        HStack(spacing: 14) {
            // Hotkey label and state description
            VStack(alignment: .leading, spacing: 2) {
                Text(titleText)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(palette.style == .native ? Color.primary : .white)
                Text(subtitleText)
                    .font(.caption2)
                    .foregroundColor(state.isRecording ? palette.primaryAccent : .secondary)
            }

            Spacer()

            // Recording Button / Idle Badge
            Button {
                if state.isRecording {
                    stopRecording()
                } else {
                    startRecording()
                }
            } label: {
                HStack(spacing: 6) {
                    if state.isRecording {
                        Circle()
                            .fill(palette.primaryAccent)
                            .frame(width: 8, height: 8)
                            .opacity(state.pulseOutline ? 1.0 : 0.2)
                        Text("interaction.hotkeys.recordingPrompt".localized)
                            .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                            .foregroundColor(palette.primaryAccent)
                    } else {
                        Image(systemName: iconName)
                            .font(.caption)
                            .foregroundColor(palette.primaryAccent)
                        Text(currentShortcut.displayString)
                            .font(.system(.subheadline, design: .monospaced).weight(.bold))
                            .foregroundColor(palette.style == .native ? Color.primary : .white)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    state.isRecording
                        ? palette.primaryAccent.opacity(0.12)
                        : palette.surfaceBackground
                )
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            state.isRecording
                                ? palette.primaryAccent.opacity(state.pulseOutline ? 1.0 : 0.35)
                                : palette.borderColor.opacity(0.5),
                            lineWidth: state.isRecording ? 1.5 : 1.0
                        )
                )
                .modifier(OptionalGlow(color: palette.primaryAccent, enabled: state.isRecording && palette.useGlow))
            }
            .buttonStyle(.tactile)

            // Reset to Default button
            if currentShortcut != defaultShortcut {
                Button {
                    resetToDefault()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.caption2)
                        Text("\("interaction.hotkeys.resetToDefault".localized) (\(defaultShortcut.displayString))")
                            .font(.caption.weight(.medium))
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(palette.borderColor.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.tactile)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .onAppear {
            if state.isRecording {
                state.pulseOutline = true
            }
        }
        .onDisappear {
            stopRecording()
        }
        .onChange(of: state.isRecording) { _, newValue in
            guard PurahMotionPolicy.allowsAmbientAnimation(reduceMotion: reduceMotion) else {
                state.pulseOutline = newValue
                return
            }
            if newValue {
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                    state.pulseOutline = true
                }
            } else {
                withAnimation(.default) {
                    state.pulseOutline = false
                }
            }
        }
    }

    public func startRecording() {
        state.startRecording(store: store)
    }

    public func stopRecording() {
        state.stopRecording()
    }

    @discardableResult
    public func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        state.handleKeyDown(event, store: store)
    }

    public func applyShortcut(_ shortcut: HotKeyShortcut) {
        state.applyShortcut(shortcut, store: store)
    }

    public func resetToDefault() {
        state.resetToDefault(store: store)
    }

    public static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.control) { mods |= 0x1000 }
        if flags.contains(.option) { mods |= 0x0800 }
        if flags.contains(.shift) { mods |= 0x0200 }
        if flags.contains(.command) { mods |= 0x0100 }
        return mods
    }

    public static func isFunctionKey(keyCode: UInt16) -> Bool {
        let functionKeyCodes: Set<UInt16> = [
            122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111
        ]
        return functionKeyCodes.contains(keyCode)
    }
}

@MainActor
public struct SculptorShortcutRecorderView: View {
    public let store: PurahWorkspaceStore

    public init(store: PurahWorkspaceStore) {
        self.store = store
    }

    public var body: some View {
        KeyboardShortcutRecorderView(store: store, target: .sculptor)
    }
}
