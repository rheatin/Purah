// Sources/PurahApp/Interaction/EdgeMouseMonitor.swift
import AppKit
import SwiftUI
import Foundation
import CoreGraphics
import PurahCore
import PurahUI

@MainActor
public final class EdgeMouseMonitor {
    private let store: PurahWorkspaceStore
    private weak var coordinator: ScreenEdgeCoordinator?
    private var velocityTracker = VelocityTracker()
    nonisolated(unsafe) internal var pushAccumulator = PushForceAccumulator()
    private let flingDetector = FlingIntentDetector()
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var keyDownMonitor: Any?
    private var globalKeyDownMonitor: Any?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var leftExitGraceTask: Task<Void, Never>?
    private var rightExitGraceTask: Task<Void, Never>?
    private var initialDwellTask: Task<Void, Never>?
    private var dwellTelemetryTask: Task<Void, Never>?
    private var portalHoverTask: Task<Void, Never>?
    private var activePortalDirection: Int?
    private var activePortalEdge: MountEdge?
    private var currentDwellCandidatePodId: String?
    private var currentDwellEdge: MountEdge?
    private var lastCandidatePodId: String?
    private var candidateHoverStartTime: Date?
    private var wasAtAbsoluteBezel: Bool = false
    private var bezelArrivalTime: Date? = nil
    private var isRunning: Bool = false
    public private(set) var isFrozen: Bool = false
    public static weak var shared: EdgeMouseMonitor?
    nonisolated(unsafe) internal static var cachedScreenHorizontalEdges: [(minX: CGFloat, maxX: CGFloat)] = []

    public static func updateCachedScreenEdges() {
        let screens = NSScreen.screens
        cachedScreenHorizontalEdges = screens.map { ($0.frame.minX, $0.frame.maxX) }
    }

    /// Test hooks to mock screen visible frame and mouse location in headless unit tests
    public var customTargetVisibleRect: CGRect?
    public var customCurrentMouseLocation: NSPoint?

    public static var isTestingEnvironment: Bool {
        NSClassFromString("XCTest") != nil ||
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
        ProcessInfo.processInfo.arguments.contains(where: { $0.contains("swiftpm-testing-helper") || $0.contains("xctest") })
    }

    private var effectiveEdgeTriggerWidth: CGFloat {
        max(CGFloat(store.railBarWidth), 4.0)
    }

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
            cancelPortalHover()
            pushAccumulator.reset()
            wasAtAbsoluteBezel = false
            bezelArrivalTime = nil
            tearDownEventTap()
        } else {
            updateEventTapState()
        }
    }

    public func cancelInitialDwell() {
        initialDwellTask?.cancel()
        initialDwellTask = nil
        dwellTelemetryTask?.cancel()
        dwellTelemetryTask = nil
        currentDwellCandidatePodId = nil
        currentDwellEdge = nil
    }

    public func cancelPortalHover() {
        portalHoverTask?.cancel()
        portalHoverTask = nil
        activePortalDirection = nil
        activePortalEdge = nil
    }

    public func resetEdgeState() {
        cancelInitialDwell()
        cancelPortalHover()
        leftExitGraceTask?.cancel()
        leftExitGraceTask = nil
        rightExitGraceTask?.cancel()
        rightExitGraceTask = nil
        pushAccumulator.reset()
        wasAtAbsoluteBezel = false
        bezelArrivalTime = nil
        lastCandidatePodId = nil
        candidateHoverStartTime = nil
    }

    public func start() {
        guard !Self.isTestingEnvironment else {
            isRunning = true
            return
        }
        stop()
        isRunning = true
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseUp, .scrollWheel]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            switch event.type {
            case .leftMouseDragged, .leftMouseUp:
                self?.handleDrag(event: event)
            default:
                self?.handleMouse(event: event)
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            switch event.type {
            case .leftMouseDragged, .leftMouseUp:
                self?.handleDrag(event: event)
            default:
                self?.handleMouse(event: event)
            }
            return event
        }
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            if event.keyCode == 53 && (self.store.activeDrawerPodId != nil || self.store.activeDrawerItemId != nil) {
                let responderType = NSApp.keyWindow?.firstResponder.map { String(describing: type(of: $0)) } ?? ""
                if !responderType.contains("Terminal") {
                    withAnimation(.spring(response: 0.20, dampingFraction: 0.92)) {
                        self.store.dismissActiveDrawer()
                    }
                    return nil
                }
            }
            return event
        }
        globalKeyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return }
            if event.keyCode == 53 && (self.store.activeDrawerPodId != nil || self.store.activeDrawerItemId != nil) {
                let responderType = NSApp.keyWindow?.firstResponder.map { String(describing: type(of: $0)) } ?? ""
                if !responderType.contains("Terminal") {
                    Task { @MainActor [weak self] in
                        withAnimation(.spring(response: 0.20, dampingFraction: 0.92)) {
                            self?.store.dismissActiveDrawer()
                        }
                    }
                }
            }
        }
        updateEventTapState()
    }

    /// Keeps the rail awake while a drag session passes over it.
    ///
    /// Inbound drags emit `leftMouseDragged` instead of `mouseMoved`, and the panel switched to
    /// click-through (`ignoresMouseEvents = true`) the moment the cursor left the rail to pick the
    /// file up. Without this the drop could never be delivered.
    ///
    /// The hit region is the drawer card's 2D bounding box (`isPointInsideAnyDrawerCard`) plus the
    /// rail band — **not** the narrow overshoot corridor, which only hugs the bezel and misses the
    /// card body where the drop targets actually live.
    ///
    /// This is not the hover trigger: it skips the dwell/push-force pipeline, and only expands the
    /// drawer of a pod that actually accepts the dragged payload.
    private func handleDrag(event: NSEvent) {
        autoreleasepool {
            guard !isFrozen, !store.isRailsFrozen, !store.isLiveRailEditingMode else { return }

            if event.type == .leftMouseUp {
                processMouse(point: NSEvent.mouseLocation, now: Date())
                return
            }
            let point = NSEvent.mouseLocation
            coordinator?.updateActiveScreenIfNeeded(for: point)
            let screen = coordinator?.targetScreen(for: point) ?? NSScreen.main ?? NSScreen.screens.first
            let visibleRect = customTargetVisibleRect ?? screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            guard point.y >= visibleRect.minY, point.y <= visibleRect.maxY else { return }
            let barW = max(CGFloat(store.railBarWidth), 4.0)
            let bandWidth = max(CGFloat(store.activeCatchCorridor), barW)

            // A drag session emits no `mouseMoved`, so `processMouse` never runs and the
            // exit-grace timer started by `mouseExited` (picking the payload up leaves the rail)
            // would retract an unpinned hover drawer before the payload ever reaches the card.
            // The drawer must survive the whole trip from the source to the rail, so this runs
            // regardless of where the cursor currently is; `leftMouseUp` restores the pipeline.
            if !store.isDraggingFromDrawer { keepOpenDrawersAliveDuringDrag() }

            let currentWindowY = visibleRect.maxY - point.y

            for edge in [MountEdge.left, .right] {
                let withinBand = (edge == .left)
                    ? point.x <= visibleRect.minX + bandWidth
                    : point.x >= visibleRect.maxX - bandWidth
                let insideCard = isPointInsideAnyDrawerCard(point: point, visibleRect: visibleRect, edge: edge)
                guard withinBand || insideCard else { continue }

                // While a drag is in flight the rail must accept drops even when nothing is pinned,
                // otherwise the rail band (and its plugin drop targets) is skipped by hit-testing.
                coordinator?.setInteractive(true, for: edge)

                if insideCard {
                    // A drag carries no mouseMoved events, so without this the exit-grace timer
                    // would retract the drawer mid-drag and the drop would be lost.
                    coordinator?.expandCanvas(for: edge)
                } else if withinBand {
                    // Dock-style affordance: hovering a drop-capable pod while carrying a payload
                    // opens its drawer, so the drop targets inside the card become reachable.
                    // Without this the payload can only land on the narrow rail bar itself.
                    expandDropCapablePodIfNeeded(
                        edge: edge,
                        currentWindowY: currentWindowY,
                        totalHeight: Double(visibleRect.height)
                    )
                }
            }
        }
    }

    /// Opens the drawer of the drop-capable pod under the cursor during a drag session.
    private func expandDropCapablePodIfNeeded(edge: MountEdge, currentWindowY: CGFloat, totalHeight: Double) {
        guard !store.isDraggingFromDrawer else { return }
        let layoutItems = store.resolvedPhysicalLayout(for: edge, totalHeight: totalHeight)
        guard let matched = layoutItems.first(where: { item in
            let topY = CGFloat(item.startY)
            return currentWindowY >= topY && currentWindowY <= topY + actualOccupiedHeight(for: item)
        }) else { return }
        // Only pods that actually accept payloads should pop open mid-drag; everything else
        // would open a card that then refuses the drop.
        guard let plugin = PluginRegistry.shared.plugin(for: matched.pod.id),
              !plugin.supportedDropTypes.isEmpty else { return }
        guard store.activeDrawerPodId != matched.pod.id else { return }

        activatePodDrawer(candidate: matched.pod, matched: matched, currentWindowY: currentWindowY, edge: edge)
        cancelExitGrace(for: edge)
    }

    private func cancelExitGrace(for edge: MountEdge) {
        if edge == .left {
            leftExitGraceTask?.cancel()
            leftExitGraceTask = nil
        } else {
            rightExitGraceTask?.cancel()
            rightExitGraceTask = nil
        }
    }

    /// Suspends exit-grace dismissal for every edge that currently shows a drawer or pinned card.
    ///
    /// Re-applied on every `leftMouseDragged`, so it holds for the whole drag; `leftMouseUp`
    /// runs `processMouse`, which restarts the grace timer naturally.
    private func keepOpenDrawersAliveDuringDrag() {
        let activeEdge = store.activePod?.edge
        for edge in [MountEdge.left, .right] {
            let hasActive = (activeEdge == edge) && (store.activeDrawerPodId != nil || store.activeDrawerItemId != nil)
            guard hasActive || store.hasPinnedItem(on: edge) else { continue }
            cancelExitGrace(for: edge)
        }
    }

    public func updateEventTapState() {
        guard isRunning, !Self.isTestingEnvironment else {
            tearDownEventTap()
            return
        }
        if !isFrozen && !store.isRailsFrozen && store.edgeTriggerMode == .pushForce {
            if eventTap == nil {
                setupEventTap()
            }
        } else {
            tearDownEventTap()
        }
    }

    public func stop() {
        isRunning = false
        leftExitGraceTask?.cancel()
        leftExitGraceTask = nil
        rightExitGraceTask?.cancel()
        rightExitGraceTask = nil
        cancelInitialDwell()
        cancelPortalHover()
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
        if let monitor = keyDownMonitor {
            NSEvent.removeMonitor(monitor)
            keyDownMonitor = nil
        }
        if let monitor = globalKeyDownMonitor {
            NSEvent.removeMonitor(monitor)
            globalKeyDownMonitor = nil
        }
    }

    deinit {
        MainActor.assumeIsolated {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: false)
                if let source = runLoopSource {
                    CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
                }
                CFMachPortInvalidate(tap)
            }
            if let monitor = globalMonitor {
                NSEvent.removeMonitor(monitor)
            }
            if let monitor = localMonitor {
                NSEvent.removeMonitor(monitor)
            }
            if let monitor = keyDownMonitor {
                NSEvent.removeMonitor(monitor)
            }
            if let monitor = globalKeyDownMonitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }

    private func setupEventTap() {
        guard !Self.isTestingEnvironment else { return }
        tearDownEventTap()
        Self.updateCachedScreenEdges()
        let eventMask = (1 << CGEventType.mouseMoved.rawValue) | (1 << CGEventType.leftMouseDragged.rawValue)
        let observer = Unmanaged.passUnretained(self).toOpaque()

        let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon, let sharedMonitor = EdgeMouseMonitor.shared else {
                    return Unmanaged.passUnretained(event)
                }
                let monitor = Unmanaged<EdgeMouseMonitor>.fromOpaque(refcon).takeUnretainedValue()
                guard monitor === sharedMonitor else {
                    return Unmanaged.passUnretained(event)
                }
                guard type == .mouseMoved || type == .leftMouseDragged else {
                    return Unmanaged.passUnretained(event)
                }
                let dx = event.getDoubleValueField(.mouseEventDeltaX)
                guard abs(dx) > 0.05 else { return Unmanaged.passUnretained(event) }
                let pt = event.location

                // Fast pre-filter: avoid hopping to MainActor for events in the middle of the screen
                let isNearBorder: Bool = {
                    let cached = EdgeMouseMonitor.cachedScreenHorizontalEdges
                    if !cached.isEmpty {
                        for border in cached {
                            if abs(pt.x - border.minX) <= 80.0 || abs(pt.x - border.maxX) <= 80.0 {
                                return true
                            }
                        }
                        return false
                    }
                    var displayCount: UInt32 = 0
                    if CGGetActiveDisplayList(0, nil, &displayCount) == .success && displayCount > 0 {
                        var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
                        if CGGetActiveDisplayList(displayCount, &displays, &displayCount) == .success {
                            for i in 0..<Int(displayCount) {
                                let bounds = CGDisplayBounds(displays[i])
                                if abs(pt.x - bounds.minX) <= 80.0 || abs(pt.x - bounds.maxX) <= 80.0 {
                                    return true
                                }
                            }
                            return false
                        }
                    }
                    return true
                }()

                if !isNearBorder && monitor.pushAccumulator.currentForce <= 0 {
                    return Unmanaged.passUnretained(event)
                }

                // The tap's run-loop source is installed on the *main* run loop
                // (see below), so this callback always runs on the main thread;
                // the hop-off is a defensive net, not a live code path.
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
        guard !isFrozen, !store.isRailsFrozen, (!store.isLiveRailEditingMode || store.isRehearsingBreathingInSculptor) else { return }
        guard store.edgeTriggerMode == .pushForce else { return }
        guard store.activeDrawerPodId == nil && store.activeDrawerItemId == nil else { return }

        // Use canonical AppKit coordinates where (0, 0) is at bottom-left, perfectly matching visibleRect!
        let mousePoint = customCurrentMouseLocation ?? NSEvent.mouseLocation
        let screen = coordinator?.targetScreen(for: mousePoint) ?? NSScreen.main ?? NSScreen.screens.first
        let visibleRect = customTargetVisibleRect ?? screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let isInVerticalBounds = (mousePoint.y >= visibleRect.minY && mousePoint.y <= visibleRect.maxY)
        guard isInVerticalBounds else { return }

        let triggerW = effectiveEdgeTriggerWidth
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

        if store.isGateTelemetryTrackingEnabled {
            if !breakthrough && pushAccumulator.currentForce > 0 && store.activeDrawerPodId == nil {
                store.onboardingGateState = .pushing
                store.onboardingGateTargetValue = Int(store.activePushResistanceBarrier)
                store.onboardingGateCurrentValue = Int(pushAccumulator.currentForce)
                store.onboardingGateProgress = min(pushAccumulator.currentForce / max(store.activePushResistanceBarrier, 1.0), 1.0)
            }
        }

        if breakthrough {
            let currentWindowY = visibleRect.maxY - mousePoint.y
            let layoutItems = store.resolvedPhysicalLayout(for: edge, totalHeight: Double(visibleRect.height))
            let matchedItem = layoutItems.first { item in
                let topY = CGFloat(item.startY)
                let bottomY = topY + actualOccupiedHeight(for: item)
                return currentWindowY >= topY && currentWindowY <= bottomY
            }
            if let matched = matchedItem {
                cancelInitialDwell()
                activatePodDrawer(candidate: matched.pod, matched: matched, currentWindowY: currentWindowY, edge: edge)
            }
        }
    }

    public func actualOccupiedHeight(for item: ResolvedPodLayoutItem) -> CGFloat {
        // The solver already resolved every chip, including the expanded card
        // that overhangs the pod. Hit the exact pixels that are drawn.
        if let last = item.chipSlots.last {
            return CGFloat(last.top + last.height - item.startY)
        }

        let isSharedMajorSubBar = (item.majorGroupId != nil && abs(item.drawerSpanH - item.spanH) > 1.0)
        let isDynamicAccordion = store.isBreathingActive(for: item.pod.edge)
        if !isSharedMajorSubBar,
           store.isPodDecomposed(item.pod.id),
           let provider = store.capabilityProvider(for: item.pod.id),
           provider.subItemCount(store: store) > 0 {
            let policy = provider.decomposedPolicy(store: store)
            let count = policy.visibleChipCount(in: item.spanH, isDynamicAccordion: isDynamicAccordion)
            let itemH = policy.chipHeight(in: item.spanH, chipCount: count, isDynamicAccordion: isDynamicAccordion)
            return CGFloat(count) * itemH + policy.spacing * CGFloat(max(count - 1, 0))
        }
        return CGFloat(item.spanH)
    }

    private func handleMouse(event: NSEvent) {
        autoreleasepool {
            processMouse(point: NSEvent.mouseLocation, event: event, now: Date())
        }
    }

    public func processMouse(
        point: NSPoint,
        event: NSEvent? = nil,
        now: Date = Date(),
        customVelocity: CGPoint? = nil
    ) {
        guard !isFrozen, !store.isRailsFrozen, (!store.isLiveRailEditingMode || store.isRehearsingBreathingInSculptor) else { return }

        if isRunning {
            if store.edgeTriggerMode == .pushForce {
                if eventTap == nil {
                    updateEventTapState()
                }
            } else if eventTap != nil {
                tearDownEventTap()
            }
        }

        if customVelocity == nil {
            velocityTracker.add(point: point, timestamp: now)
        }
        let vel = customVelocity ?? velocityTracker.currentVelocity()
        let speed = sqrt(vel.x * vel.x + vel.y * vel.y)

        coordinator?.updateActiveScreenIfNeeded(for: point)
        let screen = coordinator?.targetScreen(for: point) ?? NSScreen.main ?? NSScreen.screens.first
        let visibleRect = customTargetVisibleRect ?? screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let isInVerticalBounds = (point.y >= visibleRect.minY && point.y <= visibleRect.maxY)
        let nearEdge: MountEdge? = isInVerticalBounds
            ? ((point.x <= visibleRect.minX + 70.0) ? .left : ((point.x >= visibleRect.maxX - 70.0) ? .right : nil))
            : nil
        if let nearEdge, store.paginatedPods(for: nearEdge, totalHeight: Double(visibleRect.height)).count > 1 {
            let winY = visibleRect.maxY - point.y
            let isNearTop = (winY >= 0 && winY <= 110.0)
            let isNearBottom = (winY >= (visibleRect.height - 110.0) && winY <= visibleRect.height)
            withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                store.updatePagePortalProximity(edge: nearEdge, isNearTop: isNearTop, isNearBottom: isNearBottom)
            }
        } else {
            withAnimation(.spring(response: 0.20, dampingFraction: 0.90)) {
                store.updatePagePortalProximity(edge: nil, isNearTop: false, isNearBottom: false)
            }
        }

        let triggerW = effectiveEdgeTriggerWidth
        let isAtLeftEdge = isInVerticalBounds && (point.x <= (visibleRect.minX + triggerW))
        let isAtRightEdge = isInVerticalBounds && (point.x >= (visibleRect.maxX - triggerW))

        // Check 2D bounding boxes for drawers on left and right independently
        let isInsideLeftDrawer = isPointInsideAnyDrawerCard(point: point, visibleRect: visibleRect, edge: .left)
        let isInsideRightDrawer = isPointInsideAnyDrawerCard(point: point, visibleRect: visibleRect, edge: .right)

        let isDraggingFromDrawer = store.isDraggingFromDrawer
        let activeEdge = store.activePod?.edge

        let isDraggingActiveLeft = isDraggingFromDrawer && (activeEdge == .left || (activeEdge == nil && store.hasPinnedItem(on: .left)) || activeEdge == nil)
        let isDraggingActiveRight = isDraggingFromDrawer && (activeEdge == .right || (activeEdge == nil && store.hasPinnedItem(on: .right)) || activeEdge == nil)

        let shouldBeInteractiveLeft = isAtLeftEdge || isInsideLeftDrawer || isDraggingActiveLeft
        let shouldBeInteractiveRight = isAtRightEdge || isInsideRightDrawer || isDraggingActiveRight

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
            if !isLeftActiveUnpinned && !store.hasPinnedItem(on: .left) {
                coordinator?.collapseCanvas(for: .left)
            }
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
            if !isRightActiveUnpinned && !store.hasPinnedItem(on: .right) {
                coordinator?.collapseCanvas(for: .right)
            }
        }

        // If mouse is neither on a rail nor inside an active/pinned drawer card on either side
        if !shouldBeInteractiveLeft && !shouldBeInteractiveRight {
            pushAccumulator.reset()
            wasAtAbsoluteBezel = false
            bezelArrivalTime = nil
            cancelInitialDwell()
            cancelPortalHover()
            if store.hoveredPodId != nil {
                withAnimation(.spring(response: 0.30, dampingFraction: 0.80, blendDuration: 0.08)) {
                    store.hoveredPodId = nil
                    store.invalidateLayoutCache()
                }
            }
            if store.isGateTelemetryTrackingEnabled && store.activeDrawerPodId == nil {
                if store.onboardingGateState != .opened && store.onboardingGateState != .idle {
                    store.onboardingGateState = .idle
                    store.onboardingGateProgress = 0.0
                    store.onboardingGateCurrentValue = 0
                }
            }
            lastCandidatePodId = nil
            candidateHoverStartTime = nil
            return
        }

        // Suppress triggering new drawer expansions while dragging items from drawer
        guard !store.isDraggingFromDrawer else { return }

        // Only trigger drawer expansion when physically on the trigger edge
        guard isAtLeftEdge || isAtRightEdge else {
            wasAtAbsoluteBezel = false
            bezelArrivalTime = nil
            pushAccumulator.reset()
            cancelInitialDwell()
            cancelPortalHover()
            if store.isGateTelemetryTrackingEnabled && store.activeDrawerPodId == nil {
                if store.onboardingGateState != .opened && store.onboardingGateState != .idle {
                    store.onboardingGateState = .idle
                    store.onboardingGateProgress = 0.0
                    store.onboardingGateCurrentValue = 0
                }
            }
            return
        }

        let edge: MountEdge = isAtLeftEdge ? .left : .right
        let currentWindowY = visibleRect.maxY - point.y

        // Top & Bottom Page Portals when multiple pages exist (avoiding 20pt macOS Hot Corners)
        let pages = store.paginatedPods(for: edge, totalHeight: Double(visibleRect.height))
        if pages.count > 1 {
            let isTopPortal = (currentWindowY >= 20.0 && currentWindowY <= 44.0)
            let isBottomPortal = (currentWindowY >= (visibleRect.height - 44.0) && currentWindowY <= (visibleRect.height - 20.0))
            if isTopPortal || isBottomPortal {
                let delta = isTopPortal ? -1 : 1
                cancelInitialDwell()
                lastCandidatePodId = nil
                candidateHoverStartTime = nil
                if store.activeDrawerPodId != nil || store.activeDrawerItemId != nil || store.hoveredPodId != nil {
                    withAnimation(.spring(response: 0.20, dampingFraction: 0.92)) {
                        store.dismissActiveDrawer()
                    }
                }
                startPortalHoverIfNeeded(edge: edge, delta: delta)
                return
            } else {
                cancelPortalHover()
            }
        } else {
            cancelPortalHover()
        }

        let isSeam = (screen != nil) ? Self.isSeam(edge: edge, on: screen!, point: point) : false
        // Multi-monitor inter-screen seam suppression: pass-through swipes across monitors (>220 px/s) are ignored
        if isSeam && speed >= 220.0 {
            cancelInitialDwell()
            return
        }

        let isFromDockedState = (store.activeDrawerPodId == nil && store.activeDrawerItemId == nil)

        // Rapid vertical movement suppression strictly applies when waking from docked state (prevents accidental popups when reaching for window controls or menus)
        if isFromDockedState {
            let isVerticalFling = flingDetector.evaluate(
                point: CGPoint(x: (edge == .left) ? point.x - visibleRect.minX : visibleRect.maxX - point.x, y: point.y),
                velocity: CGPoint(x: vel.x, y: vel.y),
                edge: edge,
                edgeMargin: Double(triggerW)
            ) == .verticalFlingSuppressed

            if isVerticalFling || abs(vel.y) > 250.0 {
                cancelInitialDwell()
                if store.isGateTelemetryTrackingEnabled {
                    store.onboardingGateState = .suppressedFling
                    store.onboardingGateProgress = 0.0
                    store.onboardingGateCurrentValue = Int(abs(vel.y))
                }
                return
            }
        }

        let layoutItems = store.resolvedPhysicalLayout(for: edge, totalHeight: Double(visibleRect.height))
        let matchedItem = layoutItems.first { item in
            let topY = CGFloat(item.startY)
            let bottomY = topY + actualOccupiedHeight(for: item)
            return currentWindowY >= topY && currentWindowY <= bottomY
        }

        guard let matched = matchedItem else {
            cancelInitialDwell()
            if isFromDockedState && store.hoveredPodId != nil {
                withAnimation(.spring(response: 0.30, dampingFraction: 0.80, blendDuration: 0.08)) {
                    store.hoveredPodId = nil
                    store.invalidateLayoutCache()
                }
            }
            if store.isGateTelemetryTrackingEnabled && store.activeDrawerPodId == nil {
                if store.onboardingGateState != .opened && store.onboardingGateState != .idle {
                    store.onboardingGateState = .idle
                    store.onboardingGateProgress = 0.0
                    store.onboardingGateCurrentValue = 0
                }
            }
            return
        }
        let candidate = matched.pod
        if !isFromDockedState && store.hoveredPodId != candidate.id {
            withAnimation(.spring(response: 0.30, dampingFraction: 0.80, blendDuration: 0.08)) {
                store.hoveredPodId = candidate.id
                store.invalidateLayoutCache()
            }
        }

        // Hover dwell hysteresis: when moving between pods, require deliberate intent
        if candidate.id != lastCandidatePodId {
            cancelInitialDwell()
            lastCandidatePodId = candidate.id
            candidateHoverStartTime = now
        }

        let hoverDuration = now.timeIntervalSince(candidateHoverStartTime ?? now)
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
                    if store.isGateTelemetryTrackingEnabled {
                        if !isPushForceBreakthrough && pushAccumulator.currentForce > 0 && store.activeDrawerPodId == nil {
                            store.onboardingGateState = .pushing
                            store.onboardingGateTargetValue = Int(store.activePushResistanceBarrier)
                            store.onboardingGateCurrentValue = Int(pushAccumulator.currentForce)
                            store.onboardingGateProgress = min(pushAccumulator.currentForce / max(store.activePushResistanceBarrier, 1.0), 1.0)
                        }
                    }
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
                let requiredDwell: Double = {
                    if store.isGateTelemetryTrackingEnabled && store.edgeTriggerSensitivity == .cautious {
                        return 0.28
                    }
                    return store.activeInitialDwellSeconds
                }()

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

                    // Pre-expand canvas silently on arrival so window frame is already 580pt before drawer spring
                    coordinator?.expandCanvas(for: edge)

                    let remainingDwell = max(requiredDwell - hoverDuration, 0.02)
                    let candidateId = candidate.id

                    if store.isGateTelemetryTrackingEnabled {
                        let targetMs = max(Int(requiredDwell * 1000), 1)
                        store.onboardingGateState = .dwelling
                        store.onboardingGateTargetValue = targetMs
                        dwellTelemetryTask?.cancel()
                        let startTime = Date()
                        dwellTelemetryTask = Task { @MainActor [weak self] in
                            while !Task.isCancelled {
                                try? await Task.sleep(nanoseconds: 16_000_000)
                                guard !Task.isCancelled, let self = self else { break }
                                guard self.store.isGateTelemetryTrackingEnabled else { break }
                                guard self.store.onboardingGateState == .dwelling else { break }
                                let elapsed = Date().timeIntervalSince(startTime) + hoverDuration
                                let elapsedMs = Int(elapsed * 1000)
                                self.store.onboardingGateCurrentValue = min(elapsedMs, targetMs)
                                self.store.onboardingGateProgress = min(elapsed / requiredDwell, 1.0)
                            }
                        }
                    }

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

                        let triggerW = self.effectiveEdgeTriggerWidth
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
                            let bottomY = topY + self.actualOccupiedHeight(for: item)
                            return curWinY >= topY && curWinY <= bottomY
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
            // Drawer already expanded: instant slide transition across pods along rail (0ms latency)
            activatePodDrawer(candidate: candidate, matched: matched, currentWindowY: currentWindowY, edge: edge)
        }
    }

    private func startPortalHoverIfNeeded(edge: MountEdge, delta: Int) {
        if portalHoverTask != nil && activePortalEdge == edge && activePortalDirection == delta {
            return
        }
        cancelPortalHover()
        activePortalEdge = edge
        activePortalDirection = delta
        portalHoverTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(160))
            guard !Task.isCancelled, let self = self else { return }
            guard !self.isFrozen, !self.store.isRailsFrozen else { return }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                self.store.cycleRailPage(for: edge, delta: delta)
            }
            self.store.triggerControlHaptic(.alignment)

            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(650))
                guard !Task.isCancelled else { return }
                guard !self.isFrozen, !self.store.isRailsFrozen else { return }
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    self.store.cycleRailPage(for: edge, delta: delta)
                }
                self.store.triggerControlHaptic(.alignment)
            }
        }
    }

    public func activatePodDrawer(candidate: SlotPod, matched: ResolvedPodLayoutItem, currentWindowY: CGFloat, edge: MountEdge) {
        if store.isGateTelemetryTrackingEnabled {
            store.onboardingGateState = .opened
            store.onboardingGateProgress = 1.0
            store.onboardingGateCurrentValue = store.onboardingGateTargetValue
        }

        // Ensure window canvas is ready and interactive BEFORE triggering drawer spring animation
        coordinator?.expandCanvas(for: edge)
        coordinator?.setInteractive(true, for: edge)

        let wasDocked = (store.activeDrawerPodId == nil && store.activeDrawerItemId == nil)
        let isSharedMajorSubBar = (matched.majorGroupId != nil && abs(matched.drawerSpanH - matched.spanH) > 1.0)
        let isDynamicAccordion = store.isBreathingActive(for: edge)

        if !isSharedMajorSubBar,
           let provider = store.capabilityProvider(for: candidate.id),
           provider.isDecomposed(store: store),
           provider.subItemCount(store: store) > 0 {
            let policy = provider.decomposedPolicy(store: store)
            let rawCount = provider.subItemCount(store: store)
            let minChipH = policy.minChipHeight
            let maxChipH = policy.maxChipHeight
            let spacing = policy.spacing
            let maxAllowed = isDynamicAccordion
                ? max(policy.maxRailItems, 1)
                : max(min(Int((CGFloat(matched.spanH) + spacing) / (minChipH + spacing)), policy.maxRailItems), 1)
            let count = min(rawCount, maxAllowed)
            let safeCount = max(count, 1)
            let totalSpacing = spacing * CGFloat(safeCount - 1)
            let effectiveMinChipH: CGFloat = isDynamicAccordion ? 6.0 : minChipH
            let itemH = min(max((CGFloat(matched.spanH) - totalSpacing) / CGFloat(safeCount), effectiveMinChipH), maxChipH)
            let actualSpan = CGFloat(count) * itemH + spacing * CGFloat(max(count - 1, 0))

            let podY = currentWindowY - CGFloat(matched.startY)
            // Cursor is in empty space below the actual chips: do NOT trigger any chip!
            guard podY >= 0.0 && podY <= actualSpan else {
                if store.activeDrawerPodId == candidate.id && !store.isItemPinned(id: store.activeDrawerItemId ?? "") {
                    withAnimation(.spring(response: 0.20, dampingFraction: 0.92)) {
                        store.dismissActiveDrawer()
                    }
                }
                return
            }

            let itemPitch = itemH + spacing
            let rawIdx = Int(max(podY, 0.0) / itemPitch)
            guard rawIdx >= 0 && rawIdx < count else { return }
            let isSmartFoldSlot = (policy.overflowStrategy == .smartFold && rawCount > maxAllowed && maxAllowed >= 2 && rawIdx == count - 1)
            let subItemId = isSmartFoldSlot ? "\(candidate.id)_more_items" : (provider.subItemId(at: rawIdx, store: store) ?? candidate.id)

            if store.activeDrawerItemId != subItemId || store.activeDrawerPodId != candidate.id {
                store.activateDrawer(podId: candidate.id, itemId: subItemId)
                store.triggerEdgePopHaptic(isInitialOpen: wasDocked)
            }
        } else {
            if store.activeDrawerPodId != candidate.id {
                store.activateDrawer(podId: candidate.id)
                store.triggerEdgePopHaptic(isInitialOpen: wasDocked)
            }
        }
    }

    private func isPointInsideAnyDrawerCard(point: NSPoint, visibleRect: CGRect, edge: MountEdge) -> Bool {
        guard !store.isRailsFrozen else { return false }
        // Fast-path 1: If no drawer is active and no items are pinned on this edge, return false instantly without computing frames!
        let hasActive = (store.activePod?.edge == edge) && (store.activeDrawerPodId != nil || store.activeDrawerItemId != nil)
        let hasPinned = store.hasPinnedItem(on: edge)
        guard hasActive || hasPinned else { return false }

        if let previewFrame = store.activePreviewScreenFrame, previewFrame.contains(point) {
            return true
        }

        let windowW = Double(AmbientRailWindow.maxCanvasWidth)

        // Fast-path 2: Trivial horizontal rejection - if point is outside the maximum canvas boundary, return false instantly!
        if edge == .left && point.x > (visibleRect.minX + windowW) {
            return false
        }
        if edge == .right && point.x < (visibleRect.maxX - windowW) {
            return false
        }

        // Fast-path 3: Trivial vertical rejection - if point is outside visible rect with margin, return false instantly!
        if point.y < (visibleRect.minY - 20.0) || point.y > (visibleRect.maxY + 20.0) {
            return false
        }

        let totalH = Double(visibleRect.height)
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
