// Sources/PurahUI/DrawerPanels/PersistentTerminalDrawerView.swift
import SwiftUI
import AppKit
import PurahCore

public struct PersistentTerminalDrawerView: View {
    public let state: TerminalPluginState
    public let store: PurahWorkspaceStore

    @ObservedObject private var manager = TerminalManager.shared

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    private var terminalColor: Color {
        palette.podColor(for: "terminal", store: store)
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
        VStack(alignment: .leading, spacing: 5) {
            // Row 1: Status & Utility Toolbar
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(manager.isProcessRunning ? Color.green : Color.red)
                        .frame(width: 5, height: 5)

                    Text(manager.shellName.uppercased())
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(terminalColor.opacity(0.18))
                        .foregroundColor(terminalColor)
                        .cornerRadius(3)

                    if !manager.isProcessRunning {
                        Text("EXITED")
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundColor(.red)
                    }
                }

                Spacer()

                // Font size quick adjuster
                HStack(spacing: 2) {
                    Button {
                        if state.fontSize > 9.0 {
                            state.fontSize -= 0.5
                            state.save()
                        }
                    } label: {
                        Text("A-")
                            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.12))
                            .cornerRadius(3)
                    }
                    .buttonStyle(.plain)

                    Button {
                        if state.fontSize < 22.0 {
                            state.fontSize += 0.5
                            state.save()
                        }
                    } label: {
                        Text("A+")
                            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.12))
                            .cornerRadius(3)
                    }
                    .buttonStyle(.plain)
                }

                // Quick Terminal Action Buttons
                Button {
                    manager.sendInterrupt()
                } label: {
                    Text("^C")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1.5)
                        .background(Color.secondary.opacity(0.15))
                        .cornerRadius(3)
                }
                .buttonStyle(.plain)
                .help("Send SIGINT (Ctrl+C)")

                Button {
                    manager.clearScreen()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 8.5))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear Terminal Buffer")

                Button {
                    manager.restartShell(
                        fontFamily: state.fontFamily,
                        fontSize: CGFloat(state.fontSize),
                        palette: palette
                    )
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 8.5))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Restart Shell Session")
            }
            .padding(.bottom, 1)

            // Row 2: In-Screen Interactive SwiftTerm Terminal (GPU Accelerated, TrueColor, Starship Support)
            SwiftTermRepresentable(
                fontFamily: state.fontFamily,
                fontSize: state.fontSize,
                palette: palette
            )
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(palette.borderColor.opacity(0.3), lineWidth: 0.8)
            )
            .frame(maxHeight: .infinity)

            // Row 3: Subtle interaction hint & status
            HStack(spacing: 4) {
                Text("Click inside to type · ⌘C / ⌘V supported · ⇥ autocomplete")
                    .font(.system(size: 7.5, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.7))
                Spacer()
                Text("\(String(format: "%.1f", state.fontSize))pt")
                    .font(.system(size: 7.5, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .padding(.horizontal, 2)
        }
        .onAppear {
            manager.focusTerminal()
        }
    }
}
