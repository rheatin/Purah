// Sources/PurahUI/Settings/PreferencesView.swift
import SwiftUI
import PurahCore

public enum PreferencesTab: String, CaseIterable, Identifiable {
    case layout
    case plugins
    case permissions
    case diagnostics

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .layout: return "Layout"
        case .plugins: return "Plugins"
        case .permissions: return "Permissions"
        case .diagnostics: return "Diagnostics"
        }
    }

    @MainActor
    public var localizedTitle: String {
        switch self {
        case .layout: return "tab.layout".localized
        case .plugins: return "tab.plugins".localized
        case .permissions: return "tab.permissions".localized
        case .diagnostics: return "tab.diagnostics".localized
        }
    }

    public var icon: String {
        switch self {
        case .layout: return "slider.horizontal.2.square"
        case .plugins: return "puzzlepiece.extension.fill"
        case .permissions: return "lock.shield"
        case .diagnostics: return "stethoscope"
        }
    }
}

public struct PreferencesView: View {
    public let store: PurahWorkspaceStore
    @State public var selectedTab: PreferencesTab = .layout
    public let initialPluginId: String?

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    public init(store: PurahWorkspaceStore, initialTab: PreferencesTab = .layout, initialPluginId: String? = nil) {
        self.store = store
        self.initialPluginId = initialPluginId
        if initialPluginId != nil {
            self._selectedTab = State(initialValue: .plugins)
        } else {
            self._selectedTab = State(initialValue: initialTab)
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Segmented Top Tab Bar
            HStack(spacing: 8) {
                ForEach(PreferencesTab.allCases) { tab in
                    let isSelected = selectedTab == tab
                    Button {
                        selectedTab = tab
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 12.5, weight: .semibold))
                            Text(tab.localizedTitle)
                                .font(.system(size: 12.5, weight: isSelected ? .bold : .medium, design: .rounded))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .foregroundColor(isSelected ? (palette.style == .native ? Color.primary : .white) : .secondary)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 14)
                        .background(
                            isSelected ? palette.surfaceBackground : Color.clear
                        )
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isSelected ? palette.borderColor : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.tactile)
                }
                Spacer()

                if let appIcon = NSApp.applicationIconImage {
                    Image(nsImage: appIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 26, height: 26)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
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
                    PluginMarketplaceView(store: store, initialPluginId: initialPluginId)
                case .permissions:
                    SystemAccessSettingsView(store: store)
                case .diagnostics:
                    DiagnosticReportView(store: store)
                }
            }
        }
        .background(palette.background)
    }
}
