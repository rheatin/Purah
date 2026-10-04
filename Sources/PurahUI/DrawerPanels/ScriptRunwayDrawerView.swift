// Sources/PurahUI/DrawerPanels/ScriptRunwayDrawerView.swift
import SwiftUI
import PurahCore

public struct ScriptRunwayDrawerView: View {
    public let store: PurahWorkspaceStore
    private var runway: ScriptRunwayService {
        ScriptRunwayService.shared
    }
    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    public init(store: PurahWorkspaceStore) {
        self.store = store
    }

    public var body: some View {
        let scriptColor = palette.podColor(for: "scripts")

        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 5) {
                    ForEach(runway.actions) { action in
                        HStack(spacing: 8) {
                            Image(systemName: action.systemIcon)
                                .font(.system(size: 11))
                                .foregroundColor(scriptColor)
                                .frame(width: 14)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(action.name)
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .foregroundColor(palette.style == .native ? Color.primary : .white)
                                Text(action.description)
                                    .font(.system(size: 8))
                                    .foregroundColor(.gray)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 4)

                            Button {
                                Task {
                                    _ = await runway.executeAction(action)
                                }
                            } label: {
                                Text(runway.isRunning && runway.lastExecutedActionId == action.id ? "..." : "执行")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(scriptColor)
                            .foregroundColor(.white)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(palette.solidDrawerBackground)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(palette.borderColor.opacity(0.5), lineWidth: 0.8)
                        )
                    }
                }
            }

            if let msg = runway.lastOutput {
                Text(msg)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }
        }
    }
}
