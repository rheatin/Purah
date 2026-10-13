import SwiftUI
import AppKit
import PurahCore
import UniformTypeIdentifiers

public struct TerminalPlugin: PurahPodPlugin {
    public nonisolated let manifest = PurahPluginManifest(
        id: "terminal",
        displayName: "Terminal",
        systemIcon: "apple.terminal.fill",
        author: "Project Purah",
        version: "0.1.0",
        description: "Persistent background terminal and command shell",
        defaultEdge: .left,
        preferredZone: .goldenAction,
        ergonomicWeight: 35.0,
        minLengthRatio: 0.20,
        defaultColorHex: "#00F5D4",
        defaultDrawerWidth: 520.0,
        permissions: [.shellExecution]
    )

    public let state: TerminalPluginState

    public init(state: TerminalPluginState = TerminalPluginState()) {
        self.state = state
    }

    public func makeRailBarView(context: PurahPluginContext) -> AnyView {
        AnyView(TerminalRailBarPluginView(context: context, state: state))
    }

    public func makeDrawerView(context: PurahPluginContext) -> AnyView {
        AnyView(PersistentTerminalDrawerView(state: state, store: context.store))
    }

    public func makeHeaderAccessoryView(context: PurahPluginContext) -> AnyView? {
        AnyView(TerminalHeaderAccessoryView(state: state, color: context.accentColor))
    }

    public func makeHeaderTrailingView(context: PurahPluginContext) -> AnyView? {
        AnyView(TerminalHeaderTrailingToolbarView(state: state))
    }

    public func makeSettingsView(store: PurahWorkspaceStore) -> AnyView? {
        AnyView(TerminalPluginSettingsView(state: state, store: store))
    }

    public func onMount(store: PurahWorkspaceStore) {
        state.mount(store: store)
    }

    public func onUnmount(store: PurahWorkspaceStore) {
        state.unmount(store: store)
    }

    public func minimumDrawerHeight(store: PurahWorkspaceStore) -> CGFloat {
        60.0
    }

    public func adaptiveDrawerWidth(store: PurahWorkspaceStore) -> CGFloat? {
        520.0
    }

    public func onRailBarTap(subItemId: String?, context: PurahPluginContext) {
        context.performHaptic(.alignment)
        context.requestExpand()
    }
}

public struct TerminalRailBarPluginView: View {
    public let context: PurahPluginContext
    public let state: TerminalPluginState
    private var manager: TerminalManager {
        TerminalManager.shared
    }

    public init(context: PurahPluginContext, state: TerminalPluginState? = nil) {
        self.context = context
        self.state = state ?? (PluginRegistry.shared.plugin(for: "terminal") as? TerminalPlugin)?.state ?? TerminalPluginState()
    }

    public var body: some View {
        let radius = min(context.railWidth / 2, 4)
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: radius)
                .fill(context.accentColor.opacity(0.85))
                .frame(width: context.railWidth, height: context.slotHeight)

            if state.isProcessRunning {
                Circle()
                    .fill(Color.green)
                    .frame(width: min(context.railWidth - 2, 4), height: min(context.railWidth - 2, 4))
                    .padding(.bottom, 4)
            }
        }
        .frame(width: context.railWidth, height: context.slotHeight)
    }
}

public struct TerminalPluginSettingsView: View {
    public let state: TerminalPluginState
    public let store: PurahWorkspaceStore
    private var manager: TerminalManager {
        TerminalManager.shared
    }

    private var availableFonts: [String] {
        TerminalFontManager.availableFamilies()
    }

    public init(state: TerminalPluginState, store: PurahWorkspaceStore = PurahWorkspaceStore()) {
        self.state = state
        self.store = store
    }

    public init(store: PurahWorkspaceStore) {
        let pluginState = (PluginRegistry.shared.plugin(for: "terminal") as? TerminalPlugin)?.state ?? TerminalPluginState()
        self.init(state: pluginState, store: store)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Persistent Terminal Settings")
                .font(.headline)

            // Font Settings Group
            VStack(alignment: .leading, spacing: 8) {
                Text("Font Family & Starship Nerd Font")
                    .font(.caption.weight(.bold))

                Picker("Font", selection: Binding(
                    get: { state.fontFamily },
                    set: {
                        state.fontFamily = $0
                        state.save()
                        store._terminalFontFamily = $0
                        store.savePersistentState()
                    }
                )) {
                    ForEach(availableFonts, id: \.self) { fontName in
                        Text(fontName).tag(fontName)
                    }
                }
                .pickerStyle(.menu)

                Text("Starship icons automatically cascade to Symbols Nerd Font / Maple Mono NF.")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)

                HStack {
                    Text("Font Size: \(String(format: "%.1f", state.fontSize))pt")
                        .font(.caption)
                    Spacer()
                }

                Slider(value: Binding(
                    get: { state.fontSize },
                    set: {
                        state.fontSize = $0
                        state.save()
                        store._terminalFontSize = $0
                        store.savePersistentState()
                    }
                ), in: 9.0...20.0, step: 0.5)
            }
            .padding(10)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(8)

            // Shell & Session State Group
            VStack(alignment: .leading, spacing: 6) {
                Text("Shell Binary")
                    .font(.caption.weight(.bold))
                Text(state.shellName.uppercased())
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)

                HStack(spacing: 6) {
                    Circle()
                        .fill(state.isProcessRunning ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(state.isProcessRunning ? "Active & Running in Background (Metal GPU Rendered)" : "Exited")
                        .font(.caption)
                }
            }
            .padding(10)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(8)

            HStack(spacing: 10) {
                Button("Restart Shell") {
                    state.restartShell(palette: ThemePalette.palette(for: .native))
                }
                .buttonStyle(.bordered)

                Button("Clear Output Buffer") {
                    state.clearScreen()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
    }
}

// MARK: - Clipboard Sidecar Plugin

