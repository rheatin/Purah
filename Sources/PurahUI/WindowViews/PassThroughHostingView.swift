// Sources/PurahUI/WindowViews/PassThroughHostingView.swift
import AppKit
import SwiftUI
import PurahCore

public final class PassThroughHostingView<Content: View>: NSHostingView<Content> {
    public let edge: MountEdge
    public let store: PurahWorkspaceStore
    private var trackingArea: NSTrackingArea?
    private var exitGraceTask: Task<Void, Never>?

    public init(rootView: Content, edge: MountEdge, store: PurahWorkspaceStore) {
        self.edge = edge
        self.store = store
        super.init(rootView: rootView)
    }

    public required init(rootView: Content) {
        self.edge = .right
        self.store = PurahWorkspaceStore()
        super.init(rootView: rootView)
    }

    @MainActor public required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        self.trackingArea = area
    }

    public func isPointInInteractiveDrawer(_ point: NSPoint) -> Bool {
        guard !store.isRailsFrozen else { return false }
        let totalH = bounds.height
        let layoutItems = store.resolvedPhysicalLayout(for: edge, totalHeight: Double(totalH))

        for item in layoutItems {
            let pod = item.pod
            let isPodPinned = store.isItemPinned(id: pod.id)
            let isPodActive = (store.activeDrawerItemId == pod.id || store.activeDrawerPodId == pod.id)

            let hasActiveOrPinnedChild = store.hasActiveOrPinnedChild(for: pod.id)

            if isPodPinned || isPodActive || hasActiveOrPinnedChild {
                let startY = CGFloat(item.startY)
                let spanH = CGFloat(item.spanH)

                // In AppKit coordinates (bottom is 0, top is totalH)
                let topOfPodY = totalH - startY
                let bottomOfPodY = topOfPodY - spanH
                let minY = max(bottomOfPodY - 18.0, 0.0)
                let maxY = min(topOfPodY + 18.0, totalH)

                let corridor = CGFloat(store.activeCatchCorridor)
                let drawerW = store.effectiveDrawerWidth(baseWidth: pod.drawerWidth) + corridor
                let inDrawerX: Bool
                if edge == .right {
                    inDrawerX = (point.x >= bounds.maxX - drawerW)
                } else {
                    inDrawerX = (point.x <= bounds.minX + drawerW)
                }
                let inDrawerY = (point.y >= minY && point.y <= maxY)
                if inDrawerX && inDrawerY {
                    return true
                }
            }
        }
        return false
    }

    public override func scrollWheel(with event: NSEvent) {
        guard !store.isRailsFrozen else {
            super.scrollWheel(with: event)
            return
        }
        let winPoint = event.locationInWindow
        if isPointInInteractiveDrawer(winPoint) {
            if let panel = self.window as? NSPanel {
                panel.ignoresMouseEvents = false
            }
        }
        super.scrollWheel(with: event)
    }

    public override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        guard !store.isRailsFrozen else { return }

        let winPoint = event.locationInWindow
        let barW: CGFloat = CGFloat(store.railBarWidth)
        let isOnRail = (edge == .right) ? (winPoint.x >= bounds.maxX - barW - 6) : (winPoint.x <= bounds.minX + barW + 6)

        if isOnRail || isPointInInteractiveDrawer(winPoint) {
            exitGraceTask?.cancel()
            exitGraceTask = nil
            if let panel = self.window as? NSPanel {
                panel.ignoresMouseEvents = false
                if !panel.isKeyWindow {
                    panel.makeKey()
                }
            }
            return
        }

        // When mouse steps outside, use dynamic Exit Grace Window before retracting
        if exitGraceTask == nil {
            exitGraceTask = Task { @MainActor [weak self] in
                let graceSec = self?.store.activeExitGraceSeconds ?? 0.28
                try? await Task.sleep(nanoseconds: UInt64(graceSec * 1_000_000_000))
                guard !Task.isCancelled else { return }
                guard let self = self else { return }

                if let panel = self.window as? NSPanel {
                    panel.ignoresMouseEvents = true
                }

                let activeId = self.store.activeDrawerItemId ?? self.store.activeDrawerPodId
                if let active = activeId {
                    let isCurrentActivePinned = self.store.isItemPinned(id: active)
                    if !isCurrentActivePinned {
                        withAnimation(.spring(response: 0.18, dampingFraction: 0.90)) {
                            self.store.activeDrawerItemId = nil
                            self.store.activeDrawerPodId = nil
                            self.store.hoveredPodId = nil
                        }
                    }
                }
                self.exitGraceTask = nil
            }
        }
    }

    public override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)

        let mouseLoc = NSEvent.mouseLocation
        if let win = self.window, win.frame.contains(mouseLoc) {
            let winPoint = win.convertPoint(fromScreen: mouseLoc)
            let barW: CGFloat = CGFloat(store.railBarWidth)
            let isOnRail = (edge == .right) ? (winPoint.x >= bounds.maxX - barW - 6) : (winPoint.x <= bounds.minX + barW + 6)
            if isOnRail || isPointInInteractiveDrawer(winPoint) {
                exitGraceTask?.cancel()
                exitGraceTask = nil
                return
            }
        }

        if exitGraceTask == nil {
            exitGraceTask = Task { @MainActor [weak self] in
                let graceSec = self?.store.activeExitGraceSeconds ?? 0.28
                try? await Task.sleep(nanoseconds: UInt64(graceSec * 1_000_000_000))
                guard !Task.isCancelled else { return }
                guard let self = self else { return }

                let activeId = self.store.activeDrawerItemId ?? self.store.activeDrawerPodId
                if let active = activeId {
                    let isCurrentActivePinned = self.store.isItemPinned(id: active)
                    if !isCurrentActivePinned {
                        withAnimation(.spring(response: 0.18, dampingFraction: 0.90)) {
                            self.store.activeDrawerItemId = nil
                            self.store.activeDrawerPodId = nil
                            self.store.hoveredPodId = nil
                        }
                        if let panel = self.window as? NSPanel {
                            panel.ignoresMouseEvents = true
                            panel.resignKey()
                        }
                    }
                }
                self.exitGraceTask = nil
            }
        }
    }

    public override func hitTest(_ point: NSPoint) -> NSView? {
        guard !store.isRailsFrozen else { return nil }
        let bounds = self.bounds
        let barW: CGFloat = CGFloat(store.railBarWidth)

        let isOnRail = (edge == .right) ? (point.x >= bounds.maxX - barW - 6) : (point.x <= bounds.minX + barW + 6)
        if isOnRail {
            return super.hitTest(point)
        }

        if isPointInInteractiveDrawer(point) {
            return super.hitTest(point)
        }

        // Outside drawer and rail: return nil for 100% pass-through
        return nil
    }
}
