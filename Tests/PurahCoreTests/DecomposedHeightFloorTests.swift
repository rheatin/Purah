// Tests/PurahCoreTests/DecomposedHeightFloorTests.swift
import Testing
import Foundation
@testable import PurahCore
@testable import PurahUI

/// Decomposed pod height floor = the TALLER of the two modes:
/// composite drawer minimum vs (chip min-height × on-rail count + spacing).
/// Guarantees an expanded chip drawer is exactly its slot height — never
/// taller than the pod.
@Suite @MainActor
struct DecomposedHeightFloorTests {

    private func makeState(_ todos: [TodoItem]) -> TodoPluginState {
        let state = TodoPluginState(storage: ScopedPluginStorage(pluginId: "todo_test_\(UUID().uuidString)"))
        state.todos = todos
        return state
    }

    private func todo(_ id: String, completed: Bool = false) -> TodoItem {
        TodoItem(id: id, title: id, isCompleted: completed)
    }

    @Test("Todo floor picks the decomposed minimum when it exceeds the composite floor")
    func testTodoDecomposedExceedsComposite() {
        let plugin = TodoPlugin(state: makeState((0..<6).map { todo("t\($0)") }))
        let store = PurahWorkspaceStore()

        // 6 on-rail chips × 48 + 5 × 2.5 spacing = 300.5 > composite 130.
        let floor = plugin.minimumDrawerHeight(store: store)
        #expect(floor == 300.5)
    }

    @Test("Todo floor keeps the composite minimum when few todos are on rail")
    func testTodoCompositeWinsWhenFew() {
        let plugin = TodoPlugin(state: makeState([todo("a"), todo("b")]))
        let store = PurahWorkspaceStore()

        // 2 × 48 + 2.5 = 98.5 < composite 130 → composite floor wins.
        #expect(plugin.minimumDrawerHeight(store: store) == 130.0)
    }

    @Test("Completed todos occupy no slot in the floor")
    func testCompletedExcludedFromCount() {
        // 3 completed + 2 incomplete: only the 2 incomplete count.
        let plugin = TodoPlugin(state: makeState([
            todo("d1", completed: true), todo("d2", completed: true), todo("d3", completed: true),
            todo("a"), todo("b"),
        ]))
        let store = PurahWorkspaceStore()

        #expect(plugin.minimumDrawerHeight(store: store) == 130.0)
    }

    @Test("Todo policy minChipHeight carries the expanded drawer's readable floor")
    func testTodoChipHeightMatchesDrawerFloor() {
        let plugin = TodoPlugin(state: makeState([todo("a")]))
        #expect(plugin.decomposedPolicy.minChipHeight == 48.0)
    }

    @Test("Calendar floor picks the decomposed minimum when it exceeds the composite floor")
    func testCalendarFloorTakesMax() {
        let storage = ScopedPluginStorage(pluginId: "calendar_test_\(UUID().uuidString)")
        let state = CalendarPluginState(storage: storage)
        state.overflowStrategy = .smartFold

        let now = Date()
        state.events = (0..<4).map { i in
            CalendarEventItem(
                id: "e\(i)", title: "E\(i)",
                startTime: now.addingTimeInterval(Double(i + 1) * 3600),
                endTime: now.addingTimeInterval(Double(i + 1) * 3600 + 1800)
            )
        }

        let plugin = CalendarPlugin(state: state)
        let store = PurahWorkspaceStore()
        plugin.onMount(store: store)

        // 4 × 40 + 3 × 2.5 = 167.5 > composite 140.
        #expect(plugin.minimumDrawerHeight(store: store) == 167.5)

        // Two events: 82.5 < 140 → composite wins.
        state.events = Array(state.events.prefix(2))
        #expect(plugin.minimumDrawerHeight(store: store) == 140.0)
    }

}
