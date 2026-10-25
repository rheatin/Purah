// Sources/PurahUI/DrawerPanels/ScriptItemDrawerView.swift
import SwiftUI
import AppKit
import PurahCore

public struct ScriptItemDrawerView: View {
    public let action: ScriptActionItem
    public let edge: MountEdge
    public let state: ItemDrawerState
    public let isPinned: Bool
    public let height: CGFloat
    public let store: PurahWorkspaceStore
    public let onTogglePin: () -> Void

    @State private var isHovered = false

    private var palette: ThemePalette { ThemeManager.shared.palette }
    private var podColor: Color { palette.podColor(for: "scripts", store: store) }
    private var runway: ScriptRunwayService { ScriptRunwayService.shared }

    public init(
        action: ScriptActionItem,
        edge: MountEdge,
        state: ItemDrawerState = .dockedFlush,
        isPinned: Bool = false,
        height: CGFloat,
        store: PurahWorkspaceStore,
        onTogglePin: @escaping () -> Void = {}
    ) {
        self.action = action
        self.edge = edge
        self.state = state
        self.isPinned = isPinned
        self.height = height
        self.store = store
        self.onTogglePin = onTogglePin
    }

    public init(
        action: ScriptActionItem,
        store: PurahWorkspaceStore,
        height: CGFloat,
        edge: MountEdge,
        state: ItemDrawerState = .dockedFlush,
        isPinned: Bool = false,
        onTogglePin: @escaping () -> Void = {}
    ) {
        self.init(
            action: action,
            edge: edge,
            state: state,
            isPinned: isPinned,
            height: height,
            store: store,
            onTogglePin: onTogglePin
        )
    }

    public var body: some View {
        let cardH = height
        let barRadius = min(CGFloat(store.railBarWidth) / 2, 4)
        let barW = CGFloat(store.railBarWidth)
        let isRunning = runway.isRunning && runway.lastExecutedActionId == action.id

        let isExpanded = (state == .expandedDrawer)

        ZStack(alignment: edge == .right ? .trailing : .leading) {
            // Rail-anchored indicator bar (micro icon, execution state indicator, and tactile feedback)
            ZStack(alignment: .center) {
                RoundedRectangle(cornerRadius: barRadius)
                    .fill(podColor.opacity(isHovered ? 1.0 : (isRunning ? 0.95 : 0.85)))
                    .frame(width: barW, height: cardH)
                    .shadow(color: isRunning ? podColor.opacity(0.85) : (isHovered ? podColor.opacity(0.4) : .clear), radius: isRunning ? 4 : 2)

                if isRunning {
                    Circle()
                        .fill(Color.white)
                        .frame(width: min(max(barW - 2, 3), 5), height: min(max(barW - 2, 3), 5))
                } else if barW >= 10 {
                    Image(systemName: action.systemIcon)
                        .font(.system(size: min(barW - 2, 8)))
                        .foregroundColor(.white.opacity(0.9))
                }
            }
            .frame(width: barW, height: cardH)
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)
            .transaction { t in
                if !store.isBreathingActive(for: edge) {
                    t.animation = nil
                }
            }

            if isExpanded {
                expandedCard(cardH: cardH)
                    .transition(.move(edge: edge == .right ? .trailing : .leading))
            }
        }
        .frame(height: cardH)
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(isExpanded ? .spring(response: 0.30, dampingFraction: 0.80) : .spring(response: 0.20, dampingFraction: 0.92), value: isExpanded)
    }

    @ViewBuilder
    private func expandedCard(cardH: CGFloat) -> some View {
        let effectiveW = store.effectiveDrawerWidth(for: action.name, baseWidth: 280.0)
        let isRunning = runway.isRunning && runway.lastExecutedActionId == action.id

        HStack(spacing: 8) {
            // Entire card body is a tactile click-to-run button
            Button {
                Task {
                    let res = await runway.executeAction(action)
                    if action.showNotification {
                        let text = res.success ? "✨ Ran \(action.name)" : "⚠️ Failed: \(res.message)"
                        store.onCapacityWarningToast?(text)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    // Action Icon Tile (Animates when executing)
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(podColor.opacity(isRunning ? 0.35 : 0.16))
                            .frame(width: 24, height: 24)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(podColor.opacity(0.35), lineWidth: 1)
                            )

                        if isRunning {
                            ProgressView()
                                .controlSize(.mini)
                                .scaleEffect(0.6)
                        } else {
                            Image(systemName: action.systemIcon)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(podColor)
                        }
                    }

                    // Name & Secondary subtitle
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text(action.name)
                                .purahTitle(size: 11.5, weight: .bold, design: .rounded)
                                .foregroundColor(palette.style == .native ? Color.primary : .white)
                                .lineLimit(1)

                            Text(badgeText(for: action.commandType))
                                .purahBadge(size: 7, weight: .bold)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(podColor.opacity(0.16)))
                                .foregroundColor(podColor)
                        }

                        if isRunning {
                            let streamLine = runway.liveStreamingOutput.components(separatedBy: .newlines).last ?? ""
                            Text(streamLine.isEmpty ? "Executing command..." : streamLine)
                                .purahCaption(size: 8.5, weight: .medium, design: streamLine.isEmpty ? .default : .monospaced)
                                .foregroundColor(podColor)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        } else if let output = runway.lastOutput, runway.lastExecutedActionId == action.id {
                            HStack(spacing: 3) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 8))
                                    .foregroundColor(.green)
                                Text(output)
                                    .purahCaption(size: 8.5, weight: .regular, design: .monospaced)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        } else {
                            let preview = !action.description.isEmpty ? action.description : (action.commandType == .shortcut ? "Click to run shortcut" : action.scriptContent)
                            Text(preview)
                                .purahCaption(size: 8.5, weight: .regular, design: .monospaced)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }

                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.tactile)
            .disabled(runway.isRunning)

            if isRunning {
                Button {
                    runway.stopRunningScript()
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 6.5, weight: .bold))
                        Text("Stop")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2.5)
                    .background(Color.red.opacity(0.9))
                    .foregroundColor(.white)
                    .cornerRadius(4)
                }
                .buttonStyle(.tactile)
                .help("Stop running script")
            }

            // Pin button (Matches Hardware Vitals design)
            pinButton
        }
        .padding(.leading, edge == .left ? 12 : 22)
        .padding(.trailing, edge == .left ? 22 : 12)
        .padding(.vertical, 6)
        .frame(width: effectiveW, height: cardH)
        .liquidDrawerBackground(shape: drawerShape, accentColor: podColor)
        .contextMenu {
            Button {
                store.openPluginSettings(id: "scripts")
            } label: {
                Label("Configure Scripts Runway...", systemImage: "gearshape")
            }
            Button {
                onTogglePin()
            } label: {
                Label(isPinned ? "Unpin Action" : "Pin Action", systemImage: isPinned ? "pin.slash" : "pin")
            }
        }
    }

    private var drawerShape: UnevenRoundedRectangle {
        if edge == .right {
            return UnevenRoundedRectangle(
                topLeadingRadius: 8,
                bottomLeadingRadius: 8,
                bottomTrailingRadius: 0,
                topTrailingRadius: 0,
                style: .continuous
            )
        } else {
            return UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 8,
                topTrailingRadius: 8,
                style: .continuous
            )
        }
    }

    private var pinButton: some View {
        PurahDrawerHeaderTools(
            onSettings: { store.openPluginSettings(id: "scripts") },
            settingsHelp: "Open Scripts Settings",
            isPinned: isPinned,
            tintColor: podColor,
            onTogglePin: onTogglePin
        )
    }

    private func badgeText(for type: ScriptCommandType) -> String {
        switch type {
        case .shortcut: return "SHORTCUT"
        case .shell: return "SHELL"
        case .appleScript: return "APPLESCRIPT"
        }
    }
}
