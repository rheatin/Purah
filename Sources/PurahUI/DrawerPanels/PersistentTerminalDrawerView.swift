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
        VStack(alignment: .leading, spacing: 4) {
            // In-Screen Interactive SwiftTerm Terminal (GPU Accelerated, TrueColor, Starship Support)
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

            // Subtle interaction hint & status
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

public struct TerminalHeaderAccessoryView: View {
    public let state: TerminalPluginState
    public let color: Color
    @ObservedObject private var manager = TerminalManager.shared

    public init(state: TerminalPluginState, color: Color) {
        self.state = state
        self.color = color
    }

    public var body: some View {
        HStack(spacing: 3) {
            if manager.tabs.isEmpty {
                HStack(spacing: 3) {
                    Circle()
                        .fill(manager.isProcessRunning ? Color.green : Color.red)
                        .frame(width: 4.5, height: 4.5)
                    Text("\(manager.shellName) 1")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(color.opacity(0.18))
                .foregroundColor(color)
                .cornerRadius(4)
            } else {
                ForEach(manager.tabs) { tab in
                    let isActive = (tab.id == manager.activeTabId)
                    HStack(spacing: 3) {
                        Button {
                            manager.selectTab(id: tab.id)
                            SensoryFeedbackService.shared.performControlHapticIfEnabled(.alignment)
                        } label: {
                            HStack(spacing: 3) {
                                if isActive {
                                    Circle()
                                        .fill((tab.isRunning || manager.isProcessRunning) ? Color.green : Color.red)
                                        .frame(width: 4.5, height: 4.5)
                                }
                                Text(tab.title)
                                    .font(.system(size: 8, weight: isActive ? .bold : .medium, design: .monospaced))
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)

                        if manager.tabs.count > 1 {
                            Button {
                                manager.closeTab(id: tab.id)
                                SensoryFeedbackService.shared.performControlHapticIfEnabled(.levelChange)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 6.5, weight: .bold))
                                    .foregroundColor(isActive ? color.opacity(0.85) : .secondary.opacity(0.75))
                            }
                            .buttonStyle(.plain)
                            .help("Close Tab")
                        }
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(isActive ? color.opacity(0.20) : Color.primary.opacity(0.06))
                    .foregroundColor(isActive ? color : .secondary)
                    .cornerRadius(4)
                }
            }

            if manager.tabs.count < TerminalManager.maxTabsCount {
                Button {
                    manager.createNewTab()
                    manager.startShellProcess()
                    SensoryFeedbackService.shared.performControlHapticIfEnabled(.alignment)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundColor(color)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(color.opacity(0.14))
                        .cornerRadius(3.5)
                }
                .buttonStyle(.plain)
                .help("New Terminal Tab (up to 5)")
            }
        }
    }
}

public struct TerminalHeaderTrailingToolbarView: View {
    public let state: TerminalPluginState
    @ObservedObject private var manager = TerminalManager.shared
    private var palette: ThemePalette { ThemeManager.shared.palette }

    public init(state: TerminalPluginState) {
        self.state = state
    }

    public var body: some View {
        HStack(spacing: 4) {
            // cd Finder quick jump button
            Button {
                _ = manager.cdToFrontmostFinderDirectory()
                SensoryFeedbackService.shared.performControlHapticIfEnabled(.alignment)
                manager.focusTerminal()
            } label: {
                HStack(spacing: 2.5) {
                    Image(systemName: "folder.badge.gearshape")
                        .font(.system(size: 7.5, weight: .semibold))
                    Text("cd Finder")
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                }
                .padding(.horizontal, 4.5)
                .padding(.vertical, 1.5)
                .background(Color.secondary.opacity(0.14))
                .foregroundColor(.primary.opacity(0.85))
                .cornerRadius(3.5)
            }
            .buttonStyle(.plain)
            .help("cd into the frontmost Finder window directory")

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
    }
}
