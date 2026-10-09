// Sources/PurahUI/WindowViews/PassThroughHostingView.swift
import AppKit
import SwiftUI
import PurahCore

public final class PassThroughHostingView<Content: View>: NSHostingView<Content> {
    public let edge: MountEdge
    public let store: PurahWorkspaceStore
    private var trackingArea: NSTrackingArea?

    // High-performance geometry snapshot cache to eliminate redundant layout solvers on hitTest
    private struct GeometrySnapshotCache {
        var boundsSize: CGSize = .zero
        var activeDrawerItemId: String? = nil
        var activeDrawerPodId: String? = nil
        var pinnedItemIds: Set<String> = []
        var cachedCardFrames: [CGRect] = []
        var cachedLayoutItems: [ResolvedPodLayoutItem] = []
        var timestamp: TimeInterval = 0
    }
    private var cache = GeometrySnapshotCache()

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

    private func updateCacheIfNeeded() {
        let now = CACurrentMediaTime()
        let activeItemId = store.activeDrawerItemId
        let activePodId = store.activeDrawerPodId
        let pinned = store.pinnedDrawerItemIds

        // If bounds and active/pinned state are unchanged, throttle layout re-evaluation to 35ms (approx 30Hz)
        if cache.boundsSize == bounds.size,
           cache.activeDrawerItemId == activeItemId,
           cache.activeDrawerPodId == activePodId,
           cache.pinnedItemIds == pinned,
           (now - cache.timestamp) < 0.035 {
            return
        }

        let totalH = Double(bounds.height)
        let windowW = Double(bounds.width)
        let frames = store.activeDrawerCardFrames(for: edge, totalHeight: totalH, windowWidth: windowW)
        let layout = store.resolvedPhysicalLayout(for: edge, totalHeight: totalH)

        cache = GeometrySnapshotCache(
            boundsSize: bounds.size,
            activeDrawerItemId: activeItemId,
            activeDrawerPodId: activePodId,
            pinnedItemIds: pinned,
            cachedCardFrames: frames,
            cachedLayoutItems: layout,
            timestamp: now
        )
    }

    public func isPointInInteractiveDrawer(_ point: NSPoint) -> Bool {
        guard !store.isRailsFrozen else { return false }
        updateCacheIfNeeded()
        return cache.cachedCardFrames.contains(where: { $0.contains(point) })
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
            super.scrollWheel(with: event)
        } else {
            // Cursor in transparent region outside cards: do not swallow scroll events, switch to click-through immediately
            if let panel = self.window as? NSPanel {
                panel.ignoresMouseEvents = true
            }
        }
    }

    public override func rightMouseDown(with event: NSEvent) {
        guard !store.isRailsFrozen else {
            super.rightMouseDown(with: event)
            return
        }
        let winPoint = event.locationInWindow
        if isPointInInteractiveDrawer(winPoint) {
            super.rightMouseDown(with: event)
        } else {
            // Cursor in transparent region outside cards: do not intercept context menus, switch to click-through immediately
            if let panel = self.window as? NSPanel {
                panel.ignoresMouseEvents = true
            }
        }
    }

    public override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        guard !store.isRailsFrozen else { return }

        // Forward to mouse monitor for unified hover-dwell, push-force, and exit-grace evaluation
        store.onLocalMouseMove?(event)

        let winPoint = event.locationInWindow
        let barW: CGFloat = CGFloat(store.railBarWidth) + 4.0
        let isOnRail = (edge == .right) ? (winPoint.x >= bounds.maxX - barW) : (winPoint.x <= bounds.minX + barW)
        let isInsideCard = isPointInInteractiveDrawer(winPoint)

        if let panel = self.window as? NSPanel {
            if isOnRail || isInsideCard {
                if panel.ignoresMouseEvents {
                    panel.ignoresMouseEvents = false
                }
            } else {
                // When cursor leaves cards and rails into transparent empty space:
                // Switch window to ignoresMouseEvents = true so scroll, right-click, and taps pass 100% through to underlying apps
                if !panel.ignoresMouseEvents {
                    panel.ignoresMouseEvents = true
                }
            }
        }
    }

    public override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)

        let mouseLoc = NSEvent.mouseLocation
        if let win = self.window, win.frame.contains(mouseLoc) {
            let winPoint = win.convertPoint(fromScreen: mouseLoc)
            let barW: CGFloat = CGFloat(store.railBarWidth) + 4.0
            let isOnRail = (edge == .right) ? (winPoint.x >= bounds.maxX - barW) : (winPoint.x <= bounds.minX + barW)
            if isOnRail || isPointInInteractiveDrawer(winPoint) {
                return
            }
        }

        if let panel = self.window as? NSPanel {
            if !panel.ignoresMouseEvents {
                panel.ignoresMouseEvents = true
            }
        }
    }

    public override func hitTest(_ point: NSPoint) -> NSView? {
        guard !store.isRailsFrozen else { return nil }
        let bounds = self.bounds
        let barW: CGFloat = CGFloat(store.railBarWidth) + 4.0

        let isOnRail = (edge == .right) ? (point.x >= bounds.maxX - barW) : (point.x <= bounds.minX + barW)
        if isOnRail {
            // Only capture if physically over an actual pod on the rail (not in empty margins or corners!)
            updateCacheIfNeeded()
            let totalH = Double(bounds.height)
            let currentWindowY = totalH - Double(point.y)
            let isOverPod = cache.cachedLayoutItems.contains(where: {
                let topY = $0.startY
                let bottomY = topY + $0.spanH
                return currentWindowY >= (topY - 3.0) && currentWindowY <= (bottomY + 3.0)
            })
            if isOverPod {
                return super.hitTest(point)
            }
        }

        if isPointInInteractiveDrawer(point) {
            return super.hitTest(point)
        }

        // Outside drawer and rail: return nil for 100% pass-through
        return nil
    }
}
