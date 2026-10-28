// Sources/PurahUI/Plugins/States/TodoPluginState.swift
import SwiftUI
import AppKit
import Foundation
import Observation
import EventKit
import PurahCore

@Observable
@MainActor
public final class TodoPluginState: Sendable {
    public var todos: [TodoItem]
    public var scope: RemindersScope
    public var isUsingRealReminders: Bool
    public var isSyncing: Bool
    public var maxRailTodos: Int
    public let storage: any PurahPluginStorage

    @ObservationIgnored private var reminderStoreObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    @ObservationIgnored private weak var boundStore: PurahWorkspaceStore?

    public var remindersScope: RemindersScope {
        get { scope }
        set { scope = newValue }
    }

    public var incompleteTodos: [TodoItem] {
        todos.filter { !$0.isCompleted }
    }

    public init(storage: any PurahPluginStorage = ScopedPluginStorage(pluginId: "todo")) {
        self.storage = storage
        self.scope = storage.codable(forKey: "scope", as: RemindersScope.self) ?? .allIncomplete
        self.isUsingRealReminders = false
        self.isSyncing = false
        let savedMax = storage.int(forKey: "maxRailTodos")
        self.maxRailTodos = savedMax > 0 ? savedMax : 6
        self.todos = storage.codable(forKey: "todos", as: [TodoItem].self) ?? Self.defaultTodos()
    }

    public func load() {
        if let savedScope = storage.codable(forKey: "scope", as: RemindersScope.self) {
            self.scope = savedScope
        }
        let savedMax = storage.int(forKey: "maxRailTodos")
        if savedMax > 0 {
            self.maxRailTodos = savedMax
        }
        if let savedTodos = storage.codable(forKey: "todos", as: [TodoItem].self) {
            self.todos = savedTodos
        }
    }

    public func save() {
        storage.setCodable(scope, forKey: "scope")
        storage.set(maxRailTodos, forKey: "maxRailTodos")
        storage.setCodable(todos, forKey: "todos")
    }

    public func syncReminders(into store: PurahWorkspaceStore? = nil) async {
        if let store {
            self.boundStore = store
        }
        let targetStore = store ?? boundStore

        let status = PermissionManager.status(from: EKEventStore.authorizationStatus(for: .reminder))
        guard status.isGranted else {
            isUsingRealReminders = false
            targetStore?.isUsingRealReminders = false
            return
        }

        isSyncing = true
        let fetched = await SystemRemindersSyncService.shared.fetchReminders(scope: scope)
        self.todos = fetched
        self.isUsingRealReminders = true
        self.save()
        if let targetStore {
            targetStore.isUsingRealReminders = self.isUsingRealReminders
            targetStore._todos = self.todos
        }
        isSyncing = false
    }

    public func toggleCompletion(id: String, store: PurahWorkspaceStore? = nil) async {
        // Capture the item before mutating: a repeating todo needs its rule and
        // its due date to derive the next occurrence, and both are still the
        // *pre-completion* values here.
        let before = todos.first { $0.id == id }

        if let idx = todos.firstIndex(where: { $0.id == id }) {
            todos[idx].isCompleted.toggle()
            save()
        }
        let targetStore = store ?? boundStore
        var didUpdateRealReminder = false
        if let targetStore {
            didUpdateRealReminder = await SystemRemindersSyncService.shared.toggleCompletion(id: id, into: targetStore)
            if let idx = targetStore._todos.firstIndex(where: { $0.id == id }),
               let selfIdx = todos.firstIndex(where: { $0.id == id }) {
                todos[selfIdx].isCompleted = targetStore._todos[idx].isCompleted
            }
            targetStore.invalidateLayoutCache()
            targetStore.onWindowsRebuildNeeded?()
        }

        // Completing a repeating todo schedules its successor — but only for
        // items that live in this pod alone. A repeating reminder in Reminders
        // is maintained by EventKit: completing it already spawned the next
        // occurrence, which the round trip above pulled in. Deriving one here
        // as well would show every repeating task twice.
        if let before, before.recurrence != nil, !before.isCompleted, !didUpdateRealReminder {
            scheduleNextOccurrence(of: before, store: store)
        }
    }

    /// Appends the next occurrence of a repeating todo.
    ///
    /// The successor is a *new* item rather than a reset of the completed one:
    /// the completed occurrence stays in the list (and in Reminders) as a
    /// record, which is what makes "did I do this yesterday" answerable.
    ///
    /// Its id is derived from the original plus the occurrence count so that
    /// repeated cycles cannot collide, and so a sync that re-derives ids does
    /// not fold two occurrences together.
    @discardableResult
    public func scheduleNextOccurrence(of item: TodoItem, store: PurahWorkspaceStore? = nil) -> TodoItem? {
        guard let recurrence = item.recurrence else { return nil }

        // Advance from the due date when there was one, otherwise from now —
        // a repeating todo without a due date still needs a clock.
        let anchor = item.dueDate ?? Date()
        guard let nextDue = recurrence.nextDueDate(after: anchor) else { return nil }

        let nextCount = item.recurrenceCount + 1
        let successor = TodoItem(
            id: "\(item.id)-r\(nextCount)",
            title: item.title,
            listTitle: item.listTitle,
            listColorHex: item.listColorHex,
            dueDate: nextDue,
            isCompleted: false,
            recurrence: recurrence,
            recurrenceCount: nextCount
        )

        // Guard against a double-completion producing a duplicate successor.
        guard !todos.contains(where: { $0.id == successor.id }) else { return nil }

        todos.append(successor)
        save()

        if let targetStore = store ?? boundStore {
            targetStore._todos.append(successor)
            targetStore.invalidateLayoutCache()
            targetStore.onWindowsRebuildNeeded?()
        }
        return successor
    }

    /// Attaches or removes the repeating schedule on an item.
    ///
    /// Writes through to the store's mirror explicitly rather than relying on
    /// `boundStore`: the drawer renders from `store._todos`, so a rule that only
    /// landed in the plugin's own array would look applied and then do nothing
    /// when the task was completed.
    public func setRecurrence(id: String, recurrence: TodoRecurrence?, store: PurahWorkspaceStore? = nil) {
        if let idx = todos.firstIndex(where: { $0.id == id }) {
            todos[idx].recurrence = recurrence
            save()
        }
        let target = store ?? boundStore
        if let target, let idx = target._todos.firstIndex(where: { $0.id == id }) {
            target._todos[idx].recurrence = recurrence
        }

        // Write through to Reminders as well. The pod mirrors that list, and a
        // rule that only existed locally would vanish on the next sync — which
        // replaces the whole array with what EventKit reports. Returns false
        // for local-only items, where the local rule above is the only copy and
        // is correct as it stands.
        SystemRemindersSyncService.shared.setRecurrence(id: id, recurrence: recurrence)
    }

    public func updateTitle(id: String, title: String) {
        if let idx = todos.firstIndex(where: { $0.id == id }) {
            todos[idx].title = title
            save()
        }
        if let boundStore, let idx = boundStore._todos.firstIndex(where: { $0.id == id }) {
            boundStore._todos[idx].title = title
        }
    }

    public func setDueDate(id: String, date: Date?) {
        if let idx = todos.firstIndex(where: { $0.id == id }) {
            todos[idx].dueDate = date
            save()
        }
        if let boundStore {
            if let idx = boundStore._todos.firstIndex(where: { $0.id == id }) {
                boundStore._todos[idx].dueDate = date
            }
            boundStore.invalidateLayoutCache()
            boundStore.onWindowsRebuildNeeded?()
        }
    }

    public static func dueTodayAt18(from now: Date = Date()) -> Date {
        let cal = Calendar.current
        if let date = cal.date(bySettingHour: 18, minute: 0, second: 0, of: now), date > now {
            return date
        }
        return now.addingTimeInterval(3600)
    }

    public static func dueTomorrowAt09(from now: Date = Date()) -> Date {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(86400)
        return cal.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }

    public func addTodo(title: String, store: PurahWorkspaceStore? = nil) {
        let item = TodoItem(title: title, isCompleted: false)
        todos.append(item)
        save()
        let targetStore = store ?? boundStore
        targetStore?._todos.append(item)
        targetStore?.invalidateLayoutCache()
        targetStore?.onWindowsRebuildNeeded?()
    }

    public func removeTodo(id: String, store: PurahWorkspaceStore? = nil) {
        todos.removeAll { $0.id == id }
        save()
        let targetStore = store ?? boundStore
        targetStore?._todos.removeAll { $0.id == id }
        targetStore?.invalidateLayoutCache()
        targetStore?.onWindowsRebuildNeeded?()
    }

    public func add(todo: TodoItem, store: PurahWorkspaceStore? = nil) {
        todos.append(todo)
        save()
        let targetStore = store ?? boundStore
        targetStore?._todos.append(todo)
        targetStore?.invalidateLayoutCache()
        targetStore?.onWindowsRebuildNeeded?()
    }

    public func remove(id: String) {
        removeTodo(id: id, store: boundStore)
    }

    public func mount(store: PurahWorkspaceStore) {
        self.boundStore = store
        if !store._todos.isEmpty && self.todos.isEmpty {
            self.todos = store._todos
        }
        if reminderStoreObserver == nil {
            reminderStoreObserver = NotificationCenter.default.addObserver(
                forName: .EKEventStoreChanged,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    await self?.syncReminders()
                }
            }
        }
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            await self?.syncReminders(into: store)
        }
    }

    public func unmount(store: PurahWorkspaceStore) {
        if let obs = reminderStoreObserver {
            NotificationCenter.default.removeObserver(obs)
            reminderStoreObserver = nil
        }
        syncTask?.cancel()
        syncTask = nil
        save()
        if boundStore === store {
            boundStore = nil
        }
    }

    public static func defaultTodos() -> [TodoItem] {
        [
            TodoItem(title: "Calibrate left tactile edge sensor", isCompleted: true),
            TodoItem(title: "Update energy waveform telemetry", isCompleted: false),
            TodoItem(title: "Verify multi-display adaptive layout", isCompleted: false),
            TodoItem(title: "Tune Fitts Law flick threshold filtering", isCompleted: false)
        ]
    }
}
