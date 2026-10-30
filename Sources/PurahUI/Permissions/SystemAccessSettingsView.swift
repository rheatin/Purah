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

    /// Shared with the onboarding permission panel — see `PermissionInventory`.
    private var groupedPermissions: [PermissionGroup] {
        PermissionInventory.groups()
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
                    Text("permissions.matrix.title".localized)
                        .font(palette.fontTitle)
                        .foregroundColor(palette.style == .native ? Color.primary : .white)
                    Text("permissions.matrix.subtitle".localized)
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
                .help("help.refreshPermissions".localized)
                .accessibilityLabel("help.refreshPermissions".localized)
            }

            Divider()
                .background(palette.borderColor)

            // Dynamic Permission Cards List
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 14) {
                    let privacyPermissions = groupedPermissions.filter { $0.permission.isTCCRestricted }
                    let standardCapabilities = groupedPermissions.filter { !$0.permission.isTCCRestricted }

                    if !privacyPermissions.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("permissions.tcc.title".localized)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(palette.primaryAccent)
                                .textCase(.uppercase)

                            ForEach(privacyPermissions, id: \.permission.rawValue) { item in
                                dynamicPermissionCard(permission: item.permission, manifests: item.manifests)
                            }
                        }
                    }

                    if !standardCapabilities.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("permissions.ambient.title".localized)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.secondary)
                                .textCase(.uppercase)

                            ForEach(standardCapabilities, id: \.permission.rawValue) { item in
                                dynamicPermissionCard(permission: item.permission, manifests: item.manifests)
                            }
                        }
                    }

                    let unsupported = unsupportedDeclarations
                    if !unsupported.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("permissions.unsupported.title".localized)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.orange)
                                .textCase(.uppercase)

                            ForEach(unsupported, id: \.self) { line in
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 9.5))
                                        .foregroundColor(.orange)
                                    Text(line)
                                        .font(.system(size: 10))
                                        .foregroundColor(.orange)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.orange.opacity(0.10))
                                .cornerRadius(6)
                            }
                        }
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
                    Text("permissions.status.title".localized)
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
                        Text("permissions.grantAll".localized)
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
        let calOk = permissions.calendarStatus == .authorized
        let remOk = permissions.remindersStatus == .authorized
        if calOk && remOk {
            return "All macOS privacy permissions authorized with live synchronization."
        } else if calOk || remOk {
            return "Calendar or Reminders permission pending. Affected plugins run with sample data."
        } else {
            return "Privacy permissions not granted yet. Calendar & Reminders will run with local sample data."
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

                if status == .standardCapability {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.shield")
                            .font(.system(size: 10))
                        Text("permissions.status.ready".localized)
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.12))
                    .cornerRadius(4)
                } else if status == .authorized {
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
                        Text("permissions.status.denied".localized)
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
                Text("permissions.requestedBy".localized)
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

    /// Capability names plugins declared that this build has never heard of.
    /// The host cannot grant them — each one needs its own system API — but a
    /// silent drop would look like the plugin simply has no requirements.
    private var unsupportedDeclarations: [String] {
        PluginRegistry.shared.allCatalogPlugins
            .flatMap { entry in
                entry.manifest.unsupportedPermissions.map {
                    String(format: "permissions.unsupported".localized, entry.manifest.displayName, $0)
                }
            }
            .sorted()
    }

    private func statusColor(_ status: AccessStatus) -> Color {
        switch status {
        case .authorized: return .green
        case .standardCapability: return .blue
        case .notDetermined: return .orange
        case .denied, .restricted: return .red
        }
    }
}
