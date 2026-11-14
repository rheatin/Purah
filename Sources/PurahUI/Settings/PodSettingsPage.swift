// Sources/PurahUI/Settings/PodSettingsPage.swift
import SwiftUI
import PurahCore

@MainActor
enum PodAlertSummary {
    static func text(
        style: PluginAlertStyle,
        channels: Set<AlertChannel>,
        podEnabled: Bool,
        globalChannels: Set<AlertChannel>?
    ) -> String {
        guard podEnabled else {
            return "podPage.silenced".localized
        }
        guard let globalChannels else {
            return "podPage.alertsOff".localized
        }

        let effectiveChannels = channels.intersection(globalChannels)
        guard !effectiveChannels.isEmpty else {
            return "podPage.noChannels".localized
        }

        let channelNames = AlertChannel.allCases
            .filter(effectiveChannels.contains)
            .map(channelTitle)
            .joined(separator: " + ")
        return "\(style.localizedDisplayName) · \(channelNames)"
    }

    private static func channelTitle(_ channel: AlertChannel) -> String {
        switch channel {
        case .railEffect:
            "interaction.alerts.channel.railEffect".localized
        case .toast:
            "interaction.alerts.channel.toast".localized
        case .sound:
            "interaction.alerts.channel.sound".localized
        }
    }
}

@MainActor
enum PodStorageSummary {
    static func text(
        assetsBytes: Int64,
        dataBytes: Int64,
        cacheBytes: Int64
    ) -> String {
        String(
            format: "podPage.storageSummary".localized,
            compactSize(assetsBytes + dataBytes + cacheBytes),
            compactSize(assetsBytes),
            compactSize(cacheBytes)
        )
    }

    private static func compactSize(_ bytes: Int64) -> String {
        bytes == 0 ? "0" : PurahPluginFileStorage.format(bytes)
    }
}

/// The settings detail for one pod.
///
/// Preferences and the plugin center both route here so a pod has one settings
/// page no matter which index the person used to reach it.
public struct PodSettingsPage: View {
    public let store: PurahWorkspaceStore
    public let pluginId: String

    private let storageRoots: PluginStorageRoots
    private let onNavigate: ((PreferencesSelection, String?) -> Void)?
    let onUninstalled: (() -> Void)?
    @State private var confirmingUninstall = false
    @State private var storageMeasurement: PluginStorageMeasurement?

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    public init(
        store: PurahWorkspaceStore,
        pluginId: String,
        onNavigate: ((PreferencesSelection, String?) -> Void)? = nil
    ) {
        self.store = store
        self.pluginId = pluginId
        self.storageRoots = .live
        self.onNavigate = onNavigate
        self.onUninstalled = nil
    }

    init(
        store: PurahWorkspaceStore,
        pluginId: String,
        storageRoots: PluginStorageRoots,
        onUninstalled: (() -> Void)?,
        onNavigate: ((PreferencesSelection, String?) -> Void)?
    ) {
        self.store = store
        self.pluginId = pluginId
        self.storageRoots = storageRoots
        self.onNavigate = onNavigate
        self.onUninstalled = onUninstalled
    }

    public var body: some View {
        if let activePlugin = PluginRegistry.shared.plugin(for: pluginId) {
            pluginDetail(activePlugin)
        } else {
            unregisteredPlugin
        }
    }

    private func pluginDetail(_ activePlugin: any PurahPodPlugin) -> some View {
        let podId = activePlugin.manifest.id
        let podColor = palette.podColor(for: podId, store: store)
        let isAdaptiveTelemetry =
            activePlugin.usesAdaptiveTelemetryColor || podId == "vitals"
        let isEnabledBinding = Binding(
            get: { store.pods.first(where: { $0.id == podId })?.isEnabled ?? true },
            set: { _ in store.togglePodEnabled(id: podId) }
        )

        return ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(podColor.opacity(0.18))
                            .frame(width: 44, height: 44)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(podColor.opacity(0.7), lineWidth: 1.2)
                            )
                        Image(systemName: activePlugin.manifest.systemIcon)
                            .font(.system(size: 20))
                            .foregroundColor(podColor)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(activePlugin.manifest.displayName)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundColor(palette.style == .native ? Color.primary : .white)

                            Text("v\(activePlugin.manifest.version)")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.primary.opacity(0.08))
                                .cornerRadius(3)

                            Spacer()

                            Toggle("", isOn: isEnabledBinding)
                                .toggleStyle(.switch)
                                .scaleEffect(0.75)
                                .accessibilityLabel(activePlugin.manifest.displayName)
                        }

                        Text(activePlugin.manifest.description)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(12)
                .background(palette.surfaceBackground)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(palette.borderColor.opacity(0.4), lineWidth: 1)
                )

                appearanceCard(
                    activePlugin,
                    podId: podId,
                    isAdaptiveTelemetry: isAdaptiveTelemetry
                )

                if let customSettings = activePlugin.makeSettingsView(store: store) {
                    customSettings
                }

                if activePlugin.manifest.supportsAlerts {
                    pointerCard(
                        title: "podPage.alerts".localized,
                        icon: "bell.badge",
                        summary: alertSummary(activePlugin, podId: podId),
                        target: .motion,
                        podId: podId
                    )
                }

                pointerCard(
                    title: "podPage.storage".localized,
                    icon: "internaldrive",
                    summary: storageSummary,
                    target: .system,
                    podId: podId
                )

                managementCard(podId: podId)

                Spacer()
            }
            .padding(16)
        }
        .task(id: pluginId) {
            await loadStorageMeasurement()
        }
    }

    private func appearanceCard(
        _ activePlugin: any PurahPodPlugin,
        podId: String,
        isAdaptiveTelemetry: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Theme Accent Color", systemImage: "paintpalette.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(palette.style == .native ? Color.primary : .white)
                    .lineLimit(1)

                Spacer()

                if isAdaptiveTelemetry {
                    HStack(spacing: 6) {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(Color(red: 0.0, green: 0.90, blue: 0.60))
                                .frame(width: 5, height: 5)
                            Circle()
                                .fill(Color(red: 1.0, green: 0.72, blue: 0.15))
                                .frame(width: 5, height: 5)
                            Circle()
                                .fill(Color(red: 1.0, green: 0.28, blue: 0.38))
                                .frame(width: 5, height: 5)
                        }
                        Text("plugins.adaptiveTelemetry".localized)
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(6)
                } else if store.customPodColors[podId] != nil {
                    Button("Reset") {
                        store.customPodColors.removeValue(forKey: podId)
                        store.savePersistentState()
                    }
                    .buttonStyle(.tactile)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(palette.primaryAccent)
                }
            }

            if !isAdaptiveTelemetry {
                PurahColorPickerField(
                    store: store,
                    podId: podId,
                    defaultHex: activePlugin.manifest.defaultColorHex,
                    isCustom: store.customPodColors[podId] != nil
                )
            }

            HStack(spacing: 8) {
                Label(
                    "Default Edge: \(activePlugin.manifest.defaultEdge.rawValue.capitalized)",
                    systemImage: "sidebar.squares.left"
                )
                .font(.system(size: 9))
                .foregroundColor(.secondary)

                Text("·")
                    .foregroundColor(.gray)

                Label(
                    "Preferred: \(activePlugin.manifest.preferredZone.defaultLocalizedKey.localized)",
                    systemImage: "hand.tap.fill"
                )
                .font(.system(size: 9))
                .foregroundColor(.secondary)
            }

            if activePlugin is DynamicABIPodPlugin, activePlugin.supportedDrawerModes.contains(.stepped) {
                Divider()
                    .background(palette.borderColor.opacity(0.25))

                VStack(alignment: .leading, spacing: 8) {
                    PurahStackedDecomposeNoticeView(podId: podId, store: store)

                    HStack {
                        Text("Rail Display Mode")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(palette.style == .native ? Color.primary : .white)

                        Spacer()

                        PurahThemedSegmentedPicker(
                            options: [false, true],
                            selection: Binding<Bool>(
                                get: { activePlugin.isDecomposed(store: store) },
                                set: { newValue in
                                    activePlugin.setDecomposed(newValue, store: store)
                                    if newValue { store.ensurePodFitsDecomposedChips(podId: podId) }
                                    store.invalidateLayoutCache()
                                    store.savePersistentState()
                                    store.onWindowsRebuildNeeded?()
                                }
                            ),
                            titleForOption: { $0 ? "Stepped Chips" : "Composite Bar" }
                        )
                        .frame(width: 190)
                        .disabled(store.isInSharedMajorPod(podId: podId))
                    }
                }
            }
        }
        .padding(12)
        .background(palette.surfaceBackground)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(palette.borderColor.opacity(0.4), lineWidth: 1)
        )
    }

    private func pointerCard(
        title: String,
        icon: String,
        summary: String,
        target: PreferencesSelection,
        podId: String
    ) -> some View {
        Button {
            onNavigate?(target, podId)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(palette.primaryAccent)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(palette.style == .native ? Color.primary : .white)
                        .lineLimit(1)

                    Text(summary)
                        .font(.system(size: 9.5, design: .rounded))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(palette.surfaceBackground)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(palette.borderColor.opacity(0.4), lineWidth: 1)
            )
        }
        .buttonStyle(.tactile)
        .accessibilityLabel("\(title), \(summary)")
    }

    private func alertSummary(
        _ activePlugin: any PurahPodPlugin,
        podId: String
    ) -> String {
        let style = store.resolvedAlertStyle(
            declared: activePlugin.alertStyle(store: store),
            podId: podId
        )
        return PodAlertSummary.text(
            style: style,
            channels: store.allowedChannels(forPodId: podId),
            podEnabled: !store.disabledAlertPodIds.contains(podId),
            globalChannels: store.isAlertMasterEnabled ? store.alertChannels : nil
        )
    }

    private var storageSummary: String {
        guard let storageMeasurement else { return "…" }
        return PodStorageSummary.text(
            assetsBytes: storageMeasurement.assetsBytes,
            dataBytes: storageMeasurement.dataBytes,
            cacheBytes: storageMeasurement.cacheBytes
        )
    }

    private func loadStorageMeasurement() async {
        storageMeasurement = nil
        let pluginId = pluginId
        let roots = storageRoots
        let worker = Task.detached(priority: .utility) {
            PluginStorageScanner.measure(pluginId: pluginId, roots: roots)
        }
        let measurement = await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
        guard !Task.isCancelled else { return }
        storageMeasurement = measurement
    }

    private func managementCard(podId: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Management", systemImage: "trash")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(palette.style == .native ? Color.primary : .white)
                .lineLimit(1)

            Divider()
                .background(palette.borderColor.opacity(0.3))

            HStack {
                Text("plugins.uninstall.desc".localized)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                Spacer()

                Button {
                    if confirmingUninstall {
                        store.marketManager.uninstall(id: podId)
                        confirmingUninstall = false
                        onUninstalled?()
                    } else {
                        withAnimation { confirmingUninstall = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                            withAnimation { confirmingUninstall = false }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash.fill")
                        Text(confirmingUninstall ? "Confirm Uninstall" : "Uninstall")
                    }
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4.5)
                    .background(Color.red)
                    .cornerRadius(6)
                }
                .buttonStyle(.tactile)
            }
        }
        .padding(12)
        .background(palette.surfaceBackground)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(palette.borderColor.opacity(0.4), lineWidth: 1)
        )
    }

    private var unregisteredPlugin: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "puzzlepiece.extension")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text("This pod is not registered with a plugin implementation.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text(pluginId)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
