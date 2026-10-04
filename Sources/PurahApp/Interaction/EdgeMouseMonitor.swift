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
        let isDrawerOpen = (store.activeDrawerItemId != nil || store.activeDrawerPodId != nil || store.isDrawerPinned || !store.pinnedDrawerItemIds.isEmpty)
        let activeWidth: CGFloat = isDrawerOpen ? 340 : 16

        let isNearLeft = point.x <= (screenRect.minX + activeWidth)
        let isNearRight = point.x >= (screenRect.maxX - activeWidth)

        // 如果用户鼠标已经离开了导轨与弹出抽屉区域
        if !isNearLeft && !isNearRight {
            dwellTracker.reset()
            store.hoveredPodId = nil

            // 离开焦点就自动收回（未手动 Pin 住的事项自动缩回并彻底释放屏幕区域）
            if (store.activeDrawerItemId != nil || store.activeDrawerPodId != nil) && !store.isDrawerPinned && store.pinnedDrawerItemIds.isEmpty {
                coordinator?.dismissDrawer()
            } else {
                coordinator?.setInteractive(false, for: .left)
                coordinator?.setInteractive(false, for: .right)
            }
            return
        }

        // 仅在鼠标靠近边缘 14px 导轨时进行单项槽位命中计算与快速唤起
        let isAtEdge = point.x <= (screenRect.minX + 14) || point.x >= (screenRect.maxX - 14)
        if isAtEdge {
            let edge: MountEdge = point.x <= (screenRect.minX + 14) ? .left : .right
            coordinator?.setInteractive(true, for: edge)
        } else if isDrawerOpen {
            let edge: MountEdge = isNearLeft ? .left : .right
            coordinator?.setInteractive(true, for: edge)
        }
        guard isAtEdge else { return }

        let edge: MountEdge = point.x <= (screenRect.minX + 14) ? .left : .right
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
}
