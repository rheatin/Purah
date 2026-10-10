// Sources/PurahUI/Permissions/SystemAccessSettingsView.swift
import SwiftUI
import PurahCore

public struct SystemAccessSettingsView: View {
    public let store: PurahWorkspaceStore
    private var permissions: PermissionManager {
        PermissionManager.shared
    }
    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    public init(store: PurahWorkspaceStore) {
        self.store = store
    }

    private var groupedPermissions: [(permission: PluginPermission, manifests: [PurahPluginManifest])] {
        let allManifests = PluginRegistry.shared.allCatalogPlugins.map(\.manifest)
        var map: [PluginPermission: [PurahPluginManifest]] = [:]
        for manifest in allManifests {
            for perm in manifest.permissions {
                map[perm, default: []].append(manifest)
            }
        }
        // Ordered by case order in PluginPermission
        return PluginPermission.allCases.compactMap { perm in
            guard let manifests = map[perm], !manifests.isEmpty else { return nil }
            return (perm, manifests)
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 28))
                    .foregroundColor(palette.primaryAccent)
                    .modifier(OptionalGlow(color: palette.primaryAccent, enabled: palette.useGlow))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Plugin Permissions & Privacy Matrix")
                        .font(palette.fontTitle)
                        .foregroundColor(palette.style == .native ? Color.primary : .white)
                    Text("Dynamic inspection of system capabilities required by installed plugins and functional impacts when denied")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                Spacer()

                Button {
                    permissions.refreshStatuses()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                        .foregroundColor(palette.primaryAccent)
                }
                .buttonStyle(.plain)
                .help("Refresh permission statuses")
            }

            Divider()
                .background(palette.borderColor)

            // Dynamic Permission Cards List
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 12) {
                    ForEach(groupedPermissions, id: \.permission.rawValue) { item in
                        dynamicPermissionCard(permission: item.permission, manifests: item.manifests)
                    }
                }
                .padding(.trailing, 4)
            }
            .frame(maxHeight: 280)

            Divider()
                .background(palette.borderColor)

            // Bottom action: Guarantee Access to All
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Permission Summary")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(palette.style == .native ? Color.primary : .white)
                    Text(summaryText)
                        .font(.caption2)
                        .foregroundColor(.gray)
                }

                Spacer()

                Button {
                    Task { @MainActor in
                        _ = await permissions.guaranteeAllAccess()
                        SystemCalendarSyncService.shared.syncEvents(into: store, scope: store.calendarScope)
                        await SystemRemindersSyncService.shared.syncReminders(into: store, scope: store.remindersScope)
                        NSApp.activate(ignoringOtherApps: true)
                        for win in NSApp.windows where win.title.contains("Purah") {
                            win.makeKeyAndOrderFront(nil)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                        Text("Grant All Permissions")
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(palette.style == .native ? Color.white : Color.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(palette.primaryAccent)
                    .cornerRadius(8)
                    .modifier(OptionalGlow(color: palette.primaryAccent, enabled: palette.useGlow))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .frame(width: 580, height: 440)
    }

    private var summaryText: String {
        let calOk = permissions.calendarStatus.isGranted
        let remOk = permissions.remindersStatus.isGranted
        if calOk && remOk {
            return "All sensitive native services authorized with live synchronization."
        } else if calOk || remOk {
            return "Partial access granted. Click to complete authorization."
        } else {
            return "Some permissions pending. Affected plugins will run with degraded features."
        }
    }

    @ViewBuilder
    private func dynamicPermissionCard(
        permission: PluginPermission,
        manifests: [PurahPluginManifest]
    ) -> some View {
        let status = permissions.status(for: permission)

        VStack(alignment: .leading, spacing: 8) {
            // Row 1: Icon + Title + Status + Action
            HStack(spacing: 12) {
                Image(systemName: permission.icon)
                    .font(.system(size: 20))
                    .foregroundColor(palette.primaryAccent)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(permission.rawValue)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(palette.style == .native ? Color.primary : .white)

                        Text(status.title)
                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(statusColor(status).opacity(0.15))
                            .foregroundColor(statusColor(status))
                            .cornerRadius(4)
                    }

                    Text(permission.securityDescription)
                        .font(.caption2)
                        .foregroundColor(.gray)
                }

                Spacer()

                if status.isGranted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title3)
                } else if status == .denied {
                    if let anchor = permission.privacySettingsAnchor {
                        Button("Settings") {
                            permissions.openSystemSettings(for: anchor)
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)
                    } else {
                        Text("Denied")
                            .font(.caption2)
                            .foregroundColor(.red)
                    }
                } else {
                    Button("Grant Access") {
                        Task {
                            _ = await permissions.requestAccess(for: permission)
                            if permission == .calendar {
                                SystemCalendarSyncService.shared.syncEvents(into: store)
                            } else if permission == .reminders {
                                await SystemRemindersSyncService.shared.syncReminders(into: store)
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(palette.primaryAccent)
                    .font(.caption)
                    .foregroundColor(palette.style == .native ? Color.white : Color.black)
                }
            }

            // Row 2: Requesting Plugins Badges
            HStack(spacing: 6) {
                Text("Requested by:")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundColor(.secondary)

                ForEach(manifests) { manifest in
                    HStack(spacing: 4) {
                        Image(systemName: manifest.systemIcon)
                            .font(.system(size: 8.5))
                        Text(manifest.displayName)
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12))
                    .cornerRadius(4)
                    .foregroundColor(palette.style == .native ? .primary : .white)
                }
            }

            // Row 3: Consequence / What won't work if denied
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9.5))
                    .foregroundColor(status.isGranted ? .secondary : .orange)
                    .padding(.top, 1)

                Text(permission.deniedImpactDescription)
                    .font(.system(size: 10))
                    .foregroundColor(status.isGranted ? .secondary : .orange)
                    .lineLimit(2)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(status.isGranted ? Color.secondary.opacity(0.06) : Color.orange.opacity(0.10))
            .cornerRadius(6)
        }
        .padding(12)
        .background(palette.surfaceBackground)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(palette.borderColor.opacity(0.4), lineWidth: 1)
        )
    }

    private func statusColor(_ status: AccessStatus) -> Color {
        switch status {
        case .authorized: return .green
        case .notDetermined: return .orange
        case .denied, .restricted: return .red
        }
    }
}
