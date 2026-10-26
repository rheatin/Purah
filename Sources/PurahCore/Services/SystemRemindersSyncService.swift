// Sources/PurahCore/Services/SystemRemindersSyncService.swift
import Foundation
import EventKit
import Observation

@Observable
@MainActor
public final class SystemRemindersSyncService {
    public static let shared = SystemRemindersSyncService()

    @ObservationIgnored private lazy var eventStore = EKEventStore()
    @ObservationIgnored private var syncGeneration: UInt64 = 0
    public weak var boundStore: PurahWorkspaceStore?
    public private(set) var isSyncing: Bool = false
    public private(set) var lastSyncDate: Date?

    /// Reminders permission probe. Tests inject `.denied` so they exercise the
    /// in-memory fallback without touching the user's real Reminders database.
    @ObservationIgnored private let permissionStatus: @MainActor () -> AccessStatus

    /// Intentionally registers no `EKEventStoreChanged` observer.
    ///
    /// `TodoPluginState` (the mounted pod) already observes that notification
    /// and owns the authoritative `todos` array. Both sides used to observe it,
    /// so every Reminders edit ran two full EventKit fetches and raced to write
    /// `store._todos`. The service stays a stateless query layer.
    public init(permissionStatus: @escaping @MainActor () -> AccessStatus = {
        PermissionManager.status(from: EKEventStore.authorizationStatus(for: .reminder))
    }) {
        self.permissionStatus = permissionStatus
    }

    public func resetStore() {
        self.eventStore = EKEventStore()
    }

    public func fetchReminders(scope: RemindersScope = .allIncomplete) async -> [TodoItem] {
        eventStore.refreshSourcesIfNecessary()

        let status = permissionStatus()
        guard status.isGranted else { return [] }

        return await withCheckedContinuation { continuation in
            let predicate = eventStore.predicateForReminders(in: nil)
            eventStore.fetchReminders(matching: predicate) { ekReminders in
                Task { @MainActor in
                    guard let ekReminders = ekReminders else {
                        continuation.resume(returning: [])
                        return
                    }

                    let cal = Calendar.current
                    let today = Date()
                    let startOfToday = cal.startOfDay(for: today)
                    let endOfToday = cal.date(byAdding: .day, value: 1, to: startOfToday) ?? today
                    let endOfWeek = cal.date(byAdding: .day, value: 7, to: startOfToday) ?? today

                    let filtered = ekReminders.filter { rem in
                        switch scope {
                        case .allIncomplete:
                            return !rem.isCompleted
                        case .completed:
                            return rem.isCompleted
                        case .dueToday:
                            guard !rem.isCompleted, let dueComp = rem.dueDateComponents, let dueDate = cal.date(from: dueComp) else {
                                return false
                            }
                            return dueDate >= startOfToday && dueDate <= endOfToday
                        case .dueThisWeek:
                            guard !rem.isCompleted, let dueComp = rem.dueDateComponents, let dueDate = cal.date(from: dueComp) else {
                                return false
                            }
                            return dueDate >= startOfToday && dueDate <= endOfWeek
                        }
                    }

                    let mapped = filtered.map { rem in
                        let dueDate = rem.dueDateComponents.flatMap { cal.date(from: $0) }
                        let baseId = rem.calendarItemIdentifier
                        let dueTimestamp = dueDate.map { Int($0.timeIntervalSince1970) } ?? 0
                        let uniqueId = dueTimestamp > 0 ? "\(baseId)_\(dueTimestamp)" : baseId

                        return TodoItem(
                            id: uniqueId,
                            title: rem.title ?? "Untitled Reminder",
                            listTitle: rem.calendar?.title ?? "Reminders",
                            listColorHex: SystemCalendarSyncService.hexString(from: rem.calendar?.cgColor),
                            dueDate: dueDate,
                            isCompleted: rem.isCompleted
                        )
                    }
                    continuation.resume(returning: mapped)
                }
            }
        }
    }

    public func syncReminders(into store: PurahWorkspaceStore? = nil, scope: RemindersScope? = nil) async {
        if let store = store {
            self.boundStore = store
        }
        let targetStore = store ?? self.boundStore

        let status = permissionStatus()
        guard status.isGranted else {
            targetStore?.isUsingRealReminders = false
            return
        }

        isSyncing = true
        syncGeneration &+= 1
        let currentGen = syncGeneration

        let targetScope = scope ?? targetStore?.remindersScope ?? .allIncomplete
        let items = await fetchReminders(scope: targetScope)

        guard currentGen == self.syncGeneration else { return }

        if let targetStore = targetStore {
            targetStore.remindersScope = targetScope
            targetStore.isUsingRealReminders = true
            targetStore._todos = items
        }
        lastSyncDate = Date()
        isSyncing = false
    }

    public func addReminder(title: String, into store: PurahWorkspaceStore? = nil) async -> Bool {
        if let store = store {
            self.boundStore = store
        }
        let targetStore = store ?? self.boundStore

        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let status = permissionStatus()
        if status.isGranted, let calendar = eventStore.defaultCalendarForNewReminders() {
            let reminder = EKReminder(eventStore: eventStore)
            reminder.title = trimmed
            reminder.calendar = calendar
            do {
                try eventStore.save(reminder, commit: true)
                await syncReminders(into: targetStore)
                return true
            } catch {
                targetStore?._todos.append(TodoItem(title: trimmed))
                return true
            }
        } else {
            targetStore?._todos.append(TodoItem(title: trimmed))
            return true
        }
    }

    public func toggleCompletion(id: String, into store: PurahWorkspaceStore? = nil) async {
        if let store = store {
            self.boundStore = store
        }
        let targetStore = store ?? self.boundStore

        let status = permissionStatus()
        if status.isGranted {
            let baseIdentifier = id.components(separatedBy: "_").first ?? id
            if let item = eventStore.calendarItem(withIdentifier: baseIdentifier) as? EKReminder {
                item.isCompleted.toggle()
                do {
                    try eventStore.save(item, commit: true)
                    await syncReminders(into: targetStore)
                    return
                } catch {
                    DiagnosticLogger.shared.error("Reminders", "Failed to save reminder completion: \(error.localizedDescription)")
                }
            }
        }

        if let idx = targetStore?._todos.firstIndex(where: { $0.id == id }) {
            targetStore?._todos[idx].isCompleted.toggle()
        }
    }
}
