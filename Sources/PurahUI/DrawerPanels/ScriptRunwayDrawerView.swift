// Sources/PurahUI/DrawerPanels/ScriptRunwayDrawerView.swift
import SwiftUI
import PurahCore

public struct ScriptRunwayDrawerView: View {
    public let state: ScriptsPluginState
    public let store: PurahWorkspaceStore
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
                        HStack(spacing: 8) {
                            Image(systemName: action.systemIcon)
                                .font(.system(size: 11))
                                .foregroundColor(scriptColor)
                                .frame(width: 14)

                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 4) {
                                    Text(action.name)
                                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                                        .foregroundColor(palette.style == .native ? Color.primary : .white)

                                    if action.commandType == .shortcut {
                                        Text("SHORTCUT")
                                            .font(.system(size: 7, weight: .bold))
                                            .padding(.horizontal, 3)
                                            .padding(.vertical, 1)
                                            .background(scriptColor.opacity(0.20))
                                            .foregroundColor(scriptColor)
                                            .cornerRadius(3)
                                    }
                                }
                                Text(action.description)
                                    .font(.system(size: 8))
                                    .foregroundColor(.gray)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 4)

                            Button {
                                Task {
                                    let res = await state.executeAction(action, store: store)
                                    if action.showNotification {
                                        let text = res.success ? "✨ Ran \(action.name)" : "⚠️ Failed: \(res.message)"
                                        store.onCapacityWarningToast?(text)
                                    }
                                }
                            } label: {
                                Text((state.isRunning && state.lastExecutedActionId == action.id) || (runway.isRunning && runway.lastExecutedActionId == action.id) ? "..." : "Run")
                                    .font(.system(size: 8, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(scriptColor)
                                    .foregroundColor(.white)
                                    .cornerRadius(4)
                            }
                            .buttonStyle(.tactile)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .liquidCardBackground(cornerRadius: 6, strokeColor: palette.borderColor.opacity(0.4))
                    }
                }
            }

            if let msg = state.lastOutput ?? runway.lastOutput {
                Text(msg)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }
        }
    }
}
