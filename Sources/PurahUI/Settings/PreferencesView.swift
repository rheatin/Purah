// Sources/PurahUI/Settings/PreferencesView.swift
import SwiftUI
import AppKit
import PurahCore

public enum PreferencesTab: String, CaseIterable, Identifiable {
    case general
    case layout
    case motion
    case market
    case permissions
    case diagnostics

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .general: return "General"
        case .layout: return "Layout"
        case .motion: return "Motion"
        case .market: return "Market"
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
        case .market: return "tab.market".localized
        case .permissions: return "tab.permissions".localized
        case .diagnostics: return "tab.diagnostics".localized
        }
    }

    public var icon: String {
        switch self {
        case .general: return "gearshape.fill"
        case .layout: return "slider.horizontal.2.square"
        case .motion: return "wand.and.stars"
        case .market: return "bag.fill"
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
        case .market: return .market
        case .permissions: return .permissions
        case .diagnostics: return .system
        }
    }
}

public enum PreferencesSelection: Hashable, Identifiable, Sendable {
    case pod(String)
    case layout, general, motion, market, permissions, system

    public static let globalCases: [PreferencesSelection] = [
        .layout, .general, .motion, .market, .permissions, .system,
    ]

    public var id: String {
        switch self {
        case .pod(let id): return "pod:\(id)"
        case .layout: return "layout"
        case .general: return "general"
        case .motion: return "motion"
        case .market: return "market"
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
        case .market: return "bag.fill"
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
        case .market: return "tab.market".localized
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

struct SettingsFocusHandoff: Equatable {
    private(set) var podId: String?
    private(set) var nonce: Int = 0

    mutating func deliver(_ podId: String) {
        self.podId = podId
        nonce &+= 1
    }

    mutating func clearForManualSelection() {
        podId = nil
    }

    mutating func clearIfCurrent(podId: String, nonce: Int) {
        guard self.podId == podId, self.nonce == nonce else { return }
        self.podId = nil
    }
}

public struct PreferencesView: View {
    public let store: PurahWorkspaceStore
    @State public var selection: PreferencesSelection
    public let initialPluginId: String?

    @State private var focus = SettingsFocusHandoff()
    @State private var focusClearTask: Task<Void, Never>?
    @State private var isRepoBadgeHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let repositoryURL = URL(string: "https://github.com/rheatin/Purah")!
    private let podStorageRoots: PluginStorageRoots

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    public init(
        store: PurahWorkspaceStore,
        initialTab: PreferencesTab = .general,
        initialPluginId: String? = nil
    ) {
        self.init(
            store: store,
            initialTab: initialTab,
            initialPluginId: initialPluginId,
            podStorageRoots: .live
        )
    }

    init(
        store: PurahWorkspaceStore,
        initialTab: PreferencesTab = .general,
        initialPluginId: String? = nil,
        podStorageRoots: PluginStorageRoots
    ) {
        self.store = store
        self.initialPluginId = initialPluginId
        self.podStorageRoots = podStorageRoots
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
        .onDisappear {
            focusClearTask?.cancel()
            focusClearTask = nil
        }
    }

    private var rail: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) {
                    railSectionTitle("settings.rail.pods")

                    ForEach(podEntries) { entry in
                        podButton(entry)
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

            VStack(alignment: .leading, spacing: 4) {
                railSectionTitle("settings.rail.purah")

                ForEach(PreferencesSelection.globalCases) { item in
                    globalButton(item)
                }
            }
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .padding(.bottom, 8)

            signatureBlock
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
            selectFromRail(item)
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
            selectFromRail(item)
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
    private var signatureBlock: some View {
        if let appIcon = NSApp.applicationIconImage {
            Button {
                NSWorkspace.shared.open(Self.repositoryURL)
            } label: {
                HStack(spacing: 8) {
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

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Purah")
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                            .foregroundColor(
                                palette.style == .native ? Color.primary : .white
                            )

                        Text("v\(PurahCore.version)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isRepoBadgeHovered = $0 }
            .help("View Purah on GitHub")
            .accessibilityLabel("View Purah v\(PurahCore.version) on GitHub")
        }
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selection {
        case .pod(let id):
            PodSettingsPage(
                store: store,
                pluginId: id,
                storageRoots: podStorageRoots,
                onUninstalled: nil,
                onNavigate: focusTarget
            )
                .id(id)
        case .layout:
            VisualLayoutSimulatorView(store: store)
        case .general:
            GeneralSettingsView(store: store)
        case .motion:
            InteractionSettingsView(
                store: store,
                focusedPodId: focus.podId,
                focusNonce: focus.nonce
            )
        case .market:
            PluginMarketplaceView(store: store)
        case .permissions:
            SystemAccessSettingsView(store: store)
        case .system:
            DiagnosticReportView(
                store: store,
                focusedPodId: focus.podId,
                focusNonce: focus.nonce,
                storageRoots: podStorageRoots
            )
        }
    }

    private func focusTarget(_ target: PreferencesSelection, podId: String?) {
        focusClearTask?.cancel()
        focusClearTask = nil
        selection = target
        guard let podId else {
            focus.clearForManualSelection()
            return
        }

        focus.deliver(podId)
        let expected = focus
        focusClearTask?.cancel()
        focusClearTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_300_000_000)
            guard !Task.isCancelled, let expectedPodId = expected.podId else { return }
            focus.clearIfCurrent(podId: expectedPodId, nonce: expected.nonce)
            focusClearTask = nil
        }
    }

    private func selectFromRail(_ item: PreferencesSelection) {
        focusClearTask?.cancel()
        focusClearTask = nil
        focus.clearForManualSelection()
        selection = item
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
