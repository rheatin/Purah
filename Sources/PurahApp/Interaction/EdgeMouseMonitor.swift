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
    private var exitGraceTask: Task<Void, Never>?
    private var lastCandidatePodId: String?
    private var candidateHoverStartTime: Date?

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
        exitGraceTask?.cancel()
        exitGraceTask = nil
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

        // If mouse is inside drawer or on rail: cancel exit grace window immediately
        if shouldBeInteractiveLeft || shouldBeInteractiveRight {
            exitGraceTask?.cancel()
            exitGraceTask = nil
            coordinator?.setInteractive(shouldBeInteractiveLeft, for: .left)
            coordinator?.setInteractive(shouldBeInteractiveRight, for: .right)
        } else {
            // Mouse is outside: start 150ms Exit Grace Window to prevent accidental collapse
            if exitGraceTask == nil {
                exitGraceTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 150_000_000) // 150ms grace delay
                    guard !Task.isCancelled else { return }
                    guard let self = self else { return }

                    self.dwellTracker.reset()
                    self.store.hoveredPodId = nil
                    self.lastCandidatePodId = nil
                    self.candidateHoverStartTime = nil

                    let activeId = self.store.activeDrawerItemId ?? self.store.activeDrawerPodId
                    if let active = activeId, !self.store.isItemPinned(id: active) {
                        self.coordinator?.dismissDrawer()
                    }
                    self.coordinator?.setInteractive(false, for: .left)
                    self.coordinator?.setInteractive(false, for: .right)
                    self.exitGraceTask = nil
                }
            }
            return
        }

        // Only trigger drawer expansion when physically on the 14px edge
        guard isAtLeftEdge || isAtRightEdge else { return }

        // Velocity speed check: suppress accidental popups on rapid fling across screen edge (>900 px/s)
        let vel = velocityTracker.currentVelocity()
        let speed = sqrt(vel.x * vel.x + vel.y * vel.y)
        guard speed < 900.0 else { return }

        let edge: MountEdge = isAtLeftEdge ? .left : .right
        let normalizedY = 1.0 - ((point.y - screenRect.minY) / screenRect.height)

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
