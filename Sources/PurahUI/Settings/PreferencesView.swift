// Sources/PurahUI/Settings/PreferencesView.swift
import SwiftUI
import AppKit
import PurahCore

public enum PreferencesTab: String, CaseIterable, Identifiable {
    case general
    case layout
    case motion
    case plugins
    case permissions
    case diagnostics

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .general: return "General"
        case .layout: return "Layout"
        case .motion: return "Motion"
        case .plugins: return "Plugins"
        case .permissions: return "Permissions"
        case .diagnostics: return "Diagnostics"
        }
    }

    @MainActor
    public var localizedTitle: String {
        switch self {
        case .general: return "tab.general".localized
        case .layout: return "tab.layout".localized
        case .motion: return "tab.motion".localized
        case .plugins: return "tab.plugins".localized
        case .permissions: return "tab.permissions".localized
        case .diagnostics: return "tab.diagnostics".localized
        }
    }

    public var icon: String {
        switch self {
        case .general: return "gearshape.fill"
        case .layout: return "slider.horizontal.2.square"
        case .motion: return "wand.and.stars"
        case .plugins: return "puzzlepiece.extension.fill"
        case .permissions: return "lock.shield"
        case .diagnostics: return "stethoscope"
        }
    }

    // Backward-compatibility alias
    public static var interaction: PreferencesTab { .motion }

    var selection: PreferencesSelection {
        switch self {
        case .general: return .general
        case .layout: return .layout
        case .motion: return .motion
        case .plugins: return .plugins
        case .permissions: return .permissions
        case .diagnostics: return .system
        }
    }
}

public enum PreferencesSelection: Hashable, Identifiable, Sendable {
    case pod(String)
    case layout, general, motion, plugins, permissions, system

    public static let globalCases: [PreferencesSelection] = [
        .layout, .general, .motion, .plugins, .permissions, .system,
    ]

    public var id: String {
        switch self {
        case .pod(let id): return "pod:\(id)"
        case .layout: return "layout"
        case .general: return "general"
        case .motion: return "motion"
        case .plugins: return "plugins"
        case .permissions: return "permissions"
        case .system: return "system"
        }
    }

    public var podId: String? {
        guard case .pod(let id) = self else { return nil }
        return id
    }

    public var icon: String? {
        switch self {
        case .pod: return nil
        case .layout: return "slider.horizontal.2.square"
        case .general: return "gearshape.fill"
        case .motion: return "wand.and.stars"
        case .plugins: return "puzzlepiece.extension.fill"
        case .permissions: return "lock.shield"
        case .system: return "stethoscope"
        }
    }

    @MainActor
    public var localizedTitle: String? {
        switch self {
        case .pod: return nil
        case .layout: return "tab.layout".localized
        case .general: return "tab.general".localized
        case .motion: return "tab.motion".localized
        case .plugins: return "tab.plugins".localized
        case .permissions: return "tab.permissions".localized
        case .system: return "tab.system".localized
        }
    }
}

struct SettingsPodIndexEntry: Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let icon: String
    let isMounted: Bool
    let isEnabled: Bool
}

enum SettingsPodIndex {
    static func ordered(
        mounted: [SettingsPodIndexEntry],
        registered: [SettingsPodIndexEntry]
    ) -> [SettingsPodIndexEntry] {
        var seen: Set<String> = []
        var result = mounted.filter { seen.insert($0.id).inserted }
        let alphabetical = registered.sorted {
            let order = $0.displayName.localizedCaseInsensitiveCompare($1.displayName)
            if order == .orderedSame {
                return $0.id < $1.id
            }
            return order == .orderedAscending
        }
        for entry in alphabetical where seen.insert(entry.id).inserted {
            result.append(entry)
        }
        return result
    }
}

public struct PreferencesView: View {
    public let store: PurahWorkspaceStore
    @State public var selection: PreferencesSelection
    public let initialPluginId: String?

    @State private var isRepoBadgeHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let repositoryURL = URL(string: "https://github.com/rheatin/Purah")!

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    public init(
        store: PurahWorkspaceStore,
        initialTab: PreferencesTab = .general,
        initialPluginId: String? = nil
    ) {
        self.store = store
        self.initialPluginId = initialPluginId
        if let initialPluginId {
            self._selection = State(initialValue: .pod(initialPluginId))
        } else {
            self._selection = State(initialValue: initialTab.selection)
        }
    }

    public var body: some View {
        let _ = LocalizationManager.shared.currentLanguage

        HStack(spacing: 0) {
            rail
                .frame(width: 200)

            selectedContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(LocalizationManager.shared.currentLanguage)
        }
        .background(palette.background)
    }

    private var rail: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) {
                    railSectionTitle("settings.rail.pods")

                    ForEach(podEntries) { entry in
                        podButton(entry)
                    }

                    Rectangle()
                        .fill(palette.borderColor)
                        .frame(height: 1)
                        .padding(.vertical, 8)

                    railSectionTitle("settings.rail.purah")

                    ForEach(PreferencesSelection.globalCases.filter { $0 != .system }) { item in
                        globalButton(item)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 12)
                .padding(.bottom, 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Rectangle()
                .fill(palette.borderColor)
                .frame(height: 1)

            globalButton(.system)
                .padding(.horizontal, 8)
                .padding(.top, 8)

            repoBadge
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.55))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(palette.borderColor)
                .frame(width: 1)
        }
    }

    private func railSectionTitle(_ key: String) -> some View {
        Text(key.localized.uppercased())
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundColor(.secondary)
            .padding(.horizontal, 9)
            .padding(.top, 4)
            .padding(.bottom, 3)
    }

    private func podButton(_ entry: SettingsPodIndexEntry) -> some View {
        let item = PreferencesSelection.pod(entry.id)
        let isSelected = selection == item
        let color = palette.podColor(for: entry.id, store: store)

        return Button {
            selection = item
        } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(color)
                    .frame(width: 4, height: 14)

                Image(systemName: entry.icon)
                    .font(.system(size: 12))
                    .foregroundColor(color)
                    .frame(width: 14)

                Text(entry.displayName)
                    .font(
                        .system(
                            size: 11.5,
                            weight: isSelected ? .bold : .medium,
                            design: .rounded
                        )
                    )
                    .foregroundColor(
                        isSelected
                            ? (palette.style == .native ? Color.primary : .white)
                            : .secondary
                    )
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? palette.surfaceBackground : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(isSelected ? palette.borderColor : Color.clear, lineWidth: 1)
            )
            .opacity(entry.isEnabled ? 1 : 0.45)
        }
        .buttonStyle(.tactile)
        .accessibilityLabel(entry.displayName)
    }

    private func globalButton(_ item: PreferencesSelection) -> some View {
        let isSelected = selection == item

        return Button {
            selection = item
        } label: {
            HStack(spacing: 8) {
                Image(systemName: item.icon ?? "circle")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(width: 14)

                Text(item.localizedTitle ?? "")
                    .font(
                        .system(
                            size: 11.5,
                            weight: isSelected ? .bold : .medium,
                            design: .rounded
                        )
                    )
                    .foregroundColor(
                        isSelected
                            ? (palette.style == .native ? Color.primary : .white)
                            : .secondary
                    )
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? palette.surfaceBackground : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(isSelected ? palette.borderColor : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.tactile)
        .accessibilityLabel(item.localizedTitle ?? item.id)
    }

    @ViewBuilder
    private var repoBadge: some View {
        if let appIcon = NSApp.applicationIconImage {
            HStack {
                Button {
                    NSWorkspace.shared.open(Self.repositoryURL)
                } label: {
                    Image(nsImage: appIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 22, height: 22)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .shadow(
                            color: palette.primaryAccent.opacity(
                                isRepoBadgeHovered ? 0.50 : 0.20
                            ),
                            radius: isRepoBadgeHovered ? 7 : 4
                        )
                        .scaleEffect(isRepoBadgeHovered && !reduceMotion ? 1.06 : 1.0)
                        .animation(PurahMotionPolicy.hover, value: isRepoBadgeHovered)
                }
                .buttonStyle(.plain)
                .onHover { isRepoBadgeHovered = $0 }
                .help("View Purah on GitHub")
                .accessibilityLabel("View Purah on GitHub")

                Spacer()
            }
        }
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selection {
        case .pod(let id):
            PodSettingsPage(store: store, pluginId: id)
                .id(id)
        case .layout:
            VisualLayoutSimulatorView(store: store)
        case .general:
            GeneralSettingsView(store: store)
        case .motion:
            InteractionSettingsView(store: store)
        case .plugins:
            PluginMarketplaceView(store: store, initialPluginId: initialPluginId)
        case .permissions:
            SystemAccessSettingsView(store: store)
        case .system:
            DiagnosticReportView(store: store)
        }
    }

    private var podEntries: [SettingsPodIndexEntry] {
        let plugins = PluginRegistry.shared.allPlugins
        let pluginsByID = Dictionary(
            uniqueKeysWithValues: plugins.map { ($0.manifest.id, $0) }
        )
        let mounted = store.pods.map { pod -> SettingsPodIndexEntry in
            let plugin = pluginsByID[pod.id]
            return SettingsPodIndexEntry(
                id: pod.id,
                displayName: plugin?.manifest.displayName ?? pod.defaultName,
                icon: plugin?.manifest.systemIcon ?? pod.systemIcon,
                isMounted: true,
                isEnabled: pod.isEnabled
            )
        }
        let registered = plugins.map {
            SettingsPodIndexEntry(
                id: $0.manifest.id,
                displayName: $0.manifest.displayName,
                icon: $0.manifest.systemIcon,
                isMounted: false,
                isEnabled: true
            )
        }
        return SettingsPodIndex.ordered(mounted: mounted, registered: registered)
    }
}
