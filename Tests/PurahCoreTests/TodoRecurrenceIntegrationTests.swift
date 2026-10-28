// Tests/PurahCoreTests/TodoRecurrenceIntegrationTests.swift
import Testing
import Foundation
@testable import PurahCore
@testable import PurahUI

/// `TodoRecurrence` only tests the date arithmetic. This covers the piece that
/// actually makes the feature work: completing a repeating todo appends its
/// successor, exactly once.
@Suite("Todo Recurrence Integration")
@MainActor
struct TodoRecurrenceIntegrationTests {

    private func makeState() -> TodoPluginState {
        let defaults = UserDefaults(suiteName: "purah.todo.rec.\(UUID().uuidString)")!
        return TodoPluginState(storage: ScopedPluginStorage(pluginId: "todo", defaults: defaults))
    }

    @Test("Completing a repeating todo appends one successor")
    func testCompletionAppendsSuccessor() {
        let state = makeState()
        let item = TodoItem(
            id: "daily-1",
            title: "Standup",
            dueDate: Date(),
            recurrence: TodoRecurrence(frequency: .daily)
        )
        state.todos = [item]

        let successor = state.scheduleNextOccurrence(of: item)

        #expect(successor != nil)
        #expect(state.todos.count == 2)
        #expect(state.todos.last?.title == "Standup")
        #expect(state.todos.last?.isCompleted == false)
        #expect(state.todos.last?.recurrenceCount == 1)
        #expect(state.todos.last?.recurrence?.frequency == .daily)
        #expect(state.todos.last?.id == "daily-1-r1")
    }

    /// Completing the same occurrence twice must not queue two successors.
    @Test("A second completion of the same occurrence is idempotent")
    func testDoubleCompletionIsIdempotent() {
        let state = makeState()
        let item = TodoItem(
            id: "daily-2",
            title: "Standup",
            dueDate: Date(),
            recurrence: TodoRecurrence(frequency: .daily)
        )
        state.todos = [item]

        state.scheduleNextOccurrence(of: item)
        state.scheduleNextOccurrence(of: item)

        #expect(state.todos.count == 2, "the successor must not be appended twice")
    }

    @Test("A non-repeating todo produces no successor")
    func testNonRepeatingProducesNothing() {
        let state = makeState()
        let item = TodoItem(id: "plain", title: "One off")
        state.todos = [item]

        #expect(state.scheduleNextOccurrence(of: item) == nil)
        #expect(state.todos.count == 1)
    }

    @Test("The successor's due date advances from the completed occurrence")
    func testSuccessorAdvancesFromDueDate() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let anchor = cal.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 9))!

        let state = makeState()
        let item = TodoItem(
            id: "weekly-1",
            title: "Report",
            dueDate: anchor,
            recurrence: TodoRecurrence(frequency: .weekly)
        )
        state.todos = [item]

        let successor = try #require(state.scheduleNextOccurrence(of: item))
        let components = cal.dateComponents([.month, .day], from: try #require(successor.dueDate))
        #expect(components.month == 11)
        #expect(components.day == 3)
    }

    @Test("A recurrence past its end date produces no successor")
    func testExpiredRecurrenceProducesNothing() {
        let state = makeState()
        let item = TodoItem(
            id: "expired",
            title: "Old",
            dueDate: Date(),
            recurrence: TodoRecurrence(frequency: .daily, endDate: Date().addingTimeInterval(-86_400))
        )
        state.todos = [item]

        #expect(state.scheduleNextOccurrence(of: item) == nil)
        #expect(state.todos.count == 1)
    }

    @Test("Setting a recurrence writes it through to the store mirror")
    func testSetRecurrenceWritesThrough() {
        let defaults = UserDefaults(suiteName: "purah.todo.rec.store.\(UUID().uuidString)")!
        let store = PurahWorkspaceStore(userDefaults: defaults)
        let state = makeState()

        let item = TodoItem(id: "mirror-1", title: "Mirror")
        store._todos = [item]
        state.todos = [item]

        state.setRecurrence(id: "mirror-1", recurrence: TodoRecurrence(frequency: .monthly), store: store)

        #expect(state.todos.first?.recurrence?.frequency == .monthly)
        #expect(store._todos.first?.recurrence?.frequency == .monthly,
                "the drawer renders from the store, so the rule must land there too")
    }

    @Test("Clearing a recurrence removes it from both copies")
    func testClearRecurrence() {
        let defaults = UserDefaults(suiteName: "purah.todo.rec.clear.\(UUID().uuidString)")!
        let store = PurahWorkspaceStore(userDefaults: defaults)
        let state = makeState()

        let item = TodoItem(id: "clear-1", title: "Clear", recurrence: TodoRecurrence(frequency: .daily))
        store._todos = [item]
        state.todos = [item]

        state.setRecurrence(id: "clear-1", recurrence: nil, store: store)

        #expect(state.todos.first?.recurrence == nil)
        #expect(store._todos.first?.recurrence == nil)
    }
}
