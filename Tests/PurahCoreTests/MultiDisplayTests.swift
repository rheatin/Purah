// Tests/PurahCoreTests/MultiDisplayTests.swift
import Testing
import AppKit
import SwiftUI
@testable import PurahCore
@testable import PurahUI
@testable import PurahApp

@Suite("Multi-Display Coordination and Seam Detection Tests", .serialized)
@MainActor
struct MultiDisplayTests {
    @Test("DisplayTargetMode cases, names and store persistence")
    func testDisplayTargetModePersistence() {
        let store = PurahWorkspaceStore()
        #expect(DisplayTargetMode.allCases.count == 3)
        #expect(store.displayTargetMode == .followCursor)

        store.displayTargetMode = .primaryOnly
        store.savePersistentState()

        let reloaded = PurahWorkspaceStore()
        #expect(reloaded.displayTargetMode == .primaryOnly)

        // Reset
        store.displayTargetMode = .followCursor
        store.savePersistentState()
    }

    @Test("Coordinator resolves target screen for follow cursor mode")
    func testCoordinatorTargetScreen() {
        let store = PurahWorkspaceStore()
        let coordinator = ScreenEdgeCoordinator(store: store)

        let target = coordinator.targetScreen()
        #expect(target != nil)
        #expect(coordinator.activeScreen != nil)
    }

    @Test("EdgeMouseMonitor isSeam evaluates safely on single and multi screens")
    func testSeamDetectionSafety() {
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let point = NSPoint(x: screen.frame.maxX, y: screen.frame.midY)
            let isSeam = EdgeMouseMonitor.isSeam(edge: .right, on: screen, point: point)
            // If single display, isSeam must be false
            if NSScreen.screens.count <= 1 {
                #expect(isSeam == false)
            }
        }
    }
}
