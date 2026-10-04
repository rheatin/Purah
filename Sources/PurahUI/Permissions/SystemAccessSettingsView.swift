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

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 28))
                    .foregroundColor(palette.primaryAccent)
                    .modifier(OptionalGlow(color: palette.primaryAccent, enabled: palette.useGlow))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Native App Permissions & Access")
                        .font(palette.fontTitle)
                        .foregroundColor(palette.style == .native ? Color.primary : .white)
                    Text("Grant access for real-time synchronization with Calendar, Reminders, and Music")
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
            }

            Divider()
                .background(palette.borderColor)

            // Permission Cards
            VStack(spacing: 12) {
                // 1. Apple Calendar
                permissionRow(
                    icon: "calendar",
                    title: "Apple Calendar",
                    purpose: "Reads events and meetings to power timeline rails and calendar drawers",
                    status: permissions.calendarStatus,
                    onGrant: {
                        Task {
                            let granted = await permissions.requestCalendarAccess()
                            if granted {
                                SystemCalendarSyncService.shared.syncEvents(into: store)
                            }
                        }
                    },
                    onOpenSettings: {
                        permissions.openSystemSettings(for: "Privacy_Calendars")
                    }
                )

                // 2. Apple Reminders
                permissionRow(
                    icon: "checklist",
                    title: "Apple Reminders",
                    purpose: "Synchronizes tasks into tactile segments with quick completion support",
                    status: permissions.remindersStatus,
                    onGrant: {
                        Task {
                            let granted = await permissions.requestRemindersAccess()
                            if granted {
                                await SystemRemindersSyncService.shared.syncReminders(into: store)
                            }
                        }
                    },
                    onOpenSettings: {
                        permissions.openSystemSettings(for: "Privacy_Reminders")
                    }
                )

                // 3. Apple Music
                HStack(spacing: 14) {
                    Image(systemName: "music.note")
                        .font(.system(size: 22))
                        .foregroundColor(palette.primaryAccent)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Apple Music")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(palette.style == .native ? Color.primary : .white)
                            Text("Always Available")
                                .font(.system(size: 10, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.15))
                                .foregroundColor(.green)
                                .cornerRadius(4)
                        }
                        Text("Automatically observes track and playback state via macOS notifications")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }

                    Spacer()

                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title3)
                }
                .padding(12)
                .background(palette.surfaceBackground)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(palette.borderColor.opacity(0.4), lineWidth: 1)
                )
            }

            Spacer()

            Divider()
                .background(palette.borderColor)

            // Bottom action: Guarantee Access to All
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Permission Status")
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
        .frame(width: 580, height: 420)
    }

    private var summaryText: String {
        let calOk = permissions.calendarStatus.isGranted
        let remOk = permissions.remindersStatus.isGranted
        if calOk && remOk {
            return "All native services authorized with live synchronization."
        } else if calOk || remOk {
            return "Partial access granted. Click to complete authorization."
        } else {
            return "Permissions not granted yet. Using local sample data."
        }
    }

    @ViewBuilder
    private func permissionRow(
        icon: String,
        title: String,
        purpose: String,
        status: AccessStatus,
        onGrant: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundColor(palette.primaryAccent)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(palette.style == .native ? Color.primary : .white)

                    Text(status.title)
                        .font(.system(size: 10, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(statusColor(status).opacity(0.15))
                        .foregroundColor(statusColor(status))
                        .cornerRadius(4)
                }

                Text(purpose)
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .lineLimit(2)
            }

            Spacer()

            if status.isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title3)
            } else if status == .denied {
                Button("Settings", action: onOpenSettings)
                    .buttonStyle(.bordered)
                    .font(.caption)
            } else {
                Button("Grant Access", action: onGrant)
                    .buttonStyle(.borderedProminent)
                    .tint(palette.primaryAccent)
                    .font(.caption)
                    .foregroundColor(palette.style == .native ? Color.white : Color.black)
            }
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
