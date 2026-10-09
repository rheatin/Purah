// Sources/PurahApp/Interaction/EdgeMouseMonitor.swift
import AppKit
import SwiftUI
import Foundation
import CoreGraphics
import PurahCore

@MainActor
public final class EdgeMouseMonitor {
    private let store: PurahWorkspaceStore
    private weak var coordinator: ScreenEdgeCoordinator?
    private var velocityTracker = VelocityTracker()
    private var pushAccumulator = PushForceAccumulator()
    private let flingDetector = FlingIntentDetector()
    private var dwellTracker = DwellTracker(threshold: 0.16)
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var leftExitGraceTask: Task<Void, Never>?
    private var rightExitGraceTask: Task<Void, Never>?
    private var initialDwellTask: Task<Void, Never>?
    private var currentDwellCandidatePodId: String?
    private var currentDwellEdge: MountEdge?
    private var lastCandidatePodId: String?
    private var candidateHoverStartTime: Date?
    private var wasAtAbsoluteBezel: Bool = false
    private var bezelArrivalTime: Date? = nil
    public private(set) var isFrozen: Bool = false
    public static weak var shared: EdgeMouseMonitor?

    /// Test hooks to mock screen visible frame and mouse location in headless unit tests
    public var customTargetVisibleRect: CGRect?
    public var customCurrentMouseLocation: NSPoint?

    public init(store: PurahWorkspaceStore, coordinator: ScreenEdgeCoordinator? = nil) {
        self.store = store
        self.coordinator = coordinator
        Self.shared = self
        store.onLocalMouseMove = { [weak self] event in
            self?.handleMouse(event: event)
        }
    }

    public func setCoordinator(_ coordinator: ScreenEdgeCoordinator) {
        self.coordinator = coordinator
    }

    public func setFrozen(_ isFrozen: Bool) {
        self.isFrozen = isFrozen
        if isFrozen {
            leftExitGraceTask?.cancel()
            leftExitGraceTask = nil
            rightExitGraceTask?.cancel()
            rightExitGraceTask = nil
            cancelInitialDwell()
            dwellTracker.reset()
            pushAccumulator.reset()
            wasAtAbsoluteBezel = false
            bezelArrivalTime = nil
        }
    }

    public func cancelInitialDwell() {
        initialDwellTask?.cancel()
        initialDwellTask = nil
        currentDwellCandidatePodId = nil
        currentDwellEdge = nil
    }

    public func resetEdgeState() {
        cancelInitialDwell()
        leftExitGraceTask?.cancel()
        leftExitGraceTask = nil
        rightExitGraceTask?.cancel()
        rightExitGraceTask = nil
        dwellTracker.reset()
        pushAccumulator.reset()
        wasAtAbsoluteBezel = false
        bezelArrivalTime = nil
        lastCandidatePodId = nil
        candidateHoverStartTime = nil
    }

    public func start() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .scrollWheel]) { [weak self] event in
            self?.handleMouse(event: event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .scrollWheel]) { [weak self] event in
            self?.handleMouse(event: event)
            return event
        }
        setupEventTap()
    }

    public func stop() {
        leftExitGraceTask?.cancel()
        leftExitGraceTask = nil
        rightExitGraceTask?.cancel()
        rightExitGraceTask = nil
        cancelInitialDwell()
        pushAccumulator.reset()
        tearDownEventTap()
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    private func setupEventTap() {
        tearDownEventTap()
        let eventMask = (1 << CGEventType.mouseMoved.rawValue) | (1 << CGEventType.leftMouseDragged.rawValue)
        let observer = Unmanaged.passUnretained(self).toOpaque()

        let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<EdgeMouseMonitor>.fromOpaque(refcon).takeUnretainedValue()
                let dx = event.getDoubleValueField(.mouseEventDeltaX)
                let pt = event.location

                if Thread.isMainThread {
                    MainActor.assumeIsolated {
                        monitor.handleHardwareRawMotion(point: pt, rawDeltaX: dx)
                    }
                } else {
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            monitor.handleHardwareRawMotion(point: pt, rawDeltaX: dx)
                        }
                    }
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: observer
        )

        if let tap = tap {
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            self.eventTap = tap
            self.runLoopSource = source
        }
    }

    private func tearDownEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
                self.runLoopSource = nil
            }
            CFMachPortInvalidate(tap)
            self.eventTap = nil
        }
    }

    public func handleHardwareRawMotion(point: CGPoint? = nil, rawDeltaX: Double, now: Date = Date()) {
        guard !isFrozen, !store.isRailsFrozen else { return }
        guard store.edgeTriggerMode == .pushForce else { return }
        guard store.activeDrawerPodId == nil && store.activeDrawerItemId == nil else { return }

        // Use canonical AppKit coordinates where (0, 0) is at bottom-left, perfectly matching visibleRect!
        let mousePoint = customCurrentMouseLocation ?? NSEvent.mouseLocation
        let screen = coordinator?.targetScreen(for: mousePoint) ?? NSScreen.main ?? NSScreen.screens.first
        let visibleRect = customTargetVisibleRect ?? screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let isInVerticalBounds = (mousePoint.y >= visibleRect.minY && mousePoint.y <= visibleRect.maxY)
        guard isInVerticalBounds else { return }

        let triggerW = CGFloat(store.railBarWidth) + 4.0
        let isAtLeftEdge = (mousePoint.x <= (visibleRect.minX + triggerW))
        let isAtRightEdge = (mousePoint.x >= (visibleRect.maxX - triggerW))
        guard isAtLeftEdge || isAtRightEdge else { return }

        let edge: MountEdge = isAtLeftEdge ? .left : .right
        let outwardDelta = (edge == .left) ? -rawDeltaX : rawDeltaX

        // Accumulate raw motion deltas only when cursor rests against physical bezel (<= 1.5pt) and pushes outward
        let isAtAbsoluteBezel = (edge == .left) ? (mousePoint.x <= visibleRect.minX + 1.5) : (mousePoint.x >= visibleRect.maxX - 1.5)
        guard isAtAbsoluteBezel else {
            wasAtAbsoluteBezel = false
            bezelArrivalTime = nil
            pushAccumulator.reset()
            return
        }

        guard let arrivalTime = bezelArrivalTime else {
            bezelArrivalTime = now
            wasAtAbsoluteBezel = true
            pushAccumulator.reset()
            return
        }

        // Settle gate (50ms):
        // Inflight approach motion during the first 50ms upon arriving at bezel is inertia, not deliberate push force
        guard now.timeIntervalSince(arrivalTime) >= 0.05 else {
            pushAccumulator.reset()
            return
        }

        let breakthrough = pushAccumulator.push(
            outwardDelta: outwardDelta,
            timestamp: now,
            threshold: store.activePushResistanceBarrier
        )

        if breakthrough {
            let currentWindowY = visibleRect.maxY - mousePoint.y
            let layoutItems = store.resolvedPhysicalLayout(for: edge, totalHeight: Double(visibleRect.height))
            let matchedItem = layoutItems.first { item in
                let topY = CGFloat(item.startY)
                let bottomY = topY + CGFloat(item.spanH)
                return currentWindowY >= (topY - 3.0) && currentWindowY <= (bottomY + 3.0)
            }
            if let matched = matchedItem {
                cancelInitialDwell()
                activatePodDrawer(candidate: matched.pod, matched: matched, currentWindowY: currentWindowY, edge: edge)
            }
        }
    }

    private func handleMouse(event: NSEvent) {
        processMouse(point: NSEvent.mouseLocation, event: event, now: Date())
    }

    public func processMouse(
        point: NSPoint,
        event: NSEvent? = nil,
        now: Date = Date(),
        customVelocity: CGPoint? = nil
    ) {
        guard !isFrozen, !store.isRailsFrozen else { return }

        if customVelocity == nil {
            velocityTracker.add(point: point, timestamp: now)
        }
        let vel = customVelocity ?? velocityTracker.currentVelocity()
        let speed = sqrt(vel.x * vel.x + vel.y * vel.y)

        coordinator?.updateActiveScreenIfNeeded(for: point)
        let screen = coordinator?.targetScreen(for: point) ?? NSScreen.main ?? NSScreen.screens.first
        let visibleRect = customTargetVisibleRect ?? screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let isInVerticalBounds = (point.y >= visibleRect.minY && point.y <= visibleRect.maxY)
        let triggerW = CGFloat(store.railBarWidth) + 4.0
        let isAtLeftEdge = isInVerticalBounds && (point.x <= (visibleRect.minX + triggerW))
        let isAtRightEdge = isInVerticalBounds && (point.x >= (visibleRect.maxX - triggerW))

        // Check 2D bounding boxes for drawers on left and right independently
        let isInsideLeftDrawer = isPointInsideAnyDrawerCard(point: point, visibleRect: visibleRect, edge: .left)
        let isInsideRightDrawer = isPointInsideAnyDrawerCard(point: point, visibleRect: visibleRect, edge: .right)

        let shouldBeInteractiveLeft = isAtLeftEdge || isInsideLeftDrawer
        let shouldBeInteractiveRight = isAtRightEdge || isInsideRightDrawer

        let activeIdLeft = store.activeDrawerItemId ?? store.activeDrawerPodId
        let isLeftActiveUnpinned = (store.activePod?.edge == .left) && (activeIdLeft != nil && !store.isItemPinned(id: activeIdLeft!))

        let activeIdRight = store.activeDrawerItemId ?? store.activeDrawerPodId
        let isRightActiveUnpinned = (store.activePod?.edge == .right) && (activeIdRight != nil && !store.isItemPinned(id: activeIdRight!))

        // 1. Manage Left Rail independence
        if shouldBeInteractiveLeft {
            leftExitGraceTask?.cancel()
            leftExitGraceTask = nil
            coordinator?.setInteractive(true, for: .left)
        } else if isLeftActiveUnpinned {
            if leftExitGraceTask == nil {
                leftExitGraceTask = Task { @MainActor [weak self] in
                    defer { self?.leftExitGraceTask = nil }
                    let graceSec = self?.store.activeExitGraceSeconds ?? 0.28
                    try? await Task.sleep(for: .seconds(graceSec))
                    guard !Task.isCancelled, let self = self else { return }
                    self.coordinator?.dismissDrawer(for: .left)
                }
            }
        } else {
            leftExitGraceTask?.cancel()
            leftExitGraceTask = nil
            coordinator?.setInteractive(false, for: .left)
        }

        // 2. Manage Right Rail independence
        if shouldBeInteractiveRight {
            rightExitGraceTask?.cancel()
            rightExitGraceTask = nil
            coordinator?.setInteractive(true, for: .right)
        } else if isRightActiveUnpinned {
            if rightExitGraceTask == nil {
                rightExitGraceTask = Task { @MainActor [weak self] in
                    defer { self?.rightExitGraceTask = nil }
                    let graceSec = self?.store.activeExitGraceSeconds ?? 0.28
                    try? await Task.sleep(for: .seconds(graceSec))
                    guard !Task.isCancelled, let self = self else { return }
                    self.coordinator?.dismissDrawer(for: .right)
                }
            }
        } else {
            rightExitGraceTask?.cancel()
            rightExitGraceTask = nil
            coordinator?.setInteractive(false, for: .right)
        }

        // If mouse is neither on a rail nor inside an active/pinned drawer card on either side
        if !shouldBeInteractiveLeft && !shouldBeInteractiveRight {
            dwellTracker.reset()
            pushAccumulator.reset()
            wasAtAbsoluteBezel = false
            bezelArrivalTime = nil
            cancelInitialDwell()
            store.hoveredPodId = nil
            lastCandidatePodId = nil
            candidateHoverStartTime = nil
            return
        }

        // Only trigger drawer expansion when physically on the trigger edge
        guard isAtLeftEdge || isAtRightEdge else {
            wasAtAbsoluteBezel = false
            bezelArrivalTime = nil
            pushAccumulator.reset()
            cancelInitialDwell()
            return
        }

        let edge: MountEdge = isAtLeftEdge ? .left : .right
        let isSeam = (screen != nil) ? Self.isSeam(edge: edge, on: screen!, point: point) : false
        // Multi-monitor inter-screen seam suppression: pass-through swipes across monitors (>220 px/s) are ignored
        if isSeam && speed >= 220.0 {
            cancelInitialDwell()
            return
        }

        let currentWindowY = visibleRect.maxY - point.y
        let layoutItems = store.resolvedPhysicalLayout(for: edge, totalHeight: Double(visibleRect.height))
        let matchedItem = layoutItems.first { item in
            let topY = CGFloat(item.startY)
            let bottomY = topY + CGFloat(item.spanH)
            return currentWindowY >= (topY - 3.0) && currentWindowY <= (bottomY + 3.0)
        }

        guard let matched = matchedItem else {
            cancelInitialDwell()
            store.hoveredPodId = nil
            return
        }
        let candidate = matched.pod
        store.hoveredPodId = candidate.id

        // Hover dwell hysteresis: when moving between pods, require deliberate intent
        if candidate.id != lastCandidatePodId {
            cancelInitialDwell()
            lastCandidatePodId = candidate.id
            candidateHoverStartTime = now
        }

        let hoverDuration = now.timeIntervalSince(candidateHoverStartTime ?? now)

        let isFromDockedState = (store.activeDrawerPodId == nil && store.activeDrawerItemId == nil)
        let isAtAbsoluteBezel = (edge == .left) ? (point.x <= visibleRect.minX + 1.5) : (point.x >= visibleRect.maxX - 1.5)

        // 1. Calculate Edge Push Force (Barrier / Input Leap model)
        // Core rules:
        // 1. Before cursor reaches physical border (<= 1.5pt), accumulator stays reset
        // 2. Post-arrival settle gate (50ms): inflight approach inertia is discarded
        // 3. Only sustained pushing after settling accumulates force
        let isPushForceBreakthrough: Bool
        if isAtAbsoluteBezel {
            if let arrivalTime = bezelArrivalTime {
                if now.timeIntervalSince(arrivalTime) >= 0.05 {
                    let outwardDelta: Double
                    if let ev = event {
                        let rawDeltaX = Double(ev.deltaX)
                        outwardDelta = (edge == .left) ? -rawDeltaX : rawDeltaX
                    } else if let customVel = customVelocity {
                        let simDeltaX = Double(customVel.x) * 0.016
                        outwardDelta = (edge == .left) ? -simDeltaX : simDeltaX
                    } else {
                        let velX = Double(vel.x) * 0.016
                        outwardDelta = (edge == .left) ? -velX : velX
                    }

                    let isAccumulatorBreakthrough = pushAccumulator.push(
                        outwardDelta: outwardDelta,
                        timestamp: now,
                        threshold: store.activePushResistanceBarrier
                    )
                    isPushForceBreakthrough = !isSeam && isAccumulatorBreakthrough
                } else {
                    pushAccumulator.reset()
                    isPushForceBreakthrough = false
                }
            } else {
                bezelArrivalTime = now
                wasAtAbsoluteBezel = true
                pushAccumulator.reset()
                isPushForceBreakthrough = false
            }
        } else {
            wasAtAbsoluteBezel = false
            bezelArrivalTime = nil
            pushAccumulator.reset()
            isPushForceBreakthrough = false
        }

        // Apply Mutual-Exclusion between Push Force and Hover Dwell
        if isFromDockedState {
            switch store.edgeTriggerMode {
            case .pushForce:
                // Mode 1: Push force breakthrough trigger (0ms instant trigger upon overcoming barrier)
                if isPushForceBreakthrough {
                    cancelInitialDwell()
                    activatePodDrawer(candidate: candidate, matched: matched, currentWindowY: currentWindowY, edge: edge)
                }
                return

            case .hoverDwell:
                // Agile mode: 0ms instant trigger on hover
                if store.edgeTriggerSensitivity == .agile {
                    cancelInitialDwell()
                    activatePodDrawer(candidate: candidate, matched: matched, currentWindowY: currentWindowY, edge: edge)
                    return
                }

                // Mode 2: Hover dwell gate trigger (strictly adheres to configured dwell duration)
                let requiredDwell = store.activeInitialDwellSeconds

                // If hover duration already satisfies dwell requirement, trigger immediately
                if hoverDuration >= requiredDwell {
                    cancelInitialDwell()
                    activatePodDrawer(candidate: candidate, matched: matched, currentWindowY: currentWindowY, edge: edge)
                    return
                }

                // Launch asynchronous dwell timer to capture stationary hover
                if initialDwellTask == nil || currentDwellCandidatePodId != candidate.id {
                    cancelInitialDwell()
                    currentDwellCandidatePodId = candidate.id
                    currentDwellEdge = edge

                    let remainingDwell = max(requiredDwell - hoverDuration, 0.02)
                    let candidateId = candidate.id

                    initialDwellTask = Task { @MainActor [weak self] in
                        try? await Task.sleep(for: .seconds(remainingDwell))
                        guard !Task.isCancelled, let self = self else { return }
                        guard !self.isFrozen, !self.store.isRailsFrozen else { return }
                        guard self.store.activeDrawerPodId == nil && self.store.activeDrawerItemId == nil else { return }
                        guard self.store.edgeTriggerMode == .hoverDwell else { return }

                        // Re-verify that cursor still resides on edge and target pod
                        let currentPoint = self.customCurrentMouseLocation ?? NSEvent.mouseLocation
                        let curScreen = self.coordinator?.targetScreen(for: currentPoint) ?? NSScreen.main ?? NSScreen.screens.first
                        let curVisibleRect = self.customTargetVisibleRect ?? curScreen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

                        let triggerW = CGFloat(self.store.railBarWidth) + 8.0
                        let atLeft = currentPoint.x <= (curVisibleRect.minX + triggerW)
                        let atRight = currentPoint.x >= (curVisibleRect.maxX - triggerW)
                        guard (edge == .left && atLeft) || (edge == .right && atRight) else {
                            self.cancelInitialDwell()
                            return
                        }

                        let curWinY = curVisibleRect.maxY - currentPoint.y
                        let curLayout = self.store.resolvedPhysicalLayout(for: edge, totalHeight: Double(curVisibleRect.height))
                        let curMatched = curLayout.first(where: { item in
                            let topY = CGFloat(item.startY)
                            let bottomY = topY + CGFloat(item.spanH)
                            return curWinY >= (topY - 6.0) && curWinY <= (bottomY + 6.0)
                        })

                        guard let targetMatched = curMatched, targetMatched.pod.id == candidateId else {
                            self.cancelInitialDwell()
                            return
                        }

                        // Hover dwell requirement satisfied: trigger initial drawer expansion
                        self.activatePodDrawer(candidate: targetMatched.pod, matched: targetMatched, currentWindowY: curWinY, edge: edge)
                        self.initialDwellTask = nil
                        self.currentDwellCandidatePodId = nil
                        self.currentDwellEdge = nil
                    }
                }
            }
        } else {
            // Drawer already expanded: fast slide transition across pods along rail (40ms)
            guard hoverDuration >= 0.04 || store.activeDrawerPodId == candidate.id else { return }
            activatePodDrawer(candidate: candidate, matched: matched, currentWindowY: currentWindowY, edge: edge)
        }
    }

    public func activatePodDrawer(candidate: SlotPod, matched: ResolvedPodLayoutItem, currentWindowY: CGFloat, edge: MountEdge) {
        let spanH = max(CGFloat(matched.spanH), 0.001)
        let podRelativeY = min(max((currentWindowY - CGFloat(matched.startY)) / spanH, 0.0), 0.999)

        if let provider = store.capabilityProvider(for: candidate.id), provider.isDecomposed(store: store) {
            let subItemCount = max(provider.subItemCount(store: store), 1)
            let itemIdx = min(max(Int(podRelativeY * Double(subItemCount)), 0), subItemCount - 1)
            let subItemId = provider.subItemId(at: itemIdx, store: store) ?? candidate.id
            if store.activeDrawerItemId != subItemId {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
                    store.activeDrawerItemId = subItemId
                    store.activeDrawerPodId = candidate.id
                }
            }
        } else {
            if store.activeDrawerPodId != candidate.id {
                withAnimation(.spring(response: 0.30, dampingFraction: 0.80)) {
                    store.activeDrawerPodId = candidate.id
                    store.activeDrawerItemId = candidate.id
                }
            }
        }
        coordinator?.setInteractive(true, for: edge)
    }

    private func isPointInsideAnyDrawerCard(point: NSPoint, visibleRect: CGRect, edge: MountEdge) -> Bool {
        guard !store.isRailsFrozen else { return false }
        // Fast-path: If no drawer is active and no items are pinned on this edge, return false instantly without computing frames!
        let hasActive = (store.activePod?.edge == edge) && (store.activeDrawerPodId != nil || store.activeDrawerItemId != nil)
        let hasPinned = store.hasPinnedItem(on: edge)
        guard hasActive || hasPinned else { return false }

        let totalH = Double(visibleRect.height)
        let windowW = Double(AmbientRailWindow.maxCanvasWidth)
        let windowMinX = (edge == .right) ? (visibleRect.maxX - windowW) : visibleRect.minX
        let winX = point.x - windowMinX
        let winY = point.y - visibleRect.minY // AppKit coordinate inside window
        let winPoint = NSPoint(x: winX, y: winY)

        let cardFrames = store.activeDrawerCardFrames(for: edge, totalHeight: totalH, windowWidth: windowW)
        return cardFrames.contains(where: { $0.contains(winPoint) })
    }

    public enum SeamToleranceConstants {
        public static let seamGapThreshold: CGFloat = 20.0
        public static let viewportOverlapMargin: CGFloat = 15.0
    }

    /// Determines whether edge is an adjacent inter-screen seam in multi-display setups
    public static func isSeam(edge: MountEdge, on screen: NSScreen, point: NSPoint) -> Bool {
        let screens = NSScreen.screens
        guard screens.count > 1 else { return false }
        let currentFrame = screen.frame

        for other in screens where other != screen {
            let otherFrame = other.frame
            // Check vertical viewport overlap
            guard point.y >= otherFrame.minY - SeamToleranceConstants.viewportOverlapMargin &&
                  point.y <= otherFrame.maxY + SeamToleranceConstants.viewportOverlapMargin else { continue }

            if edge == .right {
                // Adjacent screen on right side (seam gap <= 20px)
                if abs(otherFrame.minX - currentFrame.maxX) <= SeamToleranceConstants.seamGapThreshold {
                    return true
                }
            } else {
                // Adjacent screen on left side (seam gap <= 20px)
                if abs(currentFrame.minX - otherFrame.maxX) <= SeamToleranceConstants.seamGapThreshold {
                    return true
                }
            }
        }
        return false
    }
}
