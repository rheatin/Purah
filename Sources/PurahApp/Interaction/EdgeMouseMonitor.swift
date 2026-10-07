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
    private let flingDetector = FlingIntentDetector()
    private var dwellTracker = DwellTracker(threshold: 0.16)
    private var globalMonitor: Any?
    private var leftExitGraceTask: Task<Void, Never>?
    private var rightExitGraceTask: Task<Void, Never>?
    private var lastCandidatePodId: String?
    private var candidateHoverStartTime: Date?
    public private(set) var isFrozen: Bool = false

    public init(store: PurahWorkspaceStore, coordinator: ScreenEdgeCoordinator? = nil) {
        self.store = store
        self.coordinator = coordinator
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
            dwellTracker.reset()
        }
    }

    public func start() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .scrollWheel]) { [weak self] event in
            self?.handleMouse(event: event)
        }
    }

    public func stop() {
        leftExitGraceTask?.cancel()
        leftExitGraceTask = nil
        rightExitGraceTask?.cancel()
        rightExitGraceTask = nil
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
    }

    private func handleMouse(event: NSEvent) {
        guard !isFrozen, !store.isRailsFrozen else { return }
        let point = NSEvent.mouseLocation
        let now = Date()
        velocityTracker.add(point: point, timestamp: now)

        coordinator?.updateActiveScreenIfNeeded(for: point)
        guard let screen = coordinator?.targetScreen(for: point) ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let visibleRect = screen.visibleFrame

        // Check if point is near the 14px trigger rail on either side
        let isAtLeftEdge = point.x <= (visibleRect.minX + 14)
        let isAtRightEdge = point.x >= (visibleRect.maxX - 14)

        // Check 2D bounding boxes for drawers on left and right independently
        let isInsideLeftDrawer = isPointInsideAnyDrawerCard(point: point, visibleRect: visibleRect, edge: .left)
        let isInsideRightDrawer = isPointInsideAnyDrawerCard(point: point, visibleRect: visibleRect, edge: .right)

        let shouldBeInteractiveLeft = isAtLeftEdge || isInsideLeftDrawer
        let shouldBeInteractiveRight = isAtRightEdge || isInsideRightDrawer

        // 1. Manage Left Rail independence
        if shouldBeInteractiveLeft {
            leftExitGraceTask?.cancel()
            leftExitGraceTask = nil
            coordinator?.setInteractive(true, for: .left)
        } else {
            if leftExitGraceTask == nil {
                leftExitGraceTask = Task { @MainActor [weak self] in
                    let graceSec = self?.store.activeExitGraceSeconds ?? 0.28
                    try? await Task.sleep(nanoseconds: UInt64(graceSec * 1_000_000_000))
                    guard !Task.isCancelled, let self = self else { return }
                    self.coordinator?.dismissDrawer(for: .left)
                    self.leftExitGraceTask = nil
                }
            }
        }

        // 2. Manage Right Rail independence
        if shouldBeInteractiveRight {
            rightExitGraceTask?.cancel()
            rightExitGraceTask = nil
            coordinator?.setInteractive(true, for: .right)
        } else {
            if rightExitGraceTask == nil {
                rightExitGraceTask = Task { @MainActor [weak self] in
                    let graceSec = self?.store.activeExitGraceSeconds ?? 0.28
                    try? await Task.sleep(nanoseconds: UInt64(graceSec * 1_000_000_000))
                    guard !Task.isCancelled, let self = self else { return }
                    self.coordinator?.dismissDrawer(for: .right)
                    self.rightExitGraceTask = nil
                }
            }
        }

        // If mouse is neither on a rail nor inside an active/pinned drawer card on either side
        if !shouldBeInteractiveLeft && !shouldBeInteractiveRight {
            dwellTracker.reset()
            store.hoveredPodId = nil
            lastCandidatePodId = nil
            candidateHoverStartTime = nil
            return
        }

        // Only trigger drawer expansion when physically on the 14px edge
        guard isAtLeftEdge || isAtRightEdge else { return }

        // Velocity speed check: suppress accidental popups on rapid fling across screen edge (>900 px/s)
        let vel = velocityTracker.currentVelocity()
        let speed = sqrt(vel.x * vel.x + vel.y * vel.y)
        guard speed < 900.0 else { return }

        let edge: MountEdge = isAtLeftEdge ? .left : .right
        let isSeam = Self.isSeam(edge: edge, on: screen, point: point)
        // Multi-monitor inter-screen seam suppression: pass-through swipes across monitors (>220 px/s) are ignored
        if isSeam && speed >= 220.0 { return }

        let currentWindowY = visibleRect.maxY - point.y
        let layoutItems = store.resolvedPhysicalLayout(for: edge, totalHeight: Double(visibleRect.height))
        let matchedItem = layoutItems.first { item in
            let topY = CGFloat(item.startY)
            let bottomY = topY + CGFloat(item.spanH)
            return currentWindowY >= topY && currentWindowY <= bottomY
        }
        guard let matched = matchedItem else {
            store.hoveredPodId = nil
            return
        }
        let candidate = matched.pod
        store.hoveredPodId = candidate.id

        // Hover dwell hysteresis: when moving between pods, require deliberate intent
        if candidate.id != lastCandidatePodId {
            lastCandidatePodId = candidate.id
            candidateHoverStartTime = now
        }

        let hoverDuration = now.timeIntervalSince(candidateHoverStartTime ?? now)

        // Two-Stage Intentionality Gate:
        // 1. When waking from completely docked state (activeDrawerPodId == nil):
        //    Require either deliberate hover dwell (>= initialDwellSeconds, default 150ms)
        //    OR firm physical edge push (distance <= 3px from bezel for >= deepEdgeDwellSeconds, default 60ms).
        // 2. When already active and browsing between pods/sub-items:
        //    Allow fast, fluid switching (>= 40ms or active candidate).
        let isFromDockedState = (store.activeDrawerPodId == nil && store.activeDrawerItemId == nil)
        let isDeepEdgePush = isAtLeftEdge ? (point.x <= visibleRect.minX + 3.0) : (point.x >= visibleRect.maxX - 3.0)

        let initialDwellReq = store.activeInitialDwellSeconds
        let deepEdgeDwellReq = store.activeDeepEdgeDwellSeconds

        if isFromDockedState {
            let qualifiesByDwell = (hoverDuration >= initialDwellReq)
            let qualifiesByPush = (isDeepEdgePush && hoverDuration >= deepEdgeDwellReq)
            guard qualifiesByDwell || qualifiesByPush else { return }
        } else {
            // Already active on rail: fast responsive switching between items
            guard hoverDuration >= 0.04 || store.activeDrawerPodId == candidate.id else { return }
        }

        let podRelativeY = min(max((currentWindowY - CGFloat(matched.startY)) / max(CGFloat(matched.spanH), 0.001), 0.0), 0.999)

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
    }

    private func isPointInsideAnyDrawerCard(point: NSPoint, visibleRect: CGRect, edge: MountEdge) -> Bool {
        let totalH = visibleRect.height
        let layoutItems = store.resolvedPhysicalLayout(for: edge, totalHeight: Double(totalH))

        for item in layoutItems {
            let pod = item.pod
            let isPodPinned = store.isItemPinned(id: pod.id)
            let isPodActive = (store.activeDrawerItemId == pod.id || store.activeDrawerPodId == pod.id)
            let hasActiveOrPinnedChild = (pod.id == "todo" && store.todos.contains { store.isItemPinned(id: $0.id) || $0.id == store.activeDrawerItemId }) ||
                                         (pod.id == "calendar" && store.calendarEvents.contains { store.isItemPinned(id: $0.id) || $0.id == store.activeDrawerItemId }) ||
                                         (pod.id == "vitals" && store.isVitalsDecomposed && store.vitalsEnabledMetrics.contains { store.isItemPinned(id: "vitals-\($0.rawValue)") || "vitals-\($0.rawValue)" == store.activeDrawerItemId }) ||
                                         (pod.id == "scripts" && store.isScriptsDecomposed && store.scriptsEnabledActions.contains { store.isItemPinned(id: "scripts-\($0.id)") || "scripts-\($0.id)" == store.activeDrawerItemId })

            if isPodPinned || isPodActive || hasActiveOrPinnedChild {
                let startY = CGFloat(item.startY)
                let spanH = CGFloat(item.spanH)

                // In AppKit coordinates (bottom is visibleRect.minY, top is visibleRect.maxY)
                let topOfPodY = visibleRect.maxY - startY
                let bottomOfPodY = topOfPodY - spanH

                let minY = max(bottomOfPodY - 18.0, visibleRect.minY)
                let maxY = min(topOfPodY + 18.0, visibleRect.maxY)

                let corridor = CGFloat(store.activeCatchCorridor)
                let drawerW = store.effectiveDrawerWidth(baseWidth: pod.drawerWidth) + corridor
                let inDrawerX: Bool
                if edge == .right {
                    inDrawerX = point.x >= (visibleRect.maxX - drawerW)
                } else {
                    inDrawerX = point.x <= (visibleRect.minX + drawerW)
                }
                let inDrawerY = (point.y >= minY && point.y <= maxY)

                if inDrawerX && inDrawerY {
                    return true
                }
            }
        }
        return false
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
