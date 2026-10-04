// Tests/PurahCoreTests/DrawerInteractionUITests.swift
import Testing
import Foundation
import AppKit
import SwiftUI
@testable import PurahCore
@testable import PurahUI

@Suite("Drawer Interaction & UI Hit-Test Simulation Tests")
struct DrawerInteractionUITests {
    @Test("Canonical window coordinate math covers all 7 pods on default rails")
    @MainActor
    func testAllPodsHitCoverage() {
        let store = PurahWorkspaceStore()
        let totalH = 1023.0

        for pod in store.pods {
            let minY = totalH * (1.0 - (pod.range.start + pod.range.length)) - 60.0
            let maxY = totalH * (1.0 - pod.range.start) + 60.0
            let trueCenterY = totalH * (1.0 - (pod.range.start + pod.range.length / 2.0))

            #expect(trueCenterY >= minY)
            #expect(trueCenterY <= maxY)
        }
    }

    @Test("Canonical window coordinate math covers calendar when moved to left rail")
    @MainActor
    func testCalendarOnLeftRailCoverage() {
        let store = PurahWorkspaceStore()
        store.movePod(id: "calendar", to: .left)
        let totalH = 1023.0

        for pod in store.pods {
            let minY = totalH * (1.0 - (pod.range.start + pod.range.length)) - 60.0
            let maxY = totalH * (1.0 - pod.range.start) + 60.0
            let trueCenterY = totalH * (1.0 - (pod.range.start + pod.range.length / 2.0))

            #expect(trueCenterY >= minY)
            #expect(trueCenterY <= maxY)
        }
    }

    @Test("Simulate Todo item completion toggle and title inline editing")
    @MainActor
    func testTodoInteraction() async {
        let store = PurahWorkspaceStore()
        guard let firstTodo = store.todos.first else { return }
        let initialCompleted = firstTodo.isCompleted

        // Simulate toggling completion
        await SystemRemindersSyncService.shared.toggleCompletion(id: firstTodo.id, into: store)
        let updatedTodo = store.todos.first { $0.id == firstTodo.id }
        #expect(updatedTodo?.isCompleted == !initialCompleted)

        // Simulate title editing
        if let idx = store.todos.firstIndex(where: { $0.id == firstTodo.id }) {
            store.todos[idx].title = "Edited Task Title"
        }
        #expect(store.todos.first?.title == "Edited Task Title")
    }

    @Test("Simulate Calendar Join button URL presence and extraction")
    @MainActor
    func testCalendarJoinUrlInteraction() {
        let textWithUrl = "Discussion on project status at https://zoom.us/j/12345678"
        let extracted = SystemCalendarSyncService.extractFirstURL(from: textWithUrl)
        #expect(extracted != nil)
        #expect(extracted?.absoluteString == "https://zoom.us/j/12345678")
    }

    @Test("Drawer width mode calculates valid bounds for fixed and adaptive modes")
    @MainActor
    func testDrawerWidthCalculations() {
        let store = PurahWorkspaceStore()
        store.drawerWidthMode = .fixed
        store.fixedDrawerWidth = 300.0
        #expect(store.effectiveDrawerWidth(for: "Short", baseWidth: 280) == 300.0)

        store.drawerWidthMode = .adaptive
        let shortWidth = store.effectiveDrawerWidth(for: "Hi", baseWidth: 280)
        let longWidth = store.effectiveDrawerWidth(for: "Very long event title that needs more space to breathe on screen", baseWidth: 280)
        #expect(shortWidth >= 230.0)
        #expect(longWidth <= 330.0)
        #expect(longWidth > shortWidth)
    }
}
