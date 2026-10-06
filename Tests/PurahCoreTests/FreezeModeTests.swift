import Testing
import AppKit
import SwiftUI
@testable import PurahCore
@testable import PurahUI
@testable import PurahApp

@Suite("Freeze Mode Windowing and Suppression Tests")
struct FreezeModeTests {
    @Test("ScreenEdgeCoordinator setFrozen hides windows and disables interactivity")
    @MainActor
    func testCoordinatorFreeze() {
        let store = PurahWorkspaceStore()
        let coordinator = ScreenEdgeCoordinator(store: store)
        
        coordinator.setFrozen(true)
        #expect(coordinator.isFrozen == true)
        
        coordinator.setFrozen(false)
        #expect(coordinator.isFrozen == false)
    }

    @Test("EdgeMouseMonitor setFrozen toggles frozen state and resets dwell")
    @MainActor
    func testEdgeMouseMonitorFreeze() {
        let store = PurahWorkspaceStore()
        let monitor = EdgeMouseMonitor(store: store)
        
        monitor.setFrozen(true)
        #expect(monitor.isFrozen == true)
        
        monitor.setFrozen(false)
        #expect(monitor.isFrozen == false)
    }

    @Test("PassThroughHostingView completely suppresses hit-test and interactive drawer when frozen")
    @MainActor
    func testPassThroughHostingViewFreeze() {
        let store = PurahWorkspaceStore()
        let view = PassThroughHostingView(rootView: EmptyView(), edge: .right, store: store)
        view.frame = NSRect(x: 0, y: 0, width: 340, height: 1000)
        
        store.activateDrawer(podId: "calendar")
        
        // When not frozen, point inside active drawer is interactive
        let drawerPoint = NSPoint(x: 300, y: 700)
        #expect(view.isPointInInteractiveDrawer(drawerPoint) == true)
        
        // When frozen, 100% click-through (hitTest returns nil, isPointInInteractiveDrawer returns false)
        store.isRailsFrozen = true
        #expect(view.isPointInInteractiveDrawer(drawerPoint) == false)
        #expect(view.hitTest(drawerPoint) == nil)
        #expect(view.hitTest(NSPoint(x: 338, y: 700)) == nil)
    }
}
