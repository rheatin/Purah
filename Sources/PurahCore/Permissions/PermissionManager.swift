// Sources/PurahCore/Permissions/PermissionManager.swift
import Foundation
// EventKit's headers predate Swift concurrency: `EKEventStore` is neither
// `Sendable` nor main-actor isolated, and its `request…` methods are imported
// as non-isolated `async`, so a Swift 6 compiler reads `await
// eventStore.requestFullAccessToEvents()` from `@MainActor` code as sending a
// non-Sendable value across an isolation boundary. `@preconcurrency` states
// what is actually true — the class is only used from the main actor — instead
// of silencing the diagnostic at the call site.
@preconcurrency import EventKit
import AVFoundation
import AppKit
import Observation

public enum AccessStatus: String, Codable, Sendable, CaseIterable {
    case authorized
    case notDetermined
    case denied
    case restricted
    case standardCapability

    public var title: String {
        switch self {
        case .authorized: return "Authorized"
        case .notDetermined: return "Not Determined"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        case .standardCapability: return "No Prompt Needed"
        }
    }

    public var isGranted: Bool {
        self == .authorized || self == .standardCapability
    }
}

@Observable
@MainActor
public final class PermissionManager {
    public static let shared = PermissionManager()

    public private(set) var calendarStatus: AccessStatus = .notDetermined
    public private(set) var remindersStatus: AccessStatus = .notDetermined
    public private(set) var musicStatus: AccessStatus = .standardCapability
    public private(set) var microphoneStatus: AccessStatus = .notDetermined

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

        // Apple Music observes standard distributed notifications without TCC prompt
        self.musicStatus = .standardCapability

        self.microphoneStatus = Self.status(fromCaptureAuthorization:
            AVCaptureDevice.authorizationStatus(for: .audio))
    }

    public func status(for permission: PluginPermission) -> AccessStatus {
        switch permission {
        case .calendar: return calendarStatus
        case .reminders: return remindersStatus
        case .microphone: return microphoneStatus
        case .appleMusic, .pasteboard, .machTelemetry, .shellExecution, .fileSystem:
            return .standardCapability
        }
    }

    /// Exhaustive on purpose: a `default: return true` here silently granted
    /// every capability added later, so a new TCC-gated permission would have
    /// looked authorized and never prompted. Adding a case now fails to
    /// compile until someone decides what it means.
    public func requestAccess(for permission: PluginPermission) async -> Bool {
        switch permission {
        case .calendar: return await requestCalendarAccess()
        case .reminders: return await requestRemindersAccess()
        case .microphone: return await requestMicrophoneAccess()
        case .appleMusic, .pasteboard, .machTelemetry, .shellExecution, .fileSystem:
            return true
        }
    }

    public static func status(fromCaptureAuthorization status: AVAuthorizationStatus) -> AccessStatus {
        switch status {
        case .authorized: return .authorized
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .notDetermined
        }
    }

    public static func status(from ekStatus: EKAuthorizationStatus) -> AccessStatus {
        switch ekStatus {
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .denied: .denied
        case .authorized, .fullAccess, .writeOnly: .authorized
        @unknown default: .notDetermined
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

    /// The system prompt names Purah, because TCC keys on the app. That is why
    /// a plugin can only *ask the host* for this: a dylib that called
    /// `AVCaptureDevice.requestAccess` itself would still raise the same app
    /// sheet, and the host would have no chance to check the declaration first.
    public func requestMicrophoneAccess() async -> Bool {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        refreshStatuses()
        return granted
    }

    public func openSystemSettings(for service: String = "Privacy_Calendars") {        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(service)") {
            NSWorkspace.shared.open(url)
        }
    }

    public func guaranteeAllAccess() async -> (calendar: Bool, reminders: Bool) {
        let cal = await requestCalendarAccess()
        let rem = await requestRemindersAccess()
        return (cal, rem)
    }

    // MARK: - Runtime Capability Enforcement & Sandboxing
    public func enforceCapability(pluginId: String, permission: PluginPermission, declaredIn permissions: [PluginPermission]) throws {
        guard permissions.contains(permission) else {
            throw PurahCapabilityError.permissionNotDeclared(pluginId: pluginId, permission: permission)
        }
        let stat = status(for: permission)
        guard stat.isGranted else {
            throw PurahCapabilityError.permissionNotAuthorized(pluginId: pluginId, permission: permission)
        }
    }
}

public enum PurahCapabilityError: Error, LocalizedError, Sendable, Equatable {
    case permissionNotDeclared(pluginId: String, permission: PluginPermission)
    case permissionNotAuthorized(pluginId: String, permission: PluginPermission)

    public var errorDescription: String? {
        switch self {
        case .permissionNotDeclared(let id, let perm):
            return "Plugin '\(id)' attempted to access capability '\(perm.rawValue)' without declaring it in manifest.permissions."
        case .permissionNotAuthorized(let id, let perm):
            return "Plugin '\(id)' requested capability '\(perm.rawValue)' which is not authorized by system policy."
        }
    }
}
