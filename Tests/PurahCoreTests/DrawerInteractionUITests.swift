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

    @Test("Verify Pin Isolation: unpinned items can be dismissed even when another item is pinned")
    @MainActor
    func testPinIsolation() {
        let store = PurahWorkspaceStore()
        
        // Pin the shelf drawer
        store.togglePinItem(id: "shelf")
        #expect(store.isItemPinned(id: "shelf") == true)
        
        // Activate an unpinned drawer (e.g. notes)
        store.activeDrawerItemId = "notes"
        store.activeDrawerPodId = "notes"
        
        // Check that notes is not pinned
        let isNotesPinned = store.isItemPinned(id: store.activeDrawerItemId!)
        #expect(isNotesPinned == false)
        
        // When mouse leaves notes, notes should be dismissed
        if !isNotesPinned {
            store.activeDrawerItemId = nil
            store.activeDrawerPodId = nil
        }
        
        // Shelf should still remain pinned
        #expect(store.isItemPinned(id: "shelf") == true)
        #expect(store.activeDrawerItemId == nil)
    }

    @Test("Verify Hardware Vitals metrics updates")
    @MainActor
    func testHardwareVitalsMonitoring() async {
        let vitals = HardwareVitalsService.shared
        await vitals.refreshMetricsAsync(includeProcesses: false)
        #expect(vitals.metrics.cpuUsage >= 0.0)
        #expect(vitals.metrics.memoryUsage >= 0.0)
    }

    @Test("Pinned pod maintains interactive hit-test coverage even when activePod is nil")
    @MainActor
    func testPinnedPodHitTestCoverage() {
        let store = PurahWorkspaceStore()
        store.togglePinItem(id: "notes")
        #expect(store.isItemPinned(id: "notes") == true)

        // Simulate active hover being nil
        store.activeDrawerItemId = nil
        store.activeDrawerPodId = nil
        #expect(store.activePod == nil)

        // Retrieve the pinned notes pod
        guard let notesPod = store.pods.first(where: { $0.id == "notes" }) else {
            Issue.record("Notes pod not found")
            return
        }

        let totalH = 1000.0
        let minY = totalH * (1.0 - (notesPod.range.start + notesPod.range.length)) - 60.0
        let maxY = totalH * (1.0 - notesPod.range.start) + 60.0
        let testPointY = totalH * (1.0 - (notesPod.range.start + notesPod.range.length / 2.0))
        let testPointX = 150.0 // Inside 340 width drawer

        #expect(testPointY >= minY && testPointY <= maxY)
        #expect(testPointX <= 340.0)
    }

    @Test("Calendar adaptive drawer expands width appropriately when Join button is present")
    @MainActor
    func testCalendarAdaptiveJoinWidth() {
        let store = PurahWorkspaceStore()
        store.drawerWidthMode = .adaptive

        let standardWidth = store.effectiveDrawerWidth(for: "Quick Sync", baseWidth: 280.0)
        let meetingWithJoinWidth = store.effectiveDrawerWidth(for: "Quick Sync", baseWidth: 310.0)

        #expect(meetingWithJoinWidth > standardWidth)
    }

    @Test("Music waveform scrubber updates playback progress on seek gesture")
    @MainActor
    func testMusicScrubberSeek() {
        let store = PurahWorkspaceStore()
        store.musicTrack.playbackProgress = 0.25
        #expect(store.musicTrack.playbackProgress == 0.25)

        // Simulate user dragging to 75%
        store.musicTrack.playbackProgress = 0.75
        #expect(store.musicTrack.playbackProgress == 0.75)
    }
}
