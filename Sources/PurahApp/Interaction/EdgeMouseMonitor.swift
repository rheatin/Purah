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
    private let velocityTracker = VelocityTracker()
    private let flingDetector = FlingIntentDetector()
    private let dwellTracker = DwellTracker(threshold: 0.16)
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
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let point = NSEvent.mouseLocation
        let now = Date()
        velocityTracker.add(point: point, timestamp: now)

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
                    try? await Task.sleep(nanoseconds: 150_000_000)
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
                    try? await Task.sleep(nanoseconds: 150_000_000)
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
        let normalizedY = 1.0 - ((point.y - visibleRect.minY) / visibleRect.height)

        let candidatePod = store.pods.first { pod in
            pod.edge == edge && pod.isEnabled && pod.range.contains(normalizedY)
        }

        store.hoveredPodId = candidatePod?.id

        guard let candidate = candidatePod else { return }

        // Hover dwell hysteresis: when moving between pods, require deliberate intent
        if candidate.id != lastCandidatePodId {
            lastCandidatePodId = candidate.id
            candidateHoverStartTime = now
        }

        let hoverDuration = now.timeIntervalSince(candidateHoverStartTime ?? now)
        // Instant trigger on slow movement (<300 px/s), or after 80ms dwell on normal movement
        guard hoverDuration >= 0.08 || speed < 300.0 || store.activeDrawerPodId == candidate.id else { return }

        if candidate.id == "todo" && !store.todos.isEmpty {
            let count = max(store.todos.count, 1)
            let podRelativeY = min(max((normalizedY - candidate.range.start) / candidate.range.length, 0.0), 0.999)
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
            let podRelativeY = min(max((normalizedY - candidate.range.start) / candidate.range.length, 0.0), 0.999)
            let itemIdx = min(max(Int(podRelativeY * Double(count)), 0), count - 1)
            let item = store.calendarEvents[itemIdx]
            if store.activeDrawerItemId != item.id {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
                    store.activeDrawerItemId = item.id
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

        for pod in store.pods where pod.edge == edge && pod.isEnabled {
            let isPodPinned = store.isItemPinned(id: pod.id)
            let isPodActive = (store.activeDrawerItemId == pod.id || store.activeDrawerPodId == pod.id)
            let hasActiveOrPinnedChild = (pod.id == "todo" && store.todos.contains { store.isItemPinned(id: $0.id) || $0.id == store.activeDrawerItemId }) ||
                                         (pod.id == "calendar" && store.calendarEvents.contains { store.isItemPinned(id: $0.id) || $0.id == store.activeDrawerItemId })

            if isPodPinned || isPodActive || hasActiveOrPinnedChild {
                // Physical Co-Planar Rule: drawer card height matches rail bar height exactly
                let physicalCardH = max(pod.range.length * totalH, 36.0)
                let topOfPodY = visibleRect.maxY - (pod.range.start * totalH)
                let bottomOfPodY = topOfPodY - physicalCardH

                let minY = bottomOfPodY - 4.0
                let maxY = topOfPodY + 4.0

                let drawerW = store.effectiveDrawerWidth(baseWidth: pod.drawerWidth) + 8.0
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
}
