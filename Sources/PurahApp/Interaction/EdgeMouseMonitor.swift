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
        pushAccumulator.reset()
        wasAtAbsoluteBezel = false
        wasAtAbsoluteBezel = false
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
                Task { @MainActor in
                    monitor.handleHardwareRawMotion(point: pt, rawDeltaX: dx)
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

    public func handleHardwareRawMotion(point: CGPoint? = nil, rawDeltaX: Double) {
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

        // 仅在光标紧贴绝对边框 (<= 1.5pt) 且持续施加推力时进行硬件级位移累加
        let isAtAbsoluteBezel = (edge == .left) ? (mousePoint.x <= visibleRect.minX + 1.5) : (mousePoint.x >= visibleRect.maxX - 1.5)
        guard isAtAbsoluteBezel else {
            wasAtAbsoluteBezel = false
            pushAccumulator.reset()
            return
        }

        // 触边第一帧抑制：若刚触边，丢弃飞行位移
        guard wasAtAbsoluteBezel else {
            wasAtAbsoluteBezel = true
            pushAccumulator.reset()
            return
        }

        let breakthrough = pushAccumulator.push(
            outwardDelta: outwardDelta,
            timestamp: Date(),
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

        let isLeftDrawerOpen = (store.activePod?.edge == .left || store.hasPinnedItem(on: .left))
        let isRightDrawerOpen = (store.activePod?.edge == .right || store.hasPinnedItem(on: .right))

        // 1. Manage Left Rail independence
        if shouldBeInteractiveLeft {
            leftExitGraceTask?.cancel()
            leftExitGraceTask = nil
            coordinator?.setInteractive(true, for: .left)
        } else if isLeftDrawerOpen {
            if leftExitGraceTask == nil {
                leftExitGraceTask = Task { @MainActor [weak self] in
                    let graceSec = self?.store.activeExitGraceSeconds ?? 0.28
                    try? await Task.sleep(for: .seconds(graceSec))
                    guard !Task.isCancelled, let self = self else { return }
                    self.coordinator?.dismissDrawer(for: .left)
                    self.leftExitGraceTask = nil
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
        } else if isRightDrawerOpen {
            if rightExitGraceTask == nil {
                rightExitGraceTask = Task { @MainActor [weak self] in
                    let graceSec = self?.store.activeExitGraceSeconds ?? 0.28
                    try? await Task.sleep(for: .seconds(graceSec))
                    guard !Task.isCancelled, let self = self else { return }
                    self.coordinator?.dismissDrawer(for: .right)
                    self.rightExitGraceTask = nil
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
            cancelInitialDwell()
            store.hoveredPodId = nil
            lastCandidatePodId = nil
            candidateHoverStartTime = nil
            return
        }

        // Only trigger drawer expansion when physically on the trigger edge
        guard isAtLeftEdge || isAtRightEdge else {
            wasAtAbsoluteBezel = false
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

        // 1. Calculate Edge Push Force (Barrier / Input Leap / Loop 相对位移累加器模型)
        // 核心铁律：
        // 1. 光标未完全到达物理边框 (<= 1.5pt) 之前，严禁提前蓄力，累加器强制清零！
        // 2. 触边第一帧 (Arrival Frame) 携带的是空中的冲刺位移，必须彻底丢弃清零！
        // 3. 只有到达边缘停住后 (wasAtAbsoluteBezel == true)，后续继续推边产生的位移才计入推力！
        let isPushForceBreakthrough: Bool
        if isAtAbsoluteBezel {
            if wasAtAbsoluteBezel {
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
                // 触边到达第一帧：丢弃空中位移，标记已到达，累加器清零，绝对不弹！
                wasAtAbsoluteBezel = true
                pushAccumulator.reset()
                isPushForceBreakthrough = false
            }
        } else {
            wasAtAbsoluteBezel = false
            pushAccumulator.reset()
            isPushForceBreakthrough = false
        }

        // Velocity speed check: suppress wild vertical fling if not pushing inward
        if store.edgeTriggerMode == .hoverDwell {
            guard speed < 900.0 else {
                cancelInitialDwell()
                return
            }
        } else {
            if !isPushForceBreakthrough {
                guard speed < 900.0 else {
                    cancelInitialDwell()
                    return
                }
            }
        }

        if isFromDockedState {
            switch store.edgeTriggerMode {
            case .pushForce:
                // 模式 1：仅推力突破触发 (0ms 瞬间破门，无悬停等待)
                if isPushForceBreakthrough {
                    cancelInitialDwell()
                    activatePodDrawer(candidate: candidate, matched: matched, currentWindowY: currentWindowY, edge: edge)
                }
                return

            case .hoverDwell:
                // 极速模式（agile）：0ms 一 hover 就有！
                if store.edgeTriggerSensitivity == .agile {
                    cancelInitialDwell()
                    activatePodDrawer(candidate: candidate, matched: matched, currentWindowY: currentWindowY, edge: edge)
                    return
                }

                // 模式 2：仅悬停驻留门禁触发 (严格遵循用户设定的驻留时长，避免划过误弹)
                let requiredDwell = store.activeInitialDwellSeconds

                // 若同步事件已达到驻留时长，立即触发
                if hoverDuration >= requiredDwell {
                    cancelInitialDwell()
                    activatePodDrawer(candidate: candidate, matched: matched, currentWindowY: currentWindowY, edge: edge)
                    return
                }

                // 启动异步驻留计时器 (捕获静止悬停)
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

                        // 重新校验当前鼠标位置是否仍停留在边缘及目标 Pod 上
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

                        // 悬停驻留达标：触发初次弹出！
                        self.activatePodDrawer(candidate: targetMatched.pod, matched: targetMatched, currentWindowY: curWinY, edge: edge)
                        self.initialDwellTask = nil
                        self.currentDwellCandidatePodId = nil
                        self.currentDwellEdge = nil
                    }
                }
            }
        } else {
            // 抽屉已处于展开态，沿轨快速滑动切换 (40ms 或已是当前 Pod)
            guard hoverDuration >= 0.04 || store.activeDrawerPodId == candidate.id else { return }
            activatePodDrawer(candidate: candidate, matched: matched, currentWindowY: currentWindowY, edge: edge)
        }
    }

    public func activatePodDrawer(candidate: SlotPod, matched: ResolvedPodLayoutItem, currentWindowY: CGFloat, edge: MountEdge) {
        let spanH = max(CGFloat(matched.spanH), 0.001)
        let podRelativeY = min(max((currentWindowY - CGFloat(matched.startY)) / spanH, 0.0), 0.999)

        if candidate.id == "todo" && !store.todos.isEmpty {
            let count = max(store.todos.count, 1)
            let itemIdx = min(max(Int(podRelativeY * Double(count)), 0), count - 1)
            let item = store.todos[itemIdx]
            if store.activeDrawerItemId != item.id {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
                    store.activeDrawerItemId = item.id
                    store.activeDrawerPodId = candidate.id
                }
            }
        } else if candidate.id == "calendar" && !store.calendarEvents.isEmpty {
            let count = max(store.calendarEvents.count, 1)
            let itemIdx = min(max(Int(podRelativeY * Double(count)), 0), count - 1)
            let item = store.calendarEvents[itemIdx]
            if store.activeDrawerItemId != item.id {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
                    store.activeDrawerItemId = item.id
                    store.activeDrawerPodId = candidate.id
                }
            }
        } else if candidate.id == "vitals" && store.isVitalsDecomposed && !store.vitalsEnabledMetrics.isEmpty {
            let count = max(store.vitalsEnabledMetrics.count, 1)
            let itemIdx = min(max(Int(podRelativeY * Double(count)), 0), count - 1)
            let metric = store.vitalsEnabledMetrics[itemIdx]
            let itemId = "vitals-\(metric.rawValue)"
            if store.activeDrawerItemId != itemId {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
                    store.activeDrawerItemId = itemId
                    store.activeDrawerPodId = candidate.id
                }
            }
        } else if candidate.id == "scripts" && store.isScriptsDecomposed && !store.scriptsEnabledActions.isEmpty {
            let count = max(store.scriptsEnabledActions.count, 1)
            let itemIdx = min(max(Int(podRelativeY * Double(count)), 0), count - 1)
            let action = store.scriptsEnabledActions[itemIdx]
            let itemId = "scripts-\(action.id)"
            if store.activeDrawerItemId != itemId {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
                    store.activeDrawerItemId = itemId
                    store.activeDrawerPodId = candidate.id
                }
            }
        } else {
            if store.activeDrawerPodId != candidate.id {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
                    store.activeDrawerPodId = candidate.id
                    store.activeDrawerItemId = candidate.id
                }
            }
        }
        coordinator?.setInteractive(true, for: edge)
    }

    private func isPointInsideAnyDrawerCard(point: NSPoint, visibleRect: CGRect, edge: MountEdge) -> Bool {
        guard !store.isRailsFrozen else { return false }
        let totalH = Double(visibleRect.height)
        let windowW = 340.0
        let windowMinX = (edge == .right) ? (visibleRect.maxX - windowW) : visibleRect.minX
        let winX = point.x - windowMinX
        let winY = point.y - visibleRect.minY // AppKit coordinate inside window
        let winPoint = NSPoint(x: winX, y: winY)

        let cardFrames = store.activeDrawerCardFrames(for: edge, totalHeight: totalH, windowWidth: windowW)
        return cardFrames.contains(where: { $0.contains(winPoint) })
    }

    /// 检测给定边缘是否与其他外接屏幕直接相邻拼接 (Inter-Screen Seam)
    public static func isSeam(edge: MountEdge, on screen: NSScreen, point: NSPoint) -> Bool {
        let screens = NSScreen.screens
        guard screens.count > 1 else { return false }
        let currentFrame = screen.frame

        for other in screens where other != screen {
            let otherFrame = other.frame
            // 垂直方向有视口重叠
            guard point.y >= otherFrame.minY - 15 && point.y <= otherFrame.maxY + 15 else { continue }

            if edge == .right {
                // 另一块显示器紧贴在当前显示器右侧 (左右拼接缝隙 <= 20px)
                if abs(otherFrame.minX - currentFrame.maxX) <= 20 {
                    return true
                }
            } else {
                // 另一块显示器紧贴在当前显示器左侧 (左右拼接缝隙 <= 20px)
                if abs(currentFrame.minX - otherFrame.maxX) <= 20 {
                    return true
                }
            }
        }
        return false
    }
}
