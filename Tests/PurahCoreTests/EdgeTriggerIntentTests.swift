// Tests/PurahCoreTests/EdgeTriggerIntentTests.swift
import Testing
import AppKit
import Foundation
@testable import PurahCore
@testable import PurahApp

@Suite("Edge Trigger Intent & Push Force Tests", .serialized)
struct EdgeTriggerIntentTests {
    @Test("EdgeTriggerSensitivity presets and push force threshold values")
    @MainActor
    func testPushForcePresets() {
        let agile = EdgeTriggerSensitivity.agile
        let balanced = EdgeTriggerSensitivity.balanced
        let cautious = EdgeTriggerSensitivity.cautious

        #expect(agile.pushForceThreshold == 260.0)
        #expect(balanced.pushForceThreshold == 380.0)
        #expect(cautious.pushForceThreshold == 520.0)

        let store = PurahWorkspaceStore()
        store.applySensitivityPreset(.agile)
        #expect(store.activePushForceThreshold == 260.0)

        store.applySensitivityPreset(.balanced)
        #expect(store.activePushForceThreshold == 380.0)

        store.applySensitivityPreset(.cautious)
        #expect(store.activePushForceThreshold == 520.0)

        store.edgeTriggerSensitivity = .custom
        store.customPushForceThreshold = 440.0
        #expect(store.activePushForceThreshold == 440.0)
        store.savePersistentState()

        let reloaded = PurahWorkspaceStore()
        #expect(reloaded.edgeTriggerSensitivity == .custom)
        #expect(reloaded.customPushForceThreshold == 440.0)

        // Cleanup
        UserDefaults.standard.removeObject(forKey: "purah.edgeTriggerSensitivity")
        UserDefaults.standard.removeObject(forKey: "purah.customPushForceThreshold")
    }

    @Test("Edge push force breakthrough triggers drawer immediately without dwell delay")
    @MainActor
    func testPushForceBreakthroughImmediateTrigger() {
        let store = PurahWorkspaceStore()
        store.activeDrawerPodId = nil
        store.activeDrawerItemId = nil
        store.edgeTriggerMode = .pushForce // Mutually exclusive Push Force mode
        store.edgeTriggerSensitivity = .balanced // 380 pt/s push force

        let monitor = EdgeMouseMonitor(store: store)
        let visibleRect = NSRect(x: 0, y: 0, width: 1440, height: 900)
        monitor.customTargetVisibleRect = visibleRect

        // Find a pod on the left rail
        let layoutItems = store.resolvedPhysicalLayout(for: .left, totalHeight: 900.0)
        guard let firstItem = layoutItems.first else {
            #expect(Bool(false), "No pod on left rail")
            return
        }
        let targetY = visibleRect.maxY - CGFloat(firstItem.startY + firstItem.spanH / 2.0)
        let edgePoint = NSPoint(x: 2.0, y: targetY)
        monitor.customCurrentMouseLocation = edgePoint

        // Push into the left edge with 450 pt/s velocity (Vx = -450 pt/s, Vy = 20 pt/s)
        let pushVelocity = CGPoint(x: -450.0, y: 20.0)
        monitor.processMouse(point: edgePoint, now: Date(), customVelocity: pushVelocity)

        // Because push force (450 pt/s) exceeded activePushForceThreshold (380 pt/s),
        // it must trigger immediately on the spot (0ms delay)!
        #expect(store.activeDrawerPodId == firstItem.pod.id)
    }

    @Test("Hover Dwell mode does not trigger on push force without dwelling")
    @MainActor
    func testHoverDwellModeIgnoresPushForce() {
        let store = PurahWorkspaceStore()
        store.activeDrawerPodId = nil
        store.activeDrawerItemId = nil
        store.edgeTriggerMode = .hoverDwell // Mutually exclusive Hover Dwell mode
        store.edgeTriggerSensitivity = .balanced

        let monitor = EdgeMouseMonitor(store: store)
        let visibleRect = NSRect(x: 0, y: 0, width: 1440, height: 900)
        monitor.customTargetVisibleRect = visibleRect

        let layoutItems = store.resolvedPhysicalLayout(for: .left, totalHeight: 900.0)
        guard let firstItem = layoutItems.first else { return }
        let targetY = visibleRect.maxY - CGFloat(firstItem.startY + firstItem.spanH / 2.0)
        let edgePoint = NSPoint(x: 10.0, y: targetY)
        monitor.customCurrentMouseLocation = edgePoint

        // High push velocity in Hover Dwell mode
        let pushVelocity = CGPoint(x: -500.0, y: 10.0)
        monitor.processMouse(point: edgePoint, now: Date(), customVelocity: pushVelocity)

        // Must NOT trigger immediately because mode is hoverDwell (mutual exclusivity)
        #expect(store.activeDrawerPodId == nil)
    }

    @Test("Low inward velocity does not trigger push force breakthrough immediately")
    @MainActor
    func testLowVelocityDoesNotTriggerImmediately() {
        let store = PurahWorkspaceStore()
        store.activeDrawerPodId = nil
        store.activeDrawerItemId = nil
        store.edgeTriggerMode = .pushForce
        store.edgeTriggerSensitivity = .balanced // 380 pt/s push force

        let monitor = EdgeMouseMonitor(store: store)
        let visibleRect = NSRect(x: 0, y: 0, width: 1440, height: 900)
        monitor.customTargetVisibleRect = visibleRect

        let layoutItems = store.resolvedPhysicalLayout(for: .left, totalHeight: 900.0)
        guard let firstItem = layoutItems.first else { return }
        let targetY = visibleRect.maxY - CGFloat(firstItem.startY + firstItem.spanH / 2.0)
        let edgePoint = NSPoint(x: 10.0, y: targetY)
        monitor.customCurrentMouseLocation = edgePoint

        // Low speed glide into left edge (Vx = -100 pt/s < 380 pt/s)
        let lowVelocity = CGPoint(x: -100.0, y: 10.0)
        monitor.processMouse(point: edgePoint, now: Date(), customVelocity: lowVelocity)

        // Must NOT trigger immediately
        #expect(store.activeDrawerPodId == nil)
    }

    @Test("Excessive vertical velocity suppresses push force breakthrough")
    @MainActor
    func testVerticalFlingSuppressesPushForceBreakthrough() {
        let store = PurahWorkspaceStore()
        store.activeDrawerPodId = nil
        store.activeDrawerItemId = nil
        store.edgeTriggerSensitivity = .balanced

        let monitor = EdgeMouseMonitor(store: store)
        let visibleRect = NSRect(x: 0, y: 0, width: 1440, height: 900)
        monitor.customTargetVisibleRect = visibleRect

        let layoutItems = store.resolvedPhysicalLayout(for: .left, totalHeight: 900.0)
        guard let firstItem = layoutItems.first else { return }
        let targetY = visibleRect.maxY - CGFloat(firstItem.startY + firstItem.spanH / 2.0)
        let edgePoint = NSPoint(x: 10.0, y: targetY)
        monitor.customCurrentMouseLocation = edgePoint

        // Fast vertical swipe along the bezel (Vx = -400 pt/s, Vy = 850 pt/s)
        let verticalFlingVelocity = CGPoint(x: -400.0, y: 850.0)
        monitor.processMouse(point: edgePoint, now: Date(), customVelocity: verticalFlingVelocity)

        // Must NOT trigger push breakthrough because vertical drift is dominant
        #expect(store.activeDrawerPodId == nil)
    }

    @Test("Initial hover dwell timer triggers drawer after dwell duration")
    @MainActor
    func testHoverDwellTimerTriggersDrawer() async {
        let store = PurahWorkspaceStore()
        store.activeDrawerPodId = nil
        store.activeDrawerItemId = nil
        store.edgeTriggerMode = .hoverDwell
        store.edgeTriggerSensitivity = .balanced // 150ms dwell

        let monitor = EdgeMouseMonitor(store: store)
        let visibleRect = NSRect(x: 0, y: 0, width: 1440, height: 900)
        monitor.customTargetVisibleRect = visibleRect

        let layoutItems = store.resolvedPhysicalLayout(for: .left, totalHeight: 900.0)
        guard let firstItem = layoutItems.first else { return }
        let targetY = visibleRect.maxY - CGFloat(firstItem.startY + firstItem.spanH / 2.0)
        let edgePoint = NSPoint(x: 10.0, y: targetY)
        monitor.customCurrentMouseLocation = edgePoint

        // Move to edge and rest still (zero velocity)
        monitor.processMouse(point: edgePoint, now: Date(), customVelocity: .zero)

        // Immediately after reaching edge, drawer is still docked
        #expect(store.activeDrawerPodId == nil)

        // Condition-based polling: wait up to 400ms for dwell timer to fire
        for _ in 1...8 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            if store.activeDrawerPodId != nil { break }
        }

        // Dwell timer elapsed: drawer must now be expanded!
        #expect(store.activeDrawerPodId == firstItem.pod.id)
    }

    @Test("Exiting edge before dwell duration cancels initial dwell task")
    @MainActor
    func testExitingEdgeCancelsDwell() async {
        let store = PurahWorkspaceStore()
        store.activeDrawerPodId = nil
        store.activeDrawerItemId = nil
        store.edgeTriggerMode = .hoverDwell
        store.edgeTriggerSensitivity = .balanced // 150ms dwell

        let monitor = EdgeMouseMonitor(store: store)
        let visibleRect = NSRect(x: 0, y: 0, width: 1440, height: 900)
        monitor.customTargetVisibleRect = visibleRect

        let layoutItems = store.resolvedPhysicalLayout(for: .left, totalHeight: 900.0)
        guard let firstItem = layoutItems.first else { return }
        let targetY = visibleRect.maxY - CGFloat(firstItem.startY + firstItem.spanH / 2.0)
        let edgePoint = NSPoint(x: 10.0, y: targetY)
        monitor.customCurrentMouseLocation = edgePoint

        // Move to edge
        monitor.processMouse(point: edgePoint, now: Date(), customVelocity: .zero)
        #expect(store.activeDrawerPodId == nil)

        // Move away after 30ms (< 150ms)
        try? await Task.sleep(nanoseconds: 30_000_000)
        let centerPoint = NSPoint(x: 500.0, y: 500.0)
        monitor.customCurrentMouseLocation = centerPoint
        monitor.processMouse(point: centerPoint, now: Date(), customVelocity: CGPoint(x: 200, y: 0))

        // Wait past original dwell duration
        try? await Task.sleep(nanoseconds: 180_000_000)

        // Drawer must NOT be open because cursor stepped away
        #expect(store.activeDrawerPodId == nil)
    }

    @Test("Moving between pods cancels previous dwell and starts new candidate dwell")
    @MainActor
    func testMovingBetweenPodsReschedulesDwell() async {
        let store = PurahWorkspaceStore()
        store.activeDrawerPodId = nil
        store.activeDrawerItemId = nil
        store.edgeTriggerMode = .hoverDwell
        store.edgeTriggerSensitivity = .balanced // 150ms dwell

        let monitor = EdgeMouseMonitor(store: store)
        let visibleRect = NSRect(x: 0, y: 0, width: 1440, height: 900)
        monitor.customTargetVisibleRect = visibleRect

        let layoutItems = store.resolvedPhysicalLayout(for: .left, totalHeight: 900.0)
        guard layoutItems.count >= 2 else { return }
        let pod1 = layoutItems[0]
        let pod2 = layoutItems[1]

        let y1 = visibleRect.maxY - CGFloat(pod1.startY + pod1.spanH / 2.0)
        let y2 = visibleRect.maxY - CGFloat(pod2.startY + pod2.spanH / 2.0)

        // 1. Enter Pod 1
        monitor.customCurrentMouseLocation = NSPoint(x: 10.0, y: y1)
        monitor.processMouse(point: NSPoint(x: 10.0, y: y1), now: Date(), customVelocity: .zero)
        #expect(store.activeDrawerPodId == nil)

        // 2. Before Pod 1 dwell fires (after 40ms), slide to Pod 2
        try? await Task.sleep(nanoseconds: 40_000_000)
        monitor.customCurrentMouseLocation = NSPoint(x: 10.0, y: y2)
        monitor.processMouse(point: NSPoint(x: 10.0, y: y2), now: Date(), customVelocity: .zero)

        // 3. Condition-based wait for Pod 2 dwell to complete
        for _ in 1...8 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            if store.activeDrawerPodId != nil { break }
        }

        // Pod 2 must be the one that popped open!
        #expect(store.activeDrawerPodId == pod2.pod.id)
    }

    @Test("Frozen state suppresses both push force and dwell triggers")
    @MainActor
    func testFrozenSuppression() async {
        let store = PurahWorkspaceStore()
        store.activeDrawerPodId = nil
        store.activeDrawerItemId = nil
        store.edgeTriggerSensitivity = .balanced

        let monitor = EdgeMouseMonitor(store: store)
        let visibleRect = NSRect(x: 0, y: 0, width: 1440, height: 900)
        monitor.customTargetVisibleRect = visibleRect

        let layoutItems = store.resolvedPhysicalLayout(for: .left, totalHeight: 900.0)
        guard let firstItem = layoutItems.first else { return }
        let targetY = visibleRect.maxY - CGFloat(firstItem.startY + firstItem.spanH / 2.0)
        let edgePoint = NSPoint(x: 10.0, y: targetY)
        monitor.customCurrentMouseLocation = edgePoint

        // Set frozen
        monitor.setFrozen(true)

        // 1. Try push force
        store.edgeTriggerMode = .pushForce
        monitor.processMouse(point: edgePoint, now: Date(), customVelocity: CGPoint(x: -500.0, y: 0.0))
        #expect(store.activeDrawerPodId == nil)

        // 2. Try hover dwell
        store.edgeTriggerMode = .hoverDwell
        monitor.processMouse(point: edgePoint, now: Date(), customVelocity: .zero)
        try? await Task.sleep(nanoseconds: 120_000_000)
        #expect(store.activeDrawerPodId == nil)
    }

    @Test("Push force mode ignores stationary hover dwell without pushing")
    @MainActor
    func testPushForceModeIgnoresHoverDwell() async {
        let store = PurahWorkspaceStore()
        store.activeDrawerPodId = nil
        store.activeDrawerItemId = nil
        store.edgeTriggerMode = .pushForce // Mutually exclusive Push Force
        store.edgeTriggerSensitivity = .agile

        let monitor = EdgeMouseMonitor(store: store)
        let visibleRect = NSRect(x: 0, y: 0, width: 1440, height: 900)
        monitor.customTargetVisibleRect = visibleRect

        let layoutItems = store.resolvedPhysicalLayout(for: .left, totalHeight: 900.0)
        guard let firstItem = layoutItems.first else { return }
        let targetY = visibleRect.maxY - CGFloat(firstItem.startY + firstItem.spanH / 2.0)
        let edgePoint = NSPoint(x: 10.0, y: targetY)
        monitor.customCurrentMouseLocation = edgePoint

        // Rest stationary at edge in pushForce mode
        monitor.processMouse(point: edgePoint, now: Date(), customVelocity: .zero)
        #expect(store.activeDrawerPodId == nil)

        // Wait past dwell duration
        try? await Task.sleep(nanoseconds: 120_000_000)

        // Must remain closed because push force was not exceeded
        #expect(store.activeDrawerPodId == nil)
    }

    @Test("Attention alert acknowledgment state and reset")
    @MainActor
    func testAttentionAlertAcknowledgment() {
        let store = PurahWorkspaceStore()
        let eventId = "meeting-123"

        #expect(store.isAlertAcknowledged(id: eventId) == false)

        store.acknowledgeAlert(id: eventId)
        #expect(store.isAlertAcknowledged(id: eventId) == true)

        store.resetAlertAcknowledgment(id: eventId)
        #expect(store.isAlertAcknowledged(id: eventId) == false)
    }

    @Test("Agile mode triggers 0ms instant popup on hover without dwell wait")
    @MainActor
    func testAgileModeInstantHoverTrigger() {
        let store = PurahWorkspaceStore()
        store.activeDrawerPodId = nil
        store.activeDrawerItemId = nil
        store.edgeTriggerMode = .hoverDwell
        store.edgeTriggerSensitivity = .agile // 0ms instant hover

        let monitor = EdgeMouseMonitor(store: store)
        let visibleRect = NSRect(x: 0, y: 0, width: 1440, height: 900)
        monitor.customTargetVisibleRect = visibleRect

        let layoutItems = store.resolvedPhysicalLayout(for: .left, totalHeight: 900.0)
        guard let firstItem = layoutItems.first else { return }
        let targetY = visibleRect.maxY - CGFloat(firstItem.startY + firstItem.spanH / 2.0)
        let edgePoint = NSPoint(x: 10.0, y: targetY)
        monitor.customCurrentMouseLocation = edgePoint

        // On first hover event in agile mode, it must trigger immediately!
        monitor.processMouse(point: edgePoint, now: Date(), customVelocity: .zero)
        #expect(store.activeDrawerPodId == firstItem.pod.id)
    }

    @Test("Push force mode triggers instantly on high inward velocity of 1500 pt/s")
    @MainActor
    func testPushForceHighVelocityThrust() {
        let store = PurahWorkspaceStore()
        store.activeDrawerPodId = nil
        store.activeDrawerItemId = nil
        store.edgeTriggerMode = .pushForce
        store.edgeTriggerSensitivity = .balanced

        let monitor = EdgeMouseMonitor(store: store)
        let visibleRect = NSRect(x: 0, y: 0, width: 1440, height: 900)
        monitor.customTargetVisibleRect = visibleRect

        let layoutItems = store.resolvedPhysicalLayout(for: .left, totalHeight: 900.0)
        guard let firstItem = layoutItems.first else { return }
        let targetY = visibleRect.maxY - CGFloat(firstItem.startY + firstItem.spanH / 2.0)
        let edgePoint = NSPoint(x: 2.0, y: targetY)
        monitor.customCurrentMouseLocation = edgePoint

        // High inward thrust of 1500 pt/s into bezel
        let thrustVelocity = CGPoint(x: -1500.0, y: 30.0)
        monitor.processMouse(point: edgePoint, now: Date(), customVelocity: thrustVelocity)
        #expect(store.activeDrawerPodId == firstItem.pod.id)
    }

    @Test("Empty gap between pods does not trigger accidental drawer popup")
    @MainActor
    func testGapBetweenPodsDoesNotTrigger() {
        let store = PurahWorkspaceStore()
        store.activeDrawerPodId = nil
        store.activeDrawerItemId = nil
        store.edgeTriggerMode = .hoverDwell
        store.edgeTriggerSensitivity = .agile

        let monitor = EdgeMouseMonitor(store: store)
        let visibleRect = NSRect(x: 0, y: 0, width: 1440, height: 900)
        monitor.customTargetVisibleRect = visibleRect

        let layoutItems = store.resolvedPhysicalLayout(for: .left, totalHeight: 900.0)
        guard layoutItems.count >= 2 else { return }
        let pod1 = layoutItems[0]
        let pod2 = layoutItems[1]

        // Midpoint gap between pod1 and pod2
        let gapY = (pod1.startY + pod1.spanH + pod2.startY) / 2.0
        let targetY = visibleRect.maxY - CGFloat(gapY)
        let edgePoint = NSPoint(x: 10.0, y: targetY)
        monitor.customCurrentMouseLocation = edgePoint

        // Hover in empty gap: must NOT accidentally trigger a pod where no bar exists
        monitor.processMouse(point: edgePoint, now: Date(), customVelocity: .zero)
        #expect(store.activeDrawerPodId == nil)
    }

    @Test("Menu bar and screen corners 100% suppress drawer popup and do not snap")
    @MainActor
    func testMenuBarAndCornerSuppression() {
        let store = PurahWorkspaceStore()
        store.activeDrawerPodId = nil
        store.activeDrawerItemId = nil
        store.edgeTriggerMode = .hoverDwell
        store.edgeTriggerSensitivity = .agile // Even in agile instant mode!

        let monitor = EdgeMouseMonitor(store: store)
        let visibleRect = NSRect(x: 0, y: 70, width: 1440, height: 874) // e.g. Dock at bottom (70), Menu Bar at top (944)
        monitor.customTargetVisibleRect = visibleRect

        // 1. Point inside macOS Menu Bar (top-left Apple menu at y = 960 > visibleRect.maxY)
        let appleMenuPoint = NSPoint(x: 5.0, y: 960.0)
        monitor.customCurrentMouseLocation = appleMenuPoint
        monitor.processMouse(point: appleMenuPoint, now: Date(), customVelocity: .zero)
        #expect(store.activeDrawerPodId == nil, "Menu Bar top-left must not trigger drawer")

        // 2. Point inside macOS Menu Bar top-right (Control Center at x = 1440, y = 960)
        let controlCenterPoint = NSPoint(x: 1438.0, y: 960.0)
        monitor.customCurrentMouseLocation = controlCenterPoint
        monitor.processMouse(point: controlCenterPoint, now: Date(), customVelocity: .zero)
        #expect(store.activeDrawerPodId == nil, "Menu Bar top-right must not trigger drawer")

        // 3. Point inside macOS Dock area (bottom-left at y = 30 < visibleRect.minY)
        let dockPoint = NSPoint(x: 5.0, y: 30.0)
        monitor.customCurrentMouseLocation = dockPoint
        monitor.processMouse(point: dockPoint, now: Date(), customVelocity: .zero)
        #expect(store.activeDrawerPodId == nil, "Dock bottom corner must not trigger drawer")

        // 4. Point in empty top rail margin above first pod (e.g. y = 942, inside visibleFrame but above safeTop)
        let emptyTopMarginPoint = NSPoint(x: 5.0, y: 942.0)
        monitor.customCurrentMouseLocation = emptyTopMarginPoint
        monitor.processMouse(point: emptyTopMarginPoint, now: Date(), customVelocity: .zero)
        #expect(store.activeDrawerPodId == nil, "Empty top margin must not snap to pod")
    }

    @Test("VelocityTracker submillisecond deduplication prevents velocity collapse")
    func testVelocityTrackerSubmillisecondDeduplication() {
        var tracker = VelocityTracker()
        let t0 = Date()

        // First sample
        tracker.add(point: CGPoint(x: 100, y: 100), timestamp: t0)

        // Sub-millisecond duplicate sample from dual monitors (e.g. 0.5ms later)
        let tDuplicate = t0.addingTimeInterval(0.0005)
        tracker.add(point: CGPoint(x: 102, y: 100), timestamp: tDuplicate)

        // Real subsequent sample 25ms later with significant delta
        let t2 = t0.addingTimeInterval(0.025)
        tracker.add(point: CGPoint(x: 150, y: 100), timestamp: t2)

        let vel = tracker.currentVelocity()
        // Must calculate a non-zero velocity across the ~25ms delta, not collapsing to zero!
        #expect(vel.x > 1000.0, "Velocity must be calculated accurately across stable time window")
    }

    @Test("Strict 12pt edge anti-accidental touch band triggers on pod and strictly suppresses beyond 12pt")
    @MainActor
    func testStrict12ptEdgeBandTriggerAndSuppression() {
        let store = PurahWorkspaceStore()
        store.activeDrawerPodId = nil
        store.activeDrawerItemId = nil
        store.edgeTriggerMode = .hoverDwell
        store.edgeTriggerSensitivity = .agile

        let monitor = EdgeMouseMonitor(store: store)
        let visibleRect = NSRect(x: 0, y: 0, width: 1440, height: 900)
        monitor.customTargetVisibleRect = visibleRect

        let layoutItems = store.resolvedPhysicalLayout(for: .right, totalHeight: 900.0)
        guard let firstItem = layoutItems.first else { return }
        let targetY = visibleRect.maxY - CGFloat(firstItem.startY + firstItem.spanH / 2.0)

        // 1. Outside test: Point at x = 1440 - 18 (18pt from right bezel, outside the 12pt pod band)
        let outsidePoint = NSPoint(x: 1422.0, y: targetY)
        monitor.customCurrentMouseLocation = outsidePoint
        monitor.processMouse(point: outsidePoint, now: Date(), customVelocity: .zero)
        #expect(store.activeDrawerPodId == nil, "18pt outside pod band must be strictly suppressed to prevent false triggers")

        // 2. Inside test: Point at x = 1440 - 10 (10pt from right bezel, strictly inside the 12pt pod band)
        let insidePoint = NSPoint(x: 1430.0, y: targetY)
        monitor.customCurrentMouseLocation = insidePoint
        monitor.processMouse(point: insidePoint, now: Date(), customVelocity: .zero)
        #expect(store.activeDrawerPodId == firstItem.pod.id, "10pt strictly inside pod band must trigger drawer")
    }

    @Test("PushForceAccumulator accumulates raw motion deltas and breaks through resistance barrier")
    func testPushForceAccumulatorThresholdBreakthrough() {
        var accumulator = PushForceAccumulator()
        let now = Date()

        // Push 1: 15px delta
        let res1 = accumulator.push(outwardDelta: 15.0, timestamp: now, threshold: 36.0)
        #expect(!res1, "15px push must not break through 36px threshold")
        #expect(accumulator.accumulatedForce == 15.0)

        // Push 2: 12px delta (now + 0.05s)
        let res2 = accumulator.push(outwardDelta: 12.0, timestamp: now.addingTimeInterval(0.05), threshold: 36.0)
        #expect(!res2, "27px accumulated force must not break through 36px threshold")
        #expect(accumulator.accumulatedForce == 27.0)

        // Push 3: 15px delta (now + 0.08s) -> Total 42px >= 36px threshold!
        let res3 = accumulator.push(outwardDelta: 15.0, timestamp: now.addingTimeInterval(0.08), threshold: 36.0)
        #expect(res3, "42px accumulated force must break through resistance barrier")
        #expect(accumulator.accumulatedForce == 0.0, "Accumulator must reset upon breakthrough")
    }

    @Test("PushForceAccumulator resets on leaky bucket decay timeout")
    func testPushForceAccumulatorLeakyBucketDecay() {
        var accumulator = PushForceAccumulator()
        let now = Date()

        _ = accumulator.push(outwardDelta: 25.0, timestamp: now, threshold: 36.0)
        #expect(accumulator.accumulatedForce == 25.0)

        // User stops pushing for 250ms (> 180ms decay timeout)
        let later = now.addingTimeInterval(0.25)
        _ = accumulator.push(outwardDelta: 5.0, timestamp: later, threshold: 36.0)

        // The previous 25.0 must have decayed and reset, only new 5.0 accumulated!
        #expect(accumulator.accumulatedForce == 5.0, "Accumulated force must decay after timeout")
    }

    @Test("PushForceAccumulator resets immediately on inward retreat")
    func testPushForceAccumulatorInwardRetreatReset() {
        var accumulator = PushForceAccumulator()
        let now = Date()

        _ = accumulator.push(outwardDelta: 28.0, timestamp: now, threshold: 36.0)
        #expect(accumulator.accumulatedForce == 28.0)

        // Cursor moves inward away from bezel (outwardDelta = -2.5)
        let res = accumulator.push(outwardDelta: -2.5, timestamp: now.addingTimeInterval(0.02), threshold: 36.0)
        #expect(!res)
        #expect(accumulator.accumulatedForce == 0.0, "Retreating inward must immediately reset accumulator for anti-accidental safety")
    }

    @Test("PushForceAccumulator triggers on double-tap strike impulse")
    func testPushForceAccumulatorDoubleTapImpulse() {
        var accumulator = PushForceAccumulator()
        let now = Date()

        // Strike 1: 24.0px impulse
        let res1 = accumulator.push(outwardDelta: 24.0, timestamp: now, threshold: 50.0)
        #expect(!res1, "First strike does not trigger")

        // Strike 2: 23.0px impulse within 200ms
        let res2 = accumulator.push(outwardDelta: 23.0, timestamp: now.addingTimeInterval(0.15), threshold: 50.0)
        #expect(res2, "Double-tap strike impulse within 280ms must break through barrier")
    }

    @Test("Event toast notification fires when event starts and deduplicates")
    @MainActor
    func testEventToastAlertNotification() {
        let store = PurahWorkspaceStore()
        var toastReceived: String?
        store.onCapacityWarningToast = { toastReceived = $0 }
        store.isEventToastAlertEnabled = true

        let event = CalendarEventItem(
            id: "toast-event-1",
            title: "Executive Standup",
            location: "Room 1",
            startTime: Date(),
            endTime: Date().addingTimeInterval(3600)
        )

        // 1. First alert notification
        store.notifyEventAlertIfNeeded(for: event)
        #expect(toastReceived?.contains("Executive Standup") == true)

        // 2. Subsequent alert for same event should deduplicate
        toastReceived = nil
        store.notifyEventAlertIfNeeded(for: event)
        #expect(toastReceived == nil, "Duplicate toast for same event must be suppressed")

        // 3. When disabled, no toast is fired
        store.isEventToastAlertEnabled = false
        let event2 = CalendarEventItem(
            id: "toast-event-2",
            title: "Product Launch",
            location: "Room 2",
            startTime: Date(),
            endTime: Date().addingTimeInterval(3600)
        )
        store.notifyEventAlertIfNeeded(for: event2)
        #expect(toastReceived == nil, "Toast must not fire when isEventToastAlertEnabled is false")
    }

    @Test("Seamless re-entry after retraction: multiple successive entries and exits work repeatedly without locking out")
    @MainActor
    func testSeamlessReentryAfterRetractionCycle() async {
        let store = PurahWorkspaceStore()
        store.activeDrawerPodId = nil
        store.activeDrawerItemId = nil
        store.edgeTriggerMode = .hoverDwell
        store.edgeTriggerSensitivity = .agile

        let coordinator = ScreenEdgeCoordinator(store: store)
        let monitor = EdgeMouseMonitor(store: store, coordinator: coordinator)
        let visibleRect = NSRect(x: 0, y: 0, width: 1440, height: 900)
        monitor.customTargetVisibleRect = visibleRect

        let layoutItems = store.resolvedPhysicalLayout(for: .left, totalHeight: 900.0)
        guard let firstItem = layoutItems.first else { return }
        let targetY = visibleRect.maxY - CGFloat(firstItem.startY + firstItem.spanH / 2.0)
        let edgePoint = NSPoint(x: 8.0, y: targetY)
        let desktopPoint = NSPoint(x: 400.0, y: targetY)

        // CYCLE 1: First Entry
        monitor.customCurrentMouseLocation = edgePoint
        monitor.processMouse(point: edgePoint, now: Date(), customVelocity: .zero)
        #expect(store.activeDrawerPodId == firstItem.pod.id, "Cycle 1: First entry must open drawer")

        // Retract: move to desktop and dismiss
        monitor.customCurrentMouseLocation = desktopPoint
        monitor.processMouse(point: desktopPoint, now: Date(), customVelocity: .zero)
        coordinator.dismissDrawer(for: .left)
        #expect(store.activeDrawerPodId == nil, "Drawer must be fully retracted")

        // CYCLE 2: Re-entry must trigger just like first launch!
        monitor.customCurrentMouseLocation = edgePoint
        monitor.processMouse(point: edgePoint, now: Date().addingTimeInterval(0.5), customVelocity: .zero)
        #expect(store.activeDrawerPodId == firstItem.pod.id, "Cycle 2: Re-entering retracted rail must open drawer")

        // Retract again
        monitor.customCurrentMouseLocation = desktopPoint
        monitor.processMouse(point: desktopPoint, now: Date().addingTimeInterval(1.0), customVelocity: .zero)
        coordinator.dismissDrawer(for: .left)
        #expect(store.activeDrawerPodId == nil, "Drawer must be fully retracted second time")

        // CYCLE 3: Third entry must also trigger!
        monitor.customCurrentMouseLocation = edgePoint
        monitor.processMouse(point: edgePoint, now: Date().addingTimeInterval(1.5), customVelocity: .zero)
        #expect(store.activeDrawerPodId == firstItem.pod.id, "Cycle 3: Third entry must also open drawer without getting locked out")
    }

    @Test("Swipe across pod (shorter than configured dwell) is strictly rejected without opening drawer")
    @MainActor
    func testSwipeAcrossPodDoesNotTriggerDrawer() async {
        let store = PurahWorkspaceStore()
        store.activeDrawerPodId = nil
        store.activeDrawerItemId = nil
        store.edgeTriggerMode = .hoverDwell
        store.edgeTriggerSensitivity = .custom
        store.customInitialDwellMs = 400.0 // 400ms dwell required

        let coordinator = ScreenEdgeCoordinator(store: store)
        let monitor = EdgeMouseMonitor(store: store, coordinator: coordinator)
        let visibleRect = NSRect(x: 0, y: 0, width: 1440, height: 900)
        monitor.customTargetVisibleRect = visibleRect

        let layoutItems = store.resolvedPhysicalLayout(for: .left, totalHeight: 900.0)
        guard let firstItem = layoutItems.first else { return }
        let targetY = visibleRect.maxY - CGFloat(firstItem.startY + firstItem.spanH / 2.0)
        let edgePoint = NSPoint(x: 8.0, y: targetY)
        let awayPoint = NSPoint(x: 200.0, y: targetY)

        let startTime = Date()
        // 1. Enter pod at t = 0
        monitor.customCurrentMouseLocation = edgePoint
        monitor.processMouse(point: edgePoint, now: startTime, customVelocity: .zero)
        #expect(store.activeDrawerPodId == nil, "Must not trigger immediately on entry")

        // 2. Swipe past: after 80ms (way before 400ms dwell), mouse leaves pod to awayPoint
        let swipeLeaveTime = startTime.addingTimeInterval(0.08)
        monitor.customCurrentMouseLocation = awayPoint
        monitor.processMouse(point: awayPoint, now: swipeLeaveTime, customVelocity: .zero)

        // 3. Wait for 500ms (longer than the 400ms timer)
        try? await Task.sleep(for: .milliseconds(500))

        // Must remain closed because user only swiped across!
        #expect(store.activeDrawerPodId == nil, "Swipe shorter than 400ms dwell must NOT pop open drawer")
    }

    @Test("Hover resting on pod exceeding configured dwell opens drawer reliably")
    @MainActor
    func testHoverRestingOnPodExceedingDwellOpensDrawer() async {
        let store = PurahWorkspaceStore()
        store.activeDrawerPodId = nil
        store.activeDrawerItemId = nil
        store.edgeTriggerMode = .hoverDwell
        store.edgeTriggerSensitivity = .custom
        store.customInitialDwellMs = 300.0 // 300ms dwell required

        let coordinator = ScreenEdgeCoordinator(store: store)
        let monitor = EdgeMouseMonitor(store: store, coordinator: coordinator)
        let visibleRect = NSRect(x: 0, y: 0, width: 1440, height: 900)
        monitor.customTargetVisibleRect = visibleRect

        let layoutItems = store.resolvedPhysicalLayout(for: .left, totalHeight: 900.0)
        guard let firstItem = layoutItems.first else { return }
        let targetY = visibleRect.maxY - CGFloat(firstItem.startY + firstItem.spanH / 2.0)
        let edgePoint = NSPoint(x: 8.0, y: targetY)

        let startTime = Date()
        monitor.customCurrentMouseLocation = edgePoint
        monitor.processMouse(point: edgePoint, now: startTime, customVelocity: .zero)
        #expect(store.activeDrawerPodId == nil, "Must wait for 300ms dwell")

        // Wait 350ms (longer than 300ms)
        try? await Task.sleep(for: .milliseconds(350))

        #expect(store.activeDrawerPodId == firstItem.pod.id, "Resting on pod past 300ms dwell must open drawer")
    }

    @Test("Push force mode requires post-arrival outward pushing against bezel to open drawer")
    @MainActor
    func testPushForceModeRequiresPostArrivalOutwardPush() {
        let store = PurahWorkspaceStore()
        store.activeDrawerPodId = nil
        store.activeDrawerItemId = nil
        store.edgeTriggerMode = .pushForce
        store.edgeTriggerSensitivity = .balanced

        let coordinator = ScreenEdgeCoordinator(store: store)
        let monitor = EdgeMouseMonitor(store: store, coordinator: coordinator)
        let visibleRect = NSRect(x: 0, y: 0, width: 1440, height: 900)
        monitor.customTargetVisibleRect = visibleRect

        let layoutItems = store.resolvedPhysicalLayout(for: .left, totalHeight: 900.0)
        guard let firstItem = layoutItems.first else { return }
        let targetY = visibleRect.maxY - CGFloat(firstItem.startY + firstItem.spanH / 2.0)

        // Step 1: Arrive at edge calmly without breakthrough
        let bezelPoint = NSPoint(x: 2.0, y: targetY)
        monitor.customCurrentMouseLocation = bezelPoint
        monitor.processMouse(point: bezelPoint, now: Date(), customVelocity: CGPoint(x: -80.0, y: 0.0))
        #expect(store.activeDrawerPodId == nil, "Merely arriving at edge without pushing must not open drawer")

        // Step 2: Push outward against bezel with hardware delta
        monitor.handleHardwareRawMotion(point: bezelPoint, rawDeltaX: -20.0)
        #expect(store.activeDrawerPodId == nil, "First 20px push is below 36px barrier threshold")

        // Step 3: Continue pushing outward (another 20px -> total 40px >= 36px threshold!)
        monitor.handleHardwareRawMotion(point: bezelPoint, rawDeltaX: -20.0)
        #expect(store.activeDrawerPodId == firstItem.pod.id, "Pushing past 36px barrier threshold must break through and open drawer")
    }
}
