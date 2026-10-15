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
        if let idx = todos.firstIndex(where: { $0.id == id }) {
            todos[idx].isCompleted.toggle()
            save()
        }
        let targetStore = store ?? boundStore
        if let targetStore {
            await SystemRemindersSyncService.shared.toggleCompletion(id: id, into: targetStore)
            if let idx = targetStore._todos.firstIndex(where: { $0.id == id }),
               let selfIdx = todos.firstIndex(where: { $0.id == id }) {
                todos[selfIdx].isCompleted = targetStore._todos[idx].isCompleted
            }
            targetStore.invalidateLayoutCache()
            targetStore.onWindowsRebuildNeeded?()
        }
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
