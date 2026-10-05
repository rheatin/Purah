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

    public init(store: PurahWorkspaceStore, coordinator: ScreenEdgeCoordinator? = nil) {
        self.store = store
        self.coordinator = coordinator
    }

    public func setCoordinator(_ coordinator: ScreenEdgeCoordinator) {
        self.coordinator = coordinator
    }

    public func start() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            self?.handleMouse(event: event)
        }
    }

    public func stop() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
    }

    private func handleMouse(event: NSEvent) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let point = NSEvent.mouseLocation
        let now = Date()
        velocityTracker.add(point: point, timestamp: now)

        let screenRect = screen.frame

        // Check if point is near the 14px trigger rail on either side
        let isAtLeftEdge = point.x <= (screenRect.minX + 14)
        let isAtRightEdge = point.x >= (screenRect.maxX - 14)

        // Check 2D bounding boxes for drawers on left and right
        let isInsideLeftDrawer = isPointInsideAnyDrawerCard(point: point, screenRect: screenRect, edge: .left)
        let isInsideRightDrawer = isPointInsideAnyDrawerCard(point: point, screenRect: screenRect, edge: .right)

        let shouldBeInteractiveLeft = isAtLeftEdge || isInsideLeftDrawer
        let shouldBeInteractiveRight = isAtRightEdge || isInsideRightDrawer

        coordinator?.setInteractive(shouldBeInteractiveLeft, for: .left)
        coordinator?.setInteractive(shouldBeInteractiveRight, for: .right)

        // If mouse is neither on a rail nor inside an active/pinned drawer card:
        if !shouldBeInteractiveLeft && !shouldBeInteractiveRight {
            dwellTracker.reset()
            store.hoveredPodId = nil

            let activeId = store.activeDrawerItemId ?? store.activeDrawerPodId
            if let active = activeId, !store.isItemPinned(id: active) {
                coordinator?.dismissDrawer()
            }
            return
        }

        // Only trigger drawer expansion when physically on the 14px edge
        guard isAtLeftEdge || isAtRightEdge else { return }

        let edge: MountEdge = isAtLeftEdge ? .left : .right
        let normalizedY = 1.0 - ((point.y - screenRect.minY) / screenRect.height)

        let candidatePod = store.pods.first { pod in
            pod.edge == edge && pod.isEnabled && pod.range.contains(normalizedY)
        }

        store.hoveredPodId = candidatePod?.id

        if let candidate = candidatePod {
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
    }

    private func isPointInsideAnyDrawerCard(point: NSPoint, screenRect: CGRect, edge: MountEdge) -> Bool {
        let totalH = screenRect.height

        for pod in store.pods where pod.edge == edge && pod.isEnabled {
            let isPodPinned = store.isItemPinned(id: pod.id)
            let isPodActive = (store.activeDrawerItemId == pod.id || store.activeDrawerPodId == pod.id)
            let hasActiveOrPinnedChild = (pod.id == "todo" && store.todos.contains { store.isItemPinned(id: $0.id) || $0.id == store.activeDrawerItemId }) ||
                                         (pod.id == "calendar" && store.calendarEvents.contains { store.isItemPinned(id: $0.id) || $0.id == store.activeDrawerItemId })

            if isPodPinned || isPodActive || hasActiveOrPinnedChild {
                let topOfPodY = screenRect.maxY - (pod.range.start * totalH)
                let bottomOfPodY = screenRect.maxY - ((pod.range.start + pod.range.length) * totalH)

                let minY = bottomOfPodY - 6.0
                let maxY = topOfPodY + 6.0

                let drawerW = store.effectiveDrawerWidth(baseWidth: pod.drawerWidth) + 8.0
                let inDrawerX: Bool
                if edge == .right {
                    inDrawerX = point.x >= (screenRect.maxX - drawerW)
                } else {
                    inDrawerX = point.x <= (screenRect.minX + drawerW)
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
