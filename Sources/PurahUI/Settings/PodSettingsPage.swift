// Sources/PurahUI/Settings/PodSettingsPage.swift
import SwiftUI
import PurahCore

/// The settings detail for one pod.
///
/// Preferences and the plugin center both route here so a pod has one settings
/// page no matter which index the person used to reach it.
public struct PodSettingsPage: View {
    public let store: PurahWorkspaceStore
    public let pluginId: String

    let onUninstalled: (() -> Void)?
    @State private var confirmingUninstall = false

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    public init(store: PurahWorkspaceStore, pluginId: String) {
        self.store = store
        self.pluginId = pluginId
        self.onUninstalled = nil
    }

    init(
        store: PurahWorkspaceStore,
        pluginId: String,
        onUninstalled: (() -> Void)?
    ) {
        self.store = store
        self.pluginId = pluginId
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
                    VStack(alignment: .leading, spacing: 10) {
                        Label("settings.title".localized, systemImage: "gearshape.2.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(palette.style == .native ? Color.primary : .white)
                            .lineLimit(1)

                        Divider()
                            .background(palette.borderColor.opacity(0.3))

                        customSettings
                    }
                    .padding(12)
                    .background(palette.surfaceBackground)
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(palette.borderColor.opacity(0.4), lineWidth: 1)
                    )
                }

                managementCard(podId: podId)

                Spacer()
            }
            .padding(16)
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
        }
        .padding(12)
        .background(palette.surfaceBackground)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(palette.borderColor.opacity(0.4), lineWidth: 1)
        )
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
