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

    public init(store: PurahWorkspaceStore, initialPluginId: String? = nil) {
        self.store = store
        if let id = initialPluginId {
            self._selectedPluginId = State(initialValue: id)
        } else if let first = PluginRegistry.shared.allPlugins.first?.manifest.id {
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
            VStack(spacing: 8) {
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
                            let isEnabled =
                                store.pods.first(where: { $0.id == podId })?.isEnabled ?? true
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
                                        .font(
                                            .system(
                                                size: 11,
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

                                    Spacer()

                                    if !isEnabled {
                                        Text("OFF")
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundColor(.gray)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(
                                            isSelected
                                                ? palette.primaryAccent.opacity(0.15)
                                                : Color.clear
                                        )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(
                                            isSelected
                                                ? palette.primaryAccent.opacity(0.35)
                                                : Color.clear,
                                            lineWidth: 1
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                }

                Spacer()

                HStack {
                    Text(
                        String(
                            format: "plugins.registeredCount".localized,
                            PluginRegistry.shared.allPlugins.count
                        )
                    )
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

            PodSettingsPage(
                store: store,
                pluginId: selectedPluginId,
                onUninstalled: {
                    if let next = PluginRegistry.shared.allPlugins.first?.manifest.id {
                        selectedPluginId = next
                    }
                }
            )
            .id(selectedPluginId)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
