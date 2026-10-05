// Sources/PurahCore/Services/SystemRemindersSyncService.swift
import Foundation
import EventKit
import Observation

@Observable
public final class SystemRemindersSyncService: @unchecked Sendable {
    public static let shared = SystemRemindersSyncService()

    private var eventStore = EKEventStore()
    public weak var boundStore: PurahWorkspaceStore?
    public private(set) var isSyncing: Bool = false
    public private(set) var lastSyncDate: Date?

    public init() {
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.syncReminders(into: self?.boundStore)
            }
        }
    }

    public func resetStore() {
        self.eventStore = EKEventStore()
    }

    public func fetchReminders(scope: RemindersScope = .allIncomplete) async -> [TodoItem] {
        eventStore.refreshSourcesIfNecessary()

        let status = PermissionManager.status(from: EKEventStore.authorizationStatus(for: .reminder))
        guard status.isGranted else { return [] }

        return await withCheckedContinuation { continuation in
            let predicate = eventStore.predicateForReminders(in: nil)
            eventStore.fetchReminders(matching: predicate) { ekReminders in
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
                        dueDate: dueDate,
                        isCompleted: rem.isCompleted
                    )
                }
                continuation.resume(returning: mapped)
            }
        }
    }

    public func syncReminders(into store: PurahWorkspaceStore? = nil, scope: RemindersScope? = nil) async {
        if let store = store {
            self.boundStore = store
        }
        let targetStore = store ?? self.boundStore

        let status = PermissionManager.status(from: EKEventStore.authorizationStatus(for: .reminder))
        guard status.isGranted else {
            targetStore?.isUsingRealReminders = false
            return
        }

        isSyncing = true
        let targetScope = scope ?? targetStore?.remindersScope ?? .allIncomplete
        let items = await fetchReminders(scope: targetScope)

        if let targetStore = targetStore {
            targetStore.remindersScope = targetScope
            targetStore.isUsingRealReminders = true
            targetStore.todos = items
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

        let status = PermissionManager.status(from: EKEventStore.authorizationStatus(for: .reminder))
        if status.isGranted, let calendar = eventStore.defaultCalendarForNewReminders() {
            let reminder = EKReminder(eventStore: eventStore)
            reminder.title = trimmed
            reminder.calendar = calendar
            do {
                try eventStore.save(reminder, commit: true)
                await syncReminders(into: targetStore)
                return true
            } catch {
                targetStore?.todos.append(TodoItem(title: trimmed))
                return true
            }
        } else {
            targetStore?.todos.append(TodoItem(title: trimmed))
            return true
        }
    }

    public func toggleCompletion(id: String, into store: PurahWorkspaceStore? = nil) async {
        if let store = store {
            self.boundStore = store
        }
        let targetStore = store ?? self.boundStore

        let status = PermissionManager.status(from: EKEventStore.authorizationStatus(for: .reminder))
        if status.isGranted {
            let baseIdentifier = id.components(separatedBy: "_").first ?? id
            if let item = eventStore.calendarItem(withIdentifier: baseIdentifier) as? EKReminder {
                item.isCompleted.toggle()
                try? eventStore.save(item, commit: true)
                await syncReminders(into: targetStore)
                return
            }
        }

        if let idx = targetStore?.todos.firstIndex(where: { $0.id == id }) {
            targetStore?.todos[idx].isCompleted.toggle()
        }
    }
}
