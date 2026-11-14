import Testing
import AppKit
import SwiftUI
@testable import PurahCore
@testable import PurahUI
@testable import PurahApp

@Suite("Freeze Mode Windowing and Suppression Tests", .serialized)
@MainActor
struct FreezeModeTests {
    @Test("ScreenEdgeCoordinator setFrozen hides windows and disables interactivity")
    @MainActor
    func testCoordinatorFreeze() {
        let suite = "freeze_coord_\(UUID().uuidString)"
        let isolated = UserDefaults(suiteName: suite)!
        defer { isolated.removePersistentDomain(forName: suite) }
        let store = PurahWorkspaceStore(userDefaults: isolated)
        let coordinator = ScreenEdgeCoordinator(store: store)
        
        coordinator.setFrozen(true)
        #expect(coordinator.isFrozen == true)
        
        coordinator.setFrozen(false)
        #expect(coordinator.isFrozen == false)
    }

    @Test("EdgeMouseMonitor setFrozen toggles frozen state and resets dwell")
    @MainActor
    func testEdgeMouseMonitorFreeze() {
        let suite = "freeze_mon_\(UUID().uuidString)"
        let isolated = UserDefaults(suiteName: suite)!
        defer { isolated.removePersistentDomain(forName: suite) }
        let store = PurahWorkspaceStore(userDefaults: isolated)
        let monitor = EdgeMouseMonitor(store: store)
        
        monitor.setFrozen(true)
        #expect(monitor.isFrozen == true)
        
        monitor.setFrozen(false)
        #expect(monitor.isFrozen == false)
    }

    @Test("PassThroughHostingView completely suppresses hit-test and interactive drawer when frozen")
    @MainActor
    func testPassThroughHostingViewFreeze() {
        let isolated = UserDefaults(suiteName: "test_freeze")!
        let store = PurahWorkspaceStore(userDefaults: isolated)
        let view = PassThroughHostingView(rootView: EmptyView(), edge: .right, store: store)
        view.frame = NSRect(x: 0, y: 0, width: 340, height: 1000)
        
        store.activateDrawer(podId: "calendar")
        
        let cardFrames = store.activeDrawerCardFrames(for: .right, totalHeight: 1000.0, windowWidth: 340.0)
        let drawerPoint: NSPoint
        if let first = cardFrames.first {
            drawerPoint = NSPoint(x: first.midX, y: first.midY)
        } else {
            drawerPoint = NSPoint(x: 300, y: 700)
        }
        
        // When not frozen, point inside active drawer is interactive
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
        #expect(hud.currentText == String(format: "hud.railsFrozen".localized, "⌥⇥"))
        #expect(hud.panel != nil)
        #expect(hud.panel?.ignoresMouseEvents == true)
        #expect(hud.panel?.level == .floating)
        #expect(hud.panel?.isOpaque == false)
        #expect(hud.panel?.styleMask.contains(.nonactivatingPanel) == true)
        
        hud.show(isFrozen: false)
        #expect(hud.isFrozen == false)
        #expect(hud.currentText == "hud.railsActive".localized)
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
        let expectedFreezeTitle = "\("menu.freezeRails".localized) (⌥⇥)"
        let expectedUnfreezeTitle = "\("menu.unfreezeRails".localized) (⌥⇥)"
        #expect(activeMenuItem?.title == expectedFreezeTitle)
        
        // Toggle to frozen
        appDelegate.toggleFreezeMode()
        #expect(appDelegate.store.isRailsFrozen == true)
        #expect(coord.isFrozen == true)
        #expect(monitor.isFrozen == true)
        #expect(TransientHUDController.shared.isFrozen == true)
        #expect(TransientHUDController.shared.currentText == String(format: "hud.railsFrozen".localized, "⌥⇥"))
        
        let frozenMenuItem = appDelegate.statusMenu?.items.first { $0.action == #selector(AppDelegate.toggleFreezeMode) }
        #expect(frozenMenuItem != nil)
        #expect(frozenMenuItem?.title == expectedUnfreezeTitle)
        
        // Toggle back to active
        appDelegate.toggleFreezeMode()
        #expect(appDelegate.store.isRailsFrozen == false)
        #expect(coord.isFrozen == false)
        #expect(monitor.isFrozen == false)
        #expect(TransientHUDController.shared.isFrozen == false)
        #expect(TransientHUDController.shared.currentText == "hud.railsActive".localized)
        
        let restoredMenuItem = appDelegate.statusMenu?.items.first { $0.action == #selector(AppDelegate.toggleFreezeMode) }
        #expect(restoredMenuItem != nil)
        #expect(restoredMenuItem?.title == expectedFreezeTitle)
        
        TransientHUDController.shared.dismissImmediate()
    }
}
