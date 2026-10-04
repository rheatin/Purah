// Sources/PurahCore/Services/SystemRemindersSyncService.swift
import Foundation
import EventKit
import Observation

@Observable
public final class SystemRemindersSyncService: @unchecked Sendable {
    public static let shared = SystemRemindersSyncService()

    private var eventStore = EKEventStore()
    public private(set) var isSyncing: Bool = false
    public private(set) var lastSyncDate: Date?

    public init() {
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.syncReminders(into: nil)
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
                    return TodoItem(
                        id: rem.calendarItemIdentifier,
                        title: rem.title ?? "未命名待办",
                        listTitle: rem.calendar?.title ?? "提醒事项",
                        dueDate: dueDate,
                        isCompleted: rem.isCompleted
                    )
                }
                continuation.resume(returning: mapped)
            }
        }
    }

    public func syncReminders(into store: PurahWorkspaceStore?, scope: RemindersScope? = nil) async {
        let status = PermissionManager.status(from: EKEventStore.authorizationStatus(for: .reminder))
        guard status.isGranted else {
            store?.isUsingRealReminders = false
            return
        }

        isSyncing = true
        let targetScope = scope ?? store?.remindersScope ?? .allIncomplete
        let items = await fetchReminders(scope: targetScope)

        if let store = store {
            store.remindersScope = targetScope
            store.isUsingRealReminders = true
            store.todos = items
        }
        lastSyncDate = Date()
        isSyncing = false
    }

    public func addReminder(title: String, into store: PurahWorkspaceStore?) async -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let status = PermissionManager.status(from: EKEventStore.authorizationStatus(for: .reminder))
        if status.isGranted, let calendar = eventStore.defaultCalendarForNewReminders() {
            let reminder = EKReminder(eventStore: eventStore)
            reminder.title = trimmed
            reminder.calendar = calendar
            do {
                try eventStore.save(reminder, commit: true)
                await syncReminders(into: store)
                return true
            } catch {
                store?.todos.append(TodoItem(title: trimmed))
                return true
            }
        } else {
            // 未授权或未提供系统权限时，保存在本地 Store
            store?.todos.append(TodoItem(title: trimmed))
            return true
        }
    }

    public func toggleCompletion(id: String, into store: PurahWorkspaceStore?) async {
        let status = PermissionManager.status(from: EKEventStore.authorizationStatus(for: .reminder))
        if status.isGranted {
            if let item = eventStore.calendarItem(withIdentifier: id) as? EKReminder {
                item.isCompleted.toggle()
                try? eventStore.save(item, commit: true)
                await syncReminders(into: store)
                return
            }
        }

        // 本地切换
        if let idx = store?.todos.firstIndex(where: { $0.id == id }) {
            store?.todos[idx].isCompleted.toggle()
        }
    }
}
