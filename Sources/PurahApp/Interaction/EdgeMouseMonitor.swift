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
        guard let screen = NSScreen.screens.first ?? NSScreen.main else { return }
        let point = NSEvent.mouseLocation
        let now = Date()
        velocityTracker.add(point: point, timestamp: now)

        let screenRect = screen.frame
        let hasActiveDrawer = (store.activeDrawerItemId != nil)
        let activeWidth: CGFloat = hasActiveDrawer ? 290 : 20

        let isNearLeft = point.x <= (screenRect.minX + activeWidth)
        let isNearRight = point.x >= (screenRect.maxX - activeWidth)

        // 如果用户鼠标已经离开了导轨与弹出抽屉区域
        if !isNearLeft && !isNearRight {
            dwellTracker.reset()
            store.hoveredPodId = nil

            // 离开焦点就自动收回（未手动 Pin 住的事项自动缩回）
            if store.activeDrawerItemId != nil {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.70)) {
                    store.activeDrawerItemId = nil
                }
            }
            return
        }

        let edge: MountEdge = isNearLeft ? .left : .right
        let normalizedY = 1.0 - ((point.y - screenRect.minY) / screenRect.height)

        let candidatePod = store.pods.first { pod in
            pod.edge == edge && pod.isEnabled && pod.range.contains(normalizedY)
        }

        store.hoveredPodId = candidatePod?.id
    }
}
