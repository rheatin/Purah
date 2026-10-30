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
        var hoveredPodId: String? = nil
        var activeDrawerItemId: String? = nil
        var activeDrawerPodId: String? = nil
        var pinnedItemIds: Set<String> = []
        var isDynamicBreathingEnabled: Bool = true
        var currentRailPage: Int = 0
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
        let hoveredId = store.hoveredPodId
        let activeItemId = store.activeDrawerItemId
        let activePodId = store.activeDrawerPodId
        let pinned = store.pinnedDrawerItemIds
        let isBreathing = store.isDynamicBreathingEnabled
        let page = store.currentRailPage(for: edge)

        // If bounds and active/pinned state are unchanged, throttle layout re-evaluation to 35ms (approx 30Hz)
        if cache.boundsSize == bounds.size,
           cache.hoveredPodId == hoveredId,
           cache.activeDrawerItemId == activeItemId,
           cache.activeDrawerPodId == activePodId,
           cache.pinnedItemIds == pinned,
           cache.isDynamicBreathingEnabled == isBreathing,
           cache.currentRailPage == page,
           (now - cache.timestamp) < 0.035 {
            return
        }

        let totalH = Double(bounds.height)
        let windowW = Double(bounds.width)
        let frames = store.activeDrawerCardFrames(for: edge, totalHeight: totalH, windowWidth: windowW)
        let layout = store.resolvedPhysicalLayout(for: edge, totalHeight: totalH)

        cache = GeometrySnapshotCache(
            boundsSize: bounds.size,
            hoveredPodId: hoveredId,
            activeDrawerItemId: activeItemId,
            activeDrawerPodId: activePodId,
            pinnedItemIds: pinned,
            isDynamicBreathingEnabled: isBreathing,
            currentRailPage: page,
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
        if isSculptStripMode {
            let sculptW: CGFloat = 215.0
            let isInsideSculptStrip = (edge == .right) ? (winPoint.x >= bounds.maxX - sculptW) : (winPoint.x <= bounds.minX + sculptW)
            if isInsideSculptStrip {
                if let panel = self.window as? NSPanel {
                    panel.ignoresMouseEvents = false
                }
                super.scrollWheel(with: event)
            } else if let panel = self.window as? NSPanel {
                panel.ignoresMouseEvents = true
            }
            return
        }

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

    /// True from the moment the left button goes down until it comes back up.
    ///
    /// A drag session emits no `mouseMoved`, so the hit-test writes in `mouseMoved` /`mouseExited`
    /// would win against `EdgeMouseMonitor`'s per-frame `setInteractive(true)` and the panel would
    /// fall back to click-through exactly when a payload is inbound. While the button is held the
    /// monitor owns interactivity instead.
    private var isLeftButtonHeld: Bool {
        NSEvent.pressedMouseButtons & 0x1 != 0
    }

    private var isSculptStripMode: Bool {
        store.isLiveRailEditingMode && !store.isRehearsingBreathingInSculptor
    }

    public override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        guard !store.isRailsFrozen else { return }

        // Forward to mouse monitor for unified hover-dwell, push-force, and exit-grace evaluation
        store.onLocalMouseMove?(event)

        let winPoint = event.locationInWindow
        if isSculptStripMode {
            let sculptW: CGFloat = 215.0
            let isInsideSculptStrip = (edge == .right) ? (winPoint.x >= bounds.maxX - sculptW) : (winPoint.x <= bounds.minX + sculptW)
            if let panel = self.window as? NSPanel {
                panel.ignoresMouseEvents = !isInsideSculptStrip
            }
            return
        }

        guard !isLeftButtonHeld else { return }

        let barW: CGFloat = max(CGFloat(store.railBarWidth), 4.0)
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

        // A drag in flight leaves the panel; the monitor keeps the rail awake instead.
        guard !isLeftButtonHeld else { return }

        let mouseLoc = NSEvent.mouseLocation
        if let win = self.window, win.frame.contains(mouseLoc) {
            let winPoint = win.convertPoint(fromScreen: mouseLoc)
            if isSculptStripMode {
                let sculptW: CGFloat = 215.0
                let isInsideSculptStrip = (edge == .right) ? (winPoint.x >= bounds.maxX - sculptW) : (winPoint.x <= bounds.minX + sculptW)
                if isInsideSculptStrip {
                    return
                }
            } else {
                let barW: CGFloat = max(CGFloat(store.railBarWidth), 4.0)
                let isOnRail = (edge == .right) ? (winPoint.x >= bounds.maxX - barW) : (winPoint.x <= bounds.minX + barW)
                if isOnRail || isPointInInteractiveDrawer(winPoint) {
                    return
                }
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
        if isSculptStripMode {
            let sculptW: CGFloat = 215.0
            let isInsideSculptStrip = (edge == .right) ? (point.x >= bounds.maxX - sculptW) : (point.x <= bounds.minX + sculptW)
            if isInsideSculptStrip {
                if let panel = self.window as? NSPanel, panel.ignoresMouseEvents {
                    panel.ignoresMouseEvents = false
                }
                return super.hitTest(point)
            }
            return nil
        }

        let barW: CGFloat = max(CGFloat(store.railBarWidth), 4.0)
        let totalH = Double(bounds.height)
        let currentWindowY = totalH - Double(point.y)

        if ((currentWindowY >= 20.0 && currentWindowY <= 44.0) || (currentWindowY >= (totalH - 44.0) && currentWindowY <= (totalH - 20.0))),
           store.paginatedPods(for: edge, totalHeight: totalH).count > 1 {
            let portalHitW: CGFloat = max(barW + 8.0, 16.0)
            let isOverPortal = (edge == .right) ? (point.x >= bounds.maxX - portalHitW) : (point.x <= bounds.minX + barW + 8.0)
            if isOverPortal {
                return super.hitTest(point)
            }
        }

        let isOnRail = (edge == .right) ? (point.x >= bounds.maxX - barW) : (point.x <= bounds.minX + barW)
        if isOnRail {
            // Only capture if physically over an actual pod on the rail (not in empty margins or corners!)
            updateCacheIfNeeded()
            // Hoisted out of the per-item closure: `isBreathingActive` solves
            // the whole rail's layout, and `hitTest` runs on every mouse move.
            let railIsBreathing = store.isBreathingActive(for: edge, totalHeight: totalH)
            let isOverPod = cache.cachedLayoutItems.contains(where: { item in
                let topY = item.startY
                let actualSpan: Double
                let isSharedMajorSubBar = (item.majorGroupId != nil && abs(item.drawerSpanH - item.spanH) > 1.0)
                if !isSharedMajorSubBar,
                   store.isPodDecomposed(item.pod.id),
                   let provider = store.capabilityProvider(for: item.pod.id) {
                    let policy = provider.decomposedPolicy(store: store)
                    let rawCount = provider.subItemCount(store: store)
                    let minChipH = Double(policy.minChipHeight)
                    let maxChipH = Double(policy.maxChipHeight)
                    let spacing = Double(policy.spacing)
                    let isDynamicAccordion = railIsBreathing
                    let maxAllowed = isDynamicAccordion
                        ? max(policy.maxRailItems, 1)
                        : max(min(Int((item.spanH + spacing) / (minChipH + spacing)), policy.maxRailItems), 1)
                    let count = min(rawCount, maxAllowed)
                    let safeCount = max(count, 1)
                    let totalSpacing = spacing * Double(safeCount - 1)
                    let effectiveMinChipH = isDynamicAccordion ? 6.0 : minChipH
                    let itemH = min(max((item.spanH - totalSpacing) / Double(safeCount), effectiveMinChipH), maxChipH)
                    actualSpan = Double(count) * itemH + spacing * Double(max(count - 1, 0))
                } else {
                    actualSpan = item.spanH
                }
                let bottomY = topY + actualSpan
                return currentWindowY >= topY && currentWindowY <= bottomY
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
