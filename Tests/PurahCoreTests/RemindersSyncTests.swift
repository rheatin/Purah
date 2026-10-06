// Tests/PurahCoreTests/RemindersSyncTests.swift
import Testing
import Foundation
@testable import PurahCore

@Suite("System Reminders Sync Tests")
@MainActor
struct RemindersSyncTests {
    @Test("Add reminder falls back to in-memory store when unauthorized")
    func testAddReminderFallback() async {
        let store = PurahWorkspaceStore()
        let service = SystemRemindersSyncService()
        let initialCount = store.todos.count

        let success = await service.addReminder(title: "海拉鲁矿石收集测试", into: store)
        #expect(success)
        #expect(store.todos.count == initialCount + 1)
        #expect(store.todos.last?.title == "海拉鲁矿石收集测试")
    }

    @Test("Toggle completion in-memory fallback works")
    func testToggleCompletion() async {
        let store = PurahWorkspaceStore()
        let service = SystemRemindersSyncService()

        guard let firstTodo = store.todos.first else {
            Issue.record("Missing first todo")
            return
        }
        let originalState = firstTodo.isCompleted
        await service.toggleCompletion(id: firstTodo.id, into: store)

        #expect(store.todos.first?.isCompleted == !originalState)
    }
}
