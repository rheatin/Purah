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
            .clipShape(RoundedRectangle(cornerRadius: PurahItemRhythm.rowCornerRadius, style: .continuous))
            .overlay(
                // Was a 0.3 border around a 6pt box — together with the
                // terminal's own dark fill it read as a separate window. With
                // the fill gone this is only a hairline, so the drawer's own
                // corner shows.
                RoundedRectangle(cornerRadius: PurahItemRhythm.rowCornerRadius, style: .continuous)
                    .stroke(palette.borderColor.opacity(0.12), lineWidth: 0.8)
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
            // Opening the drawer is how the person sees the result the rail
            // dot was reporting.
            state.acknowledgeCommandResult()
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
        PurahHeaderGroup {
            if manager.tabs.isEmpty {
                PurahHeaderChip(tint: color, isSelected: true) {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(manager.isProcessRunning ? Color.green : Color.red)
                            .frame(width: 4.5, height: 4.5)
                        Text("\(manager.shellName) 1")
                            .font(.system(size: PurahHeaderMetrics.pillFontSize, weight: .bold, design: .monospaced))
                    }
                }
            } else {
                ForEach(manager.tabs) { tab in
                    let isActive = (tab.id == manager.activeTabId)
                    PurahHeaderChip(tint: color, isSelected: isActive) {
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
                                        .font(.system(size: PurahHeaderMetrics.pillFontSize,
                                                      weight: isActive ? .bold : .medium,
                                                      design: .monospaced))
                                        .lineLimit(1)
                                }
                                .foregroundColor(isActive ? color : .secondary)
                                // The gap between the dot and the title is
                                // part of the target, not dead space.
                                .contentShape(Rectangle())
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
                                        // A 6.5pt glyph is not a click target.
                                        .frame(width: 10, height: 12)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .help("help.closeTab".localized)
                                .accessibilityLabel("help.closeTab".localized)
                            }
                        }
                    }
                }
            }

            if manager.tabs.count < TerminalManager.maxTabsCount {
                PurahHeaderButton(
                    systemImage: "plus",
                    help: "help.newTerminalTab".localized,
                    tint: color,
                    isEmphasized: true
                ) {
                    manager.createNewTab()
                    manager.startShellProcess()
                    SensoryFeedbackService.shared.performControlHapticIfEnabled(.alignment)
                }
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
        PurahHeaderGroup {
            PurahHeaderButton(systemImage: "folder.badge.gearshape", help: "help.cdToFinder".localized) {
                _ = manager.cdToFrontmostFinderDirectory()
                SensoryFeedbackService.shared.performControlHapticIfEnabled(.alignment)
                manager.focusTerminal()
            }

            TerminalFontSizeButton(state: state)

            PurahHeaderButton(systemImage: "arrow.clockwise", help: "help.restartShellSession".localized) {
                manager.restartShell(
                    fontFamily: state.fontFamily,
                    fontSize: CGFloat(state.fontSize),
                    palette: palette
                )
            }
        }
    }
}

// MARK: - Header Font Size

/// A dragged slider, not "smaller / larger / reset" in a menu.
///
/// Choosing a size from three discrete steps means guessing and re-opening the
/// menu; the terminal behind the popover resizes as the slider moves, so the
/// control shows its own answer.
///
/// Neutral colours, like the buttons beside it: a size that differs from the
/// default is not a state worth flagging, and an accent-tinted glyph in the
/// header reads as a warning.
struct TerminalFontSizeButton: View {
    let state: TerminalPluginState

    @State private var isShowing = false

    var body: some View {
        PurahHeaderButton(
            systemImage: "textformat.size",
            help: "terminal.fontSize".localized
        ) {
            isShowing.toggle()
        }
        .popover(isPresented: $isShowing, arrowEdge: .bottom) {
            TerminalFontSizePanel(state: state)
        }
    }
}

private struct TerminalFontSizePanel: View {
    @Bindable var state: TerminalPluginState

    private var isDefault: Bool {
        state.fontSize == TerminalPluginState.defaultFontSize
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("terminal.fontSize".localized)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)

                Spacer(minLength: 0)

                Text(String(format: "%.1f pt", state.fontSize))
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
                    .contentTransition(.numericText())
            }

            HStack(spacing: 7) {
                Text("A")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary.opacity(0.7))

                Slider(value: $state.fontSize, in: 9...22, step: 0.5)
                .controlSize(.small)
                .accessibilityLabel("terminal.fontSize".localized)
                .accessibilityValue(String(format: "%.1f pt", state.fontSize))

                Text("A")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary.opacity(0.7))
            }

            HStack(spacing: 6) {
                Spacer(minLength: 0)
                Button {
                    state.fontSize = TerminalPluginState.defaultFontSize
                    state.save()
                } label: {
                    Text("terminal.fontReset".localized)
                        .font(.system(size: 9, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundColor(isDefault ? .secondary.opacity(0.45) : .secondary)
                .disabled(isDefault)
            }
        }
        .padding(12)
        .frame(width: 224)
        .onDisappear { state.save() }
    }
}
