// Sources/PurahUI/Settings/PluginCenterSettingsView.swift
import SwiftUI
import PurahCore

public struct PluginCenterSettingsView: View {
    public let store: PurahWorkspaceStore
    @State private var selectedPluginId: String = "calendar"
    @State private var searchFilter: String = ""

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    public init(store: PurahWorkspaceStore) {
        self.store = store
        if let first = PluginRegistry.shared.allPlugins.first?.manifest.id {
            self._selectedPluginId = State(initialValue: first)
        }
    }

    private var filteredPlugins: [any PurahPodPlugin] {
        let all = PluginRegistry.shared.allPlugins
        if searchFilter.trimmingCharacters(in: .whitespaces).isEmpty {
            return all
        }
        return all.filter {
            $0.manifest.displayName.localizedCaseInsensitiveContains(searchFilter) ||
            $0.manifest.description.localizedCaseInsensitiveContains(searchFilter) ||
            $0.manifest.id.localizedCaseInsensitiveContains(searchFilter)
        }
    }

    public var body: some View {
        HStack(spacing: 0) {
            // Master: Left Sidebar Plugin List
            VStack(spacing: 8) {
                // Search bar
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("Filter plugins...", text: $searchFilter)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                .cornerRadius(6)
                .padding(.horizontal, 10)
                .padding(.top, 10)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 4) {
                        ForEach(filteredPlugins, id: \.manifest.id) { plugin in
                            let podId = plugin.manifest.id
                            let isSelected = selectedPluginId == podId
                            let isEnabled = store.pods.first(where: { $0.id == podId })?.isEnabled ?? true
                            let color = palette.podColor(for: podId, store: store)

                            Button {
                                selectedPluginId = podId
                            } label: {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(color)
                                        .frame(width: 8, height: 8)

                                    Image(systemName: plugin.manifest.systemIcon)
                                        .font(.system(size: 12))
                                        .foregroundColor(color)
                                        .frame(width: 16)

                                    Text(plugin.manifest.displayName)
                                        .font(.system(size: 11, weight: isSelected ? .bold : .medium, design: .rounded))
                                        .foregroundColor(isSelected ? (palette.style == .native ? Color.primary : .white) : .secondary)
                                        .lineLimit(1)

                                    Spacer()

                                    if !isEnabled {
                                        Text("OFF")
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundColor(.gray)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(isSelected ? palette.primaryAccent.opacity(0.15) : Color.clear)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(isSelected ? palette.primaryAccent.opacity(0.35) : Color.clear, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.tactile)
                        }
                    }
                    .padding(.horizontal, 8)
                }

                Spacer()

                // Bottom total plugin count
                HStack {
                    Text("\(PluginRegistry.shared.allPlugins.count) plugins registered")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
            .frame(width: 190)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))

            Divider()
                .background(palette.borderColor.opacity(0.4))

            // Detail: Right Plugin Settings Area
            if let activePlugin = PluginRegistry.shared.plugin(for: selectedPluginId) {
                let podId = activePlugin.manifest.id
                let podColor = palette.podColor(for: podId, store: store)
                let isEnabledBinding = Binding(
                    get: { store.pods.first(where: { $0.id == podId })?.isEnabled ?? true },
                    set: { _ in store.togglePodEnabled(id: podId) }
                )

                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 16) {
                        // Plugin Header Card
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

                        // Appearance & Color Card
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label("Theme Accent Color", systemImage: "paintpalette.fill")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(palette.style == .native ? Color.primary : .white)

                                Spacer()

                                if podId == "vitals" {
                                    HStack(spacing: 6) {
                                        HStack(spacing: 3) {
                                            Circle().fill(Color(red: 0.0, green: 0.90, blue: 0.60)).frame(width: 5, height: 5)
                                            Circle().fill(Color(red: 1.0, green: 0.72, blue: 0.15)).frame(width: 5, height: 5)
                                            Circle().fill(Color(red: 1.0, green: 0.28, blue: 0.38)).frame(width: 5, height: 5)
                                        }
                                        Text("Adaptive Telemetry Mode (Auto color based on load thresholds)")
                                            .font(.system(size: 9, weight: .medium, design: .rounded))
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color.primary.opacity(0.04))
                                    .cornerRadius(6)
                                } else {
                                    ColorPicker("", selection: Binding(
                                        get: { podColor },
                                        set: { newColor in
                                            if let hex = newColor.toHex() {
                                                store.setPodColorHex(podId: podId, hex: hex)
                                            }
                                        }
                                    ))
                                    .labelsHidden()
                                    .scaleEffect(0.85)

                                    if store.customPodColors[podId] != nil {
                                        Button("Reset") {
                                            store.customPodColors.removeValue(forKey: podId)
                                            store.savePersistentState()
                                        }
                                        .buttonStyle(.tactile)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(palette.primaryAccent)
                                    }
                                }
                            }

                            HStack(spacing: 8) {
                                Label("Default Edge: \(activePlugin.manifest.defaultEdge.rawValue.capitalized)", systemImage: "sidebar.squares.left")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)

                                Text("·")
                                    .foregroundColor(.gray)

                                Label("Preferred: \(activePlugin.manifest.preferredZone.defaultLocalizedKey.localized)", systemImage: "hand.tap.fill")
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

                        // Dedicated Isolated Plugin Settings View
                        if let customSettings = activePlugin.makeSettingsView(store: store) {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("Plugin Configuration", systemImage: "gearshape.2.fill")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(palette.style == .native ? Color.primary : .white)

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

                        Spacer()
                    }
                    .padding(16)
                }
            } else {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "puzzlepiece.extension")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("Select a plugin on the left to configure")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
