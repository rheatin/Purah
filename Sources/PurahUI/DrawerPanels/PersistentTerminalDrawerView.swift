// Sources/PurahUI/DrawerPanels/PersistentTerminalDrawerView.swift
import SwiftUI
import AppKit
import PurahCore

public struct PersistentTerminalDrawerView: View {
    public let state: TerminalPluginState
    public let store: PurahWorkspaceStore

    @ObservedObject private var manager = TerminalManager.shared

    /// Resolved when the drawer opens, not per render: it reads the AI plugin's
    /// settings and, for an HTTP provider, the secrets file.
    @State private var aiAvailability: AIAssistantAvailability?

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

            // One line: what the two commands are, and whether the AI behind
            // them can answer. The ⌘C/⌘V/⇥ boilerplate that used to sit here
            // told people things they already knew, in the space where status
            // belongs.
            HStack(spacing: 4) {
                if TerminalShellIntegration.isEnabled {
                    // Advertises `??` where it is needed, and clicking it types
                    // the two characters, so the reminder is also the way in.
                    Button {
                        manager.beginNaturalLanguageCommand()
                    } label: {
                        Text("terminal.suggest.hint".localized)
                            .font(.system(size: 7.5, weight: .semibold, design: .monospaced))
                            .foregroundColor(terminalColor.opacity(0.9))
                    }
                    .buttonStyle(.plain)
                    .disabled(!manager.isProcessRunning)
                    .help("terminal.suggest.tooltip".localized)
                    .accessibilityLabel("terminal.suggest.hint".localized)

                    Text("·")
                        .font(.system(size: 7.5, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.5))

                    // `???` needs no composed input, so it is a legend rather
                    // than a button: a click would either demand a second Return
                    // or fire an AI request nobody asked for from a status line.
                    Text("terminal.suggest.explainHint".localized)
                        .font(.system(size: 7.5, weight: .semibold, design: .monospaced))
                        .foregroundColor(terminalColor.opacity(0.9))
                        .lineLimit(1)
                }

                Spacer()

                if let aiAvailability {
                    Button {
                        store.openPluginSettings(id: "ai")
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: aiAvailability.provider.systemIcon)
                                .font(.system(size: 8, weight: .medium))
                                .foregroundColor(aiIconColor(aiAvailability))
                            aiStateDot(aiAvailability.state)
                        }
                    }
                    .buttonStyle(.plain)
                    .help(aiHelpText(aiAvailability))
                    .accessibilityLabel(aiHelpText(aiAvailability))
                }
            }
            .padding(.horizontal, 2)
        }
        .onAppear {
            manager.focusTerminal()
        }
        .task {
            aiAvailability = .current()
        }
    }

    // MARK: - AI status

    /// Which AI answers `??`, and whether it can — read from the same settings
    /// the AI Assistant drawer uses, so the two cannot disagree.
    private func aiHelpText(_ availability: AIAssistantAvailability) -> String {
        let stateText: String
        switch availability.state {
        case .ready: stateText = "ai.settings.available".localized
        case .configuredUnverified: stateText = "ai.status.configured".localized
        case .unavailable: stateText = "ai.settings.unavailableOnThisMac".localized
        }
        var text = "\(availability.provider.displayName) · \(stateText)"
        if let detail = availability.detail, !detail.isEmpty {
            text += "\n\(detail)"
        }
        return text
    }

    private func aiIconColor(_ availability: AIAssistantAvailability) -> Color {
        switch availability.state {
        case .ready:
            return availability.provider == .appleIntelligence ? .purple : terminalColor.opacity(0.9)
        case .configuredUnverified:
            return terminalColor.opacity(0.7)
        case .unavailable:
            return .orange
        }
    }

    /// Filled green when verified, hollow when only configured, orange when
    /// known to be unusable — the same three levels the settings page shows.
    @ViewBuilder
    private func aiStateDot(_ state: AIAssistantAvailabilityState) -> some View {
        Group {
            switch state {
            case .ready:
                Circle().fill(Color.green)
            case .configuredUnverified:
                Circle().stroke(Color.secondary.opacity(0.8), lineWidth: 0.8)
            case .unavailable:
                Circle().fill(Color.orange)
            }
        }
        .frame(width: 4.5, height: 4.5)
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
                            .help("help.closeTab".localized)
                            .accessibilityLabel("help.closeTab".localized)
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
                .help("help.newTerminalTab".localized)
                .accessibilityLabel("help.newTerminalTab".localized)
            }
        }
    }
}

public struct TerminalHeaderTrailingToolbarView: View {
    public let state: TerminalPluginState
    public let store: PurahWorkspaceStore
    @ObservedObject private var manager = TerminalManager.shared
    private var palette: ThemePalette { ThemeManager.shared.palette }

    public init(state: TerminalPluginState, store: PurahWorkspaceStore = PurahWorkspaceStore()) {
        self.state = state
        self.store = state.boundStore ?? store
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
            .help("help.cdToFinder".localized)
            .accessibilityLabel("help.cdToFinder".localized)

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
            .help("help.sendSIGINT".localized)
            .accessibilityLabel("help.sendSIGINT".localized)

            PurahClearButton(
                title: nil,
                icon: "trash",
                isCompact: true,
                helpText: "Clear terminal output (⌘K)"
            ) {
                state.clearActiveTab()
                store.triggerControlHaptic(.alignment)
            }

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
            .help("help.restartShellSession".localized)
            .accessibilityLabel("help.restartShellSession".localized)
        }
    }
}
