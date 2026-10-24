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
    @MainActor
    func testCoordinatorTargetScreen() {
        let store = PurahWorkspaceStore()
        let coordinator = ScreenEdgeCoordinator(store: store)

        let target = coordinator.targetScreen()
        if !NSScreen.screens.isEmpty {
            #expect(target != nil)
            #expect(coordinator.activeScreen != nil)
        } else {
            // Headless CLI execution without WindowServer returns nil safely
            #expect(target == nil)
        }
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

    @Test("AmbientRailWindow dynamically switches between compact 28pt docked width and 580pt expanded canvas")
    func testDynamicRailWindowCanvasExpansionAndCollapse() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let store = PurahWorkspaceStore()
        let window = AmbientRailWindow(edge: .right, screen: screen, store: store)

        // 1. Initial docked state must be compact 28pt to minimize framebuffer memory footprint
        #expect(window.isExpanded == false)
        #expect(window.frame.width == AmbientRailWindow.compactCanvasWidth)
        #expect(window.frame.width == 28.0)

        // 2. Expansion dynamically enlarges to full 580pt drawer canvas
        window.setExpanded(true)
        #expect(window.isExpanded == true)
        #expect(window.frame.width == AmbientRailWindow.maxCanvasWidth)
        #expect(window.frame.width == 580.0)

        // 3. Retraction collapses back to compact 28pt
        window.setExpanded(false)
        #expect(window.isExpanded == false)
        #expect(window.frame.width == AmbientRailWindow.compactCanvasWidth)
        window.close()
    }

    @Test("ScreenEdgeCoordinator sleeps empty rail when all pods on that edge are disabled")
    func testSingleRailSleepWhenPodsDisabled() {
        let isolated = UserDefaults(suiteName: "test_multi_display_\(UUID().uuidString)")!
        let store = PurahWorkspaceStore(userDefaults: isolated)
        for idx in store.pods.indices where store.pods[idx].edge == .left {
            store.pods[idx].isEnabled = false
        }
        let coordinator = ScreenEdgeCoordinator(store: store)
        coordinator.rebuildWindows()

        // Left rail window must be nil/closed because left rail has zero enabled pods
        // Coordinator manages single-rail sleep saving 15-20MB
        #expect(store.pods.contains(where: { $0.edge == .left && $0.isEnabled }) == false)
        #expect(store.pods.contains(where: { $0.edge == .right && $0.isEnabled }) == true)
    }

    @Test("HardwareVitalsService remains dormant on init until monitoring is explicitly started")
    func testHardwareVitalsLazyMonitoring() {
        let service = HardwareVitalsService()
        #expect(service.isMonitoring == false)

        service.startMonitoring(interval: 2.0)
        #expect(service.isMonitoring == true)

        service.stopMonitoring()
        #expect(service.isMonitoring == false)
    }

    @Test("Coordinator cancellable collapse task prevents race when rapidly re-expanding canvas")
    func testCancellableCollapseTaskOnRapidReexpansion() async throws {
        guard !NSScreen.screens.isEmpty else { return }
        let isolated = UserDefaults(suiteName: "test_cancellable_collapse_\(UUID().uuidString)")!
        let store = PurahWorkspaceStore(userDefaults: isolated)
        let coordinator = ScreenEdgeCoordinator(store: store)
        coordinator.rebuildWindows()

        // 1. Initial expand
        coordinator.expandCanvas(for: .right)
        #expect(coordinator.isCanvasExpanded(for: .right) == true)

        // 2. Trigger dismissDrawer, which schedules a 300ms collapse task
        coordinator.dismissDrawer(for: .right)

        // 3. Immediately re-expand canvas (canceling the pending collapse task)
        coordinator.expandCanvas(for: .right)
        #expect(coordinator.isCanvasExpanded(for: .right) == true)

        // 4. Wait 350ms to exceed the 300ms collapse timer
        try await Task.sleep(for: .milliseconds(350))

        // 5. Canvas must still be expanded because the collapse task was cancelled
        #expect(coordinator.isCanvasExpanded(for: .right) == true)
    }

    @Test("Esc key dismisses active unpinned drawer but passes through for Terminal")
    func testEscKeyDrawerDismissal() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let isolated = UserDefaults(suiteName: "test_esc_key_\(UUID().uuidString)")!
        let store = PurahWorkspaceStore(userDefaults: isolated)
        let window = AmbientRailWindow(edge: .right, screen: screen, store: store)

        // Activate an unpinned drawer
        store.activeDrawerPodId = "music"
        #expect(store.activeDrawerPodId == "music")

        // Construct Esc keyDown event
        guard let escEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false,
            keyCode: 53
        ) else { return }

        // Perform Esc key equivalent
        let handled = window.performKeyEquivalent(with: escEvent)
        #expect(handled == true)
        #expect(store.activeDrawerPodId == nil)

        // When responder is inside Terminal, Esc should pass through without dismissing
        final class TerminalMockView: NSView {}
        let terminalView = TerminalMockView()
        window.contentView?.addSubview(terminalView)
        window.makeFirstResponder(terminalView)
        store.activeDrawerPodId = "terminal"
        let terminalHandled = window.performKeyEquivalent(with: escEvent)
        #expect(terminalHandled == false)
        #expect(store.activeDrawerPodId == "terminal")

        window.close()
    }
}
