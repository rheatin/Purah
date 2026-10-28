// Tests/PurahCoreTests/RemindersSyncTests.swift
import Testing
import Foundation
@testable import PurahCore

@Suite("System Reminders Sync Tests")
@MainActor
struct RemindersSyncTests {

    /// Every test here runs with an injected `.denied` permission so it exercises
    /// the in-memory fallback. Running against real TCC state used to create
    /// actual `EKReminder`s in the developer's Reminders database and made the
    /// assertions depend on how many reminders already existed.
    private func makeDeniedService() -> SystemRemindersSyncService {
        SystemRemindersSyncService(permissionStatus: { .denied })
    }

    private func makeStore() -> PurahWorkspaceStore {
        PurahWorkspaceStore(userDefaults: UserDefaults(suiteName: "test_reminders_\(UUID().uuidString)")!)
    }

    @Test("Add reminder falls back to in-memory store when unauthorized")
    func testAddReminderFallback() async {
        let store = makeStore()
        let service = makeDeniedService()
        let initialCount = store._todos.count

        let success = await service.addReminder(title: "Hyrule Ore Gathering Test", into: store)
        #expect(success)
        #expect(store._todos.count == initialCount + 1)
        #expect(store._todos.last?.title == "Hyrule Ore Gathering Test")
    }

    @Test("Add reminder rejects blank titles without mutating the store")
    func testAddReminderRejectsBlankTitle() async {
        let store = makeStore()
        let service = makeDeniedService()
        let initialCount = store._todos.count

        let success = await service.addReminder(title: "   ", into: store)
        #expect(!success)
        #expect(store._todos.count == initialCount)
    }

    @Test("Toggle completion in-memory fallback works")
    func testToggleCompletion() async {
        let store = makeStore()
        let service = makeDeniedService()

        guard let firstTodo = store._todos.first else {
            Issue.record("Missing first todo")
            return
        }
        let originalState = firstTodo.isCompleted
        await service.toggleCompletion(id: firstTodo.id, into: store)

        #expect(store._todos.first?.isCompleted == !originalState)
    }

    @Test("Unauthorized sync leaves the in-memory todos untouched")
    func testUnauthorizedSyncDoesNotClobberTodos() async {
        let store = makeStore()
        let service = makeDeniedService()
        let before = store._todos

        await service.syncReminders(into: store)

        #expect(store._todos.count == before.count)
        #expect(store.isUsingRealReminders == false)
    }

    @Test("TodoItem carries native reminder listColorHex")
    func testTodoItemListColorHex() {
        let todo = TodoItem(
            title: "Prepare Slide Deck",
            listTitle: "Personal",
            listColorHex: "#34C759",
            isCompleted: false
        )
        #expect(todo.listColorHex == "#34C759")
        #expect(todo.listTitle == "Personal")
    }

    /// Reminders owns the recurrence of a real reminder: completing one there
    /// already produced the next occurrence. The pod must know whether its own
    /// derivation is needed, so the toggle reports which side it acted on.
    @Test("Toggling a local-only todo reports that no real reminder was updated")
    func testToggleReportsLocalFallback() async {
        let store = makeStore()
        let service = makeDeniedService()
        guard let todo = store._todos.first else {
            Issue.record("missing seeded todo")
            return
        }

        let didUpdateRealReminder = await service.toggleCompletion(id: todo.id, into: store)

        #expect(
            didUpdateRealReminder == false,
            "a local item must let the pod derive its own successor"
        )
    }

    /// The write-through must fail closed when there is no reminder behind the
    /// id, so the caller keeps its local rule instead of trusting a save that
    /// never happened.
    @Test("Writing a recurrence without a real reminder reports failure")
    func testSetRecurrenceFailsWithoutPermission() {
        let service = makeDeniedService()
        #expect(service.setRecurrence(id: "not-a-reminder", recurrence: TodoRecurrence(frequency: .daily)) == false)
        #expect(service.setRecurrence(id: "not-a-reminder", recurrence: nil) == false)
    }
}
