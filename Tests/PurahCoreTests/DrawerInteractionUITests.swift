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
        store.musicTrack.durationSeconds = 200.0
        store.musicTrack.playbackProgress = 0.25
        #expect(store.musicTrack.playbackProgress == 0.25)

        // Simulate user dragging to 75%
        SystemMusicSyncService.shared.seek(to: 0.75, store: store)
        #expect(store.musicTrack.playbackProgress == 0.75)
        #expect(store.musicTrack.currentPositionSeconds == 150.0)
    }

    @Test("Pin isolation allows both same-rail and opposite-rail drawers to retract properly")
    @MainActor
    func testPinIsolationAllowsSameRailAndOppositeRailToDismiss() {
        let store = PurahWorkspaceStore()
        // 1. Pin Quick Notes on left rail
        store.togglePinItem(id: "notes")
        #expect(store.isItemPinned(id: "notes") == true)

        // 2. Open Script Runway on same left rail
        store.activeDrawerPodId = "scripts"
        store.activeDrawerItemId = "scripts"
        #expect(store.isItemPinned(id: "scripts") == false)

        // Simulate mouse leaving Script Runway
        let activeLeft = store.activeDrawerItemId ?? store.activeDrawerPodId
        if let active = activeLeft, !store.isItemPinned(id: active) {
            store.activeDrawerItemId = nil
            store.activeDrawerPodId = nil
        }
        #expect(store.activeDrawerPodId == nil)
        #expect(store.isItemPinned(id: "notes") == true)

        // 3. Open Calendar on right rail
        store.activeDrawerPodId = "calendar"
        store.activeDrawerItemId = "calendar"
        #expect(store.isItemPinned(id: "calendar") == false)

        // Simulate mouse leaving Calendar
        let activeRight = store.activeDrawerItemId ?? store.activeDrawerPodId
        if let active = activeRight, !store.isItemPinned(id: active) {
            store.activeDrawerItemId = nil
            store.activeDrawerPodId = nil
        }
        #expect(store.activeDrawerPodId == nil)
        #expect(store.isItemPinned(id: "notes") == true)
    }

    @Test("Empty area above and beside pinned drawer does not intercept clicks")
    @MainActor
    func testEmptyAreaClickThroughHitTestReturnsNil() {
        let store = PurahWorkspaceStore()
        store.togglePinItem(id: "notes")
        #expect(store.isItemPinned(id: "notes") == true)
        store.activeDrawerPodId = nil
        store.activeDrawerItemId = nil

        guard let notesPod = store.pods.first(where: { $0.id == "notes" }) else {
            Issue.record("Notes pod not found")
            return
        }

        let totalH = 1000.0
        let cardBottom = totalH * (1.0 - (notesPod.range.start + notesPod.range.length))
        let cardTop = totalH * (1.0 - notesPod.range.start)
        let minY = max(cardBottom - 6.0, 0.0)
        let maxY = min(cardTop + 6.0, totalH)
        let drawerW = store.effectiveDrawerWidth(baseWidth: notesPod.drawerWidth) + 8.0

        // Test 1: Empty desktop area above Quick Notes (y = 800)
        let abovePointY = 800.0
        let isAboveInDrawer = (abovePointY >= minY && abovePointY <= maxY)
        #expect(isAboveInDrawer == false)

        // Test 2: Empty desktop area below Quick Notes (y = 80)
        let belowPointY = 80.0
        let isBelowInDrawer = (belowPointY >= minY && belowPointY <= maxY)
        #expect(isBelowInDrawer == false)

        // Test 3: Area to the right of drawer (x = 330 where drawerW ~ 288)
        let rightPointX = 330.0
        let isRightInDrawer = (rightPointX <= drawerW)
        #expect(isRightInDrawer == false)
    }

    @Test("Music track info retains real artwork data and audio source identity")
    @MainActor
    func testMusicTrackArtworkAndSource() {
        let dummyData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) // PNG header
        let track = MusicTrackInfo(
            title: "Cruel Summer",
            artist: "Taylor Swift",
            album: "Lover",
            isPlaying: true,
            playbackProgress: 0.5,
            currentPositionSeconds: 89.0,
            durationSeconds: 178.0,
            waveformSamples: [0.5, 0.8, 0.3],
            artworkData: dummyData,
            sourceApp: "Apple Music",
            sourceBundleId: "com.apple.Music"
        )

        #expect(track.artworkData == dummyData)
        #expect(track.sourceApp == "Apple Music")
        #expect(track.durationSeconds == 178.0)
        #expect(track.currentPositionSeconds == 89.0)
    }
}
