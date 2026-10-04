// Sources/PurahCore/Permissions/PermissionManager.swift
import Foundation
import EventKit
import AppKit
import Observation

public enum AccessStatus: String, Codable, Sendable, CaseIterable {
    case authorized
    case notDetermined
    case denied
    case restricted

    public var title: String {
        switch self {
        case .authorized: return "已授权 (Authorized)"
        case .notDetermined: return "未决定 (Not Determined)"
        case .denied: return "已拒绝 (Denied)"
        case .restricted: return "受系统限制 (Restricted)"
        }
    }

    public var isGranted: Bool {
        self == .authorized
    }
}

@Observable
public final class PermissionManager: @unchecked Sendable {
    public static let shared = PermissionManager()

    public private(set) var calendarStatus: AccessStatus = .notDetermined
    public private(set) var remindersStatus: AccessStatus = .notDetermined
    public private(set) var musicStatus: AccessStatus = .authorized

    private var eventStore = EKEventStore()

    public init() {
        refreshStatuses()
    }

    public func refreshStatuses() {
        eventStore.reset()
        let calEKStatus = EKEventStore.authorizationStatus(for: .event)
        self.calendarStatus = Self.status(from: calEKStatus)

        let remEKStatus = EKEventStore.authorizationStatus(for: .reminder)
        self.remindersStatus = Self.status(from: remEKStatus)

        // Apple Music does not require TCC permissions for DistributedNotificationCenter
        self.musicStatus = .authorized
    }

    public static func status(from ekStatus: EKAuthorizationStatus) -> AccessStatus {
        switch ekStatus {
        case .notDetermined:
            return .notDetermined
        case .restricted:
            return .restricted
        case .denied:
            return .denied
        case .authorized:
            return .authorized
        case .fullAccess:
            return .authorized
        case .writeOnly:
            return .authorized
        @unknown default:
            return .notDetermined
        }
    }

    public func requestCalendarAccess() async -> Bool {
        do {
            let granted: Bool
            if #available(macOS 14.0, *) {
                granted = try await eventStore.requestFullAccessToEvents()
            } else {
                granted = try await eventStore.requestAccess(to: .event)
            }
            refreshStatuses()
            SystemCalendarSyncService.shared.resetStore()
            return granted
        } catch {
            refreshStatuses()
            return false
        }
    }

    public func requestRemindersAccess() async -> Bool {
        do {
            let granted: Bool
            if #available(macOS 14.0, *) {
                granted = try await eventStore.requestFullAccessToReminders()
            } else {
                granted = try await eventStore.requestAccess(to: .reminder)
            }
            refreshStatuses()
            SystemRemindersSyncService.shared.resetStore()
            return granted
        } catch {
            refreshStatuses()
            return false
        }
    }

    public func openSystemSettings(for service: String = "Privacy_Calendars") {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(service)") {
            NSWorkspace.shared.open(url)
        }
    }

    public func guaranteeAllAccess() async -> (calendar: Bool, reminders: Bool) {
        let cal = await requestCalendarAccess()
        let rem = await requestRemindersAccess()
        return (cal, rem)
    }
}
