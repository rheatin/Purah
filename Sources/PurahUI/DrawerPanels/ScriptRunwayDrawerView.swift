// Sources/PurahUI/DrawerPanels/ScriptRunwayDrawerView.swift
import SwiftUI
import PurahCore

public struct ScriptRunwayDrawerView: View {
    public let state: ScriptsPluginState
    public let store: PurahWorkspaceStore
    @State private var isOutputDismissed: Bool = false
    private var runway: ScriptRunwayService {
        ScriptRunwayService.shared
    }
    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    public init(state: ScriptsPluginState, store: PurahWorkspaceStore = PurahWorkspaceStore()) {
        self.state = state
        self.store = store
    }

    public init(store: PurahWorkspaceStore) {
        let pluginState = (PluginRegistry.shared.plugin(for: "scripts") as? ScriptRunwayPlugin)?.state ?? ScriptsPluginState()
        self.init(state: pluginState, store: store)
    }

    public var body: some View {
        let scriptColor = palette.podColor(for: "scripts")

        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 5) {
                    ForEach(state.actions) { action in
                        let isThisRunning = (state.isRunning && state.lastExecutedActionId == action.id) || (runway.isRunning && runway.lastExecutedActionId == action.id)

                        HStack(spacing: 8) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(scriptColor.opacity(0.12))
                                    .frame(width: 26, height: 26)
                                Image(systemName: action.systemIcon)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(scriptColor)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 5) {
                                    Text(action.name)
                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                        .foregroundColor(palette.style == .native ? Color.primary : .white)
                                        .lineLimit(1)
                                        .truncationMode(.tail)

                                    Spacer(minLength: 4)

                                    badgeForType(action.commandType, color: scriptColor)
                                }

                                Text(action.description.isEmpty ? action.command : action.description)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }

                            Button {
                                Task {
                                    let res = await state.executeAction(action, store: store)
                                    if action.showNotification {
                                        let text = res.success ? "Ran \(action.name)" : "Failed: \(res.message)"
                                        store.onCapacityWarningToast?(text)
                                    }
                                }
                            } label: {
                                if isThisRunning {
                                    HStack(spacing: 3) {
                                        ProgressView()
                                            .controlSize(.mini)
                                        Text("Running")
                                            .font(.system(size: 8.5, weight: .bold))
                                    }
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3.5)
                                    .background(scriptColor.opacity(0.85))
                                    .foregroundColor(.white)
                                    .cornerRadius(5)
                                } else {
                                    HStack(spacing: 3.5) {
                                        Image(systemName: "play.fill")
                                            .font(.system(size: 7))
                                        Text("Run")
                                            .font(.system(size: 8.5, weight: .bold))
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3.5)
                                    .background(scriptColor)
                                    .foregroundColor(.white)
                                    .cornerRadius(5)
                                }
                            }
                            .buttonStyle(.tactile)
                            .fixedSize()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .liquidCardBackground(cornerRadius: 6, strokeColor: palette.borderColor.opacity(0.35))
                    }
                }
            }

            if !isOutputDismissed, let msg = state.lastOutput ?? runway.lastOutput, !msg.isEmpty {
                HStack(spacing: 5) {
                    Text("$")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.green.opacity(0.9))
                    Text(msg)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.primary.opacity(0.85))
                        .lineLimit(1)
                    Spacer()
                    Button {
                        isOutputDismissed = true
                        state.lastOutput = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3.5)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(palette.borderColor.opacity(0.2), lineWidth: 0.6)
                )
            }
        }
    }

    @ViewBuilder
    private func badgeForType(_ type: ScriptCommandType, color: Color) -> some View {
        let (text, badgeColor) = switch type {
        case .shortcut:
            ("SHORTCUT", Color.purple)
        case .appleScript:
            ("APPLESCRIPT", Color.orange)
        case .shell:
            ("SHELL", Color.cyan)
        }
        Text(text)
            .font(.system(size: 6.5, weight: .bold, design: .monospaced))
            .padding(.horizontal, 3.5)
            .padding(.vertical, 1)
            .background(badgeColor.opacity(0.18))
            .foregroundColor(badgeColor)
            .cornerRadius(3)
    }
}
