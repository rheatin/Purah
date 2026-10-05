// Sources/PurahUI/Settings/PreferencesView.swift
import SwiftUI
import PurahCore

public enum PreferencesTab: String, CaseIterable, Identifiable {
    case layout
    case plugins
    case permissions

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .layout: return "Layout & Rails"
        case .plugins: return "Plugins"
        case .permissions: return "Permissions & Access"
        }
    }

    public var icon: String {
        switch self {
        case .layout: return "slider.horizontal.2.square"
        case .plugins: return "puzzlepiece.extension.fill"
        case .permissions: return "lock.shield"
        }
    }
}

public struct PreferencesView: View {
    public let store: PurahWorkspaceStore
    @State public var selectedTab: PreferencesTab = .layout

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    public init(store: PurahWorkspaceStore, initialTab: PreferencesTab = .layout) {
        self.store = store
        self._selectedTab = State(initialValue: initialTab)
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Segmented Top Tab Bar
            HStack(spacing: 12) {
                ForEach(PreferencesTab.allCases) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tab.icon)
                            Text(tab.title)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(selectedTab == tab ? palette.primaryAccent : .gray)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 14)
                        .background(
                            selectedTab == tab ? palette.surfaceBackground : Color.clear
                        )
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(selectedTab == tab ? palette.borderColor : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 6)

            Divider()
                .background(palette.borderColor)

            // Content
            Group {
                switch selectedTab {
                case .layout:
                    VisualLayoutSimulatorView(store: store)
                case .plugins:
                    PluginCenterSettingsView(store: store)
                case .permissions:
                    SystemAccessSettingsView(store: store)
                }
            }
        }
        .background(palette.background)
    }
}
