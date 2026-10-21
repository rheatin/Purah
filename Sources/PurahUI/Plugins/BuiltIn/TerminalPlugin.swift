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
        120.0
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

    private var palette: ThemePalette {
        ThemeManager.shared.palette
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
            // Card 1: Typography & Nerd Font Engine
            PurahPluginSettingsCard(
                title: "Typography & Nerd Font Engine",
                subtitle: "Configure monospace terminal font and glyph cascading",
                icon: "textformat.size",
                iconColor: palette.primaryAccent
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Font Family")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                        Spacer()
                        Menu {
                            ForEach(availableFonts, id: \.self) { fontName in
                                Button(fontName) {
                                    state.fontFamily = fontName
                                    state.save()
                                    store._terminalFontFamily = fontName
                                    store.savePersistentState()
                                }
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Text(state.fontFamily)
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundColor(palette.primaryAccent)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.04))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(palette.borderColor.opacity(0.25), lineWidth: 0.8)
                            )
                        }
                        .menuIndicator(.hidden)
                    }

                    Text("Starship icons automatically cascade to Symbols Nerd Font / Maple Mono NF.")
                        .font(.system(size: 9.5))
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Font Size")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                            Spacer()
                            Text("\(String(format: "%.1f", state.fontSize)) pt")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(palette.primaryAccent)
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
                }
            }

            // Card 2: Persistent Shell Session
            PurahPluginSettingsCard(
                title: "Persistent Shell Session",
                subtitle: "PTY subprocess execution and GPU buffer lifecycle",
                icon: "apple.terminal.fill",
                iconColor: Color(hex: "#34C759")
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(state.isProcessRunning ? Color.green : Color.red)
                            .frame(width: 8, height: 8)

                        Text(state.shellName.uppercased())
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(palette.primaryAccent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(palette.primaryAccent.opacity(0.12))
                            .cornerRadius(4)

                        Text(state.isProcessRunning ? "Active & Running (Metal GPU)" : "Exited")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)

                        Spacer()
                    }
                    .padding(8)
                    .background(Color.primary.opacity(0.03))
                    .cornerRadius(7)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(palette.borderColor.opacity(0.2), lineWidth: 0.8)
                    )

                    HStack(spacing: 8) {
                        Button {
                            state.restartShell(palette: ThemePalette.palette(for: .native))
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 10))
                                Text("Restart Shell")
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.primary.opacity(0.05))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(palette.borderColor.opacity(0.3), lineWidth: 0.8)
                            )
                        }
                        .buttonStyle(.plain)

                        Button {
                            state.clearScreen()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "trash")
                                    .font(.system(size: 10))
                                Text("Clear Output Buffer")
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.primary.opacity(0.05))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(palette.borderColor.opacity(0.3), lineWidth: 0.8)
                            )
                        }
                        .buttonStyle(.plain)

                        Spacer()
                    }
                }
            }
        }
    }
}

// MARK: - Clipboard Sidecar Plugin

