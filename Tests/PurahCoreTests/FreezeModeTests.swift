import Testing
import AppKit
import SwiftUI
@testable import PurahCore
@testable import PurahUI
@testable import PurahApp

@Suite("Freeze Mode Windowing and Suppression Tests", .serialized)
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

    @Test("TransientHUDController show displays correct capsule text and configures panel")
    @MainActor
    func testTransientHUDController() {
        let hud = TransientHUDController.shared
        hud.show(isFrozen: true)
        #expect(hud.isFrozen == true)
        #expect(hud.currentText == "❄️ Rails Frozen (⌥⇥ to restore)")
        #expect(hud.panel != nil)
        #expect(hud.panel?.ignoresMouseEvents == true)
        #expect(hud.panel?.level == .floating)
        #expect(hud.panel?.isOpaque == false)
        #expect(hud.panel?.styleMask.contains(.nonactivatingPanel) == true)
        
        hud.show(isFrozen: false)
        #expect(hud.isFrozen == false)
        #expect(hud.currentText == "✨ Rails Active")
        hud.dismissImmediate()
    }

    @Test("AppDelegate toggleFreezeMode toggles store, coordinator, monitor, HUD and menu")
    @MainActor
    func testAppDelegateToggleFreezeMode() {
        let appDelegate = AppDelegate()
        let coord = ScreenEdgeCoordinator(store: appDelegate.store)
        let monitor = EdgeMouseMonitor(store: appDelegate.store, coordinator: coord)
        appDelegate.coordinator = coord
        appDelegate.mouseMonitor = monitor
        appDelegate.rebuildMenu()
        
        #expect(appDelegate.store.isRailsFrozen == false)
        #expect(coord.isFrozen == false)
        #expect(monitor.isFrozen == false)
        
        // Find freeze menu item when active
        let activeMenuItem = appDelegate.statusMenu?.items.first { $0.action == #selector(AppDelegate.toggleFreezeMode) }
        #expect(activeMenuItem != nil)
        #expect(activeMenuItem?.title == "Freeze Rails (⌥⇥)")
        
        // Toggle to frozen
        appDelegate.toggleFreezeMode()
        #expect(appDelegate.store.isRailsFrozen == true)
        #expect(coord.isFrozen == true)
        #expect(monitor.isFrozen == true)
        #expect(TransientHUDController.shared.isFrozen == true)
        #expect(TransientHUDController.shared.currentText == "❄️ Rails Frozen (⌥⇥ to restore)")
        
        let frozenMenuItem = appDelegate.statusMenu?.items.first { $0.action == #selector(AppDelegate.toggleFreezeMode) }
        #expect(frozenMenuItem != nil)
        #expect(frozenMenuItem?.title == "Unfreeze Rails (⌥⇥)")
        
        // Toggle back to active
        appDelegate.toggleFreezeMode()
        #expect(appDelegate.store.isRailsFrozen == false)
        #expect(coord.isFrozen == false)
        #expect(monitor.isFrozen == false)
        #expect(TransientHUDController.shared.isFrozen == false)
        #expect(TransientHUDController.shared.currentText == "✨ Rails Active")
        
        let restoredMenuItem = appDelegate.statusMenu?.items.first { $0.action == #selector(AppDelegate.toggleFreezeMode) }
        #expect(restoredMenuItem != nil)
        #expect(restoredMenuItem?.title == "Freeze Rails (⌥⇥)")
        
        TransientHUDController.shared.dismissImmediate()
    }
}
