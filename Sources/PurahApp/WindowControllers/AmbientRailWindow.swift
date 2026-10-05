// Sources/PurahApp/WindowControllers/AmbientRailWindow.swift
import AppKit
import SwiftUI
import ObjectiveC
import PurahCore
import PurahUI

@MainActor
public final class AmbientRailWindow: NSPanel {
    public override var canBecomeKey: Bool {
        true // Allow key window status for text editing in notes
    }

    public override var canBecomeMain: Bool {
        false
    }

    private let edge: MountEdge
    private let targetScreen: NSScreen
    private let store: PurahWorkspaceStore

    public init(edge: MountEdge, screen: NSScreen, store: PurahWorkspaceStore) {
        self.edge = edge
        self.targetScreen = screen
        self.store = store

        // Coordinate positioning:
        // 1. Horizontal X coordinates anchor strictly to physical screen boundaries (0 gap).
        // 2. Vertical Y coordinates use screen.visibleFrame to avoid dock and menu bar.
        let screenRect = screen.frame
        let visibleRect = screen.visibleFrame
        let maxCanvasWidth: CGFloat = 340.0
        let x = (edge == .left) ? screenRect.minX : (screenRect.maxX - maxCanvasWidth)
        let frame = NSRect(x: x, y: visibleRect.minY, width: maxCanvasWidth, height: visibleRect.height)

        super.init(
            contentRect: frame,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = true // Pass-through by default when docked
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let rootView = AmbientRailStripView(edge: edge, store: store)
            .ignoresSafeArea()
        let hostingView = PassThroughHostingView(rootView: rootView, edge: edge, store: store)
        hostingView.wantsLayer = true
        hostingView.layer?.drawsAsynchronously = true
        hostingView.layerContentsRedrawPolicy = .onSetNeedsDisplay
        self.contentView = hostingView

        // Swizzle NSNextStepFrame to return nil when contentView returns nil for system-level pass-through
        if let frameView = hostingView.superview {
            Self.enablePassThroughOnFrameView(frameView)
        }
    }

    private static var hasSwizzledFrameView = false

    private static func enablePassThroughOnFrameView(_ frameView: NSView) {
        guard !hasSwizzledFrameView else { return }
        hasSwizzledFrameView = true

        let frameClass: AnyClass = object_getClass(frameView)!
        let originalSelector = #selector(NSView.hitTest(_:))

        let block: @convention(block) (AnyObject, NSPoint) -> NSView? = { (selfObj, point) in
            guard let view = selfObj as? NSView else { return nil }
            // Intercept only when subviews (PassThroughHostingView) return a non-nil hit view
            for sub in view.subviews.reversed() {
                let subPoint = view.convert(point, to: sub)
                if let hit = sub.hitTest(subPoint) {
                    return hit
                }
            }
            return nil
        }
        let imp = imp_implementationWithBlock(block)
        class_replaceMethod(frameClass, originalSelector, imp, "@@:{CGPoint=dd}")
    }

    public func setInteractive(_ interactive: Bool) {
        let shouldIgnore = !interactive
        if self.ignoresMouseEvents != shouldIgnore {
            self.ignoresMouseEvents = shouldIgnore
        }
    }

    public override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            if !self.isKeyWindow {
                NSApp.activate(ignoringOtherApps: true)
                self.makeKey()
            }
        }
        super.sendEvent(event)
    }

    public func updateWidth() {
        // Redrawn reactively via workspace store
    }
}

// MARK: - Pass-Through Hosting View
final class PassThroughHostingView<Content: View>: NSHostingView<Content> {
    private let edge: MountEdge
    private let store: PurahWorkspaceStore
    private var trackingArea: NSTrackingArea?

    init(rootView: Content, edge: MountEdge, store: PurahWorkspaceStore) {
        self.edge = edge
        self.store = store
        super.init(rootView: rootView)
    }

    required init(rootView: Content) {
        self.edge = .right
        self.store = PurahWorkspaceStore()
        super.init(rootView: rootView)
    }

    @MainActor required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true // Dispatch first click directly to controls and text inputs in accessory background app
    }

    override func updateTrackingAreas() {
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

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let isPinned = store.isDrawerPinned || !store.pinnedDrawerItemIds.isEmpty
        guard !isPinned else { return }

        let winPoint = event.locationInWindow
        let barW: CGFloat = CGFloat(store.railBarWidth)
        let isOnRail = (edge == .right) ? (winPoint.x >= bounds.maxX - barW - 6) : (winPoint.x <= bounds.minX + barW + 6)
        if isOnRail { return }

        // Check if inside active drawer card bounds using canonical window coordinates (0 at bottom, totalH at top)
        if let activePod = store.activePod, activePod.edge == edge {
            let totalH = bounds.height
            let minY = totalH * (1.0 - (activePod.range.start + activePod.range.length)) - 60
            let maxY = totalH * (1.0 - activePod.range.start) + 60
            let inDrawerX = (edge == .right) ? (winPoint.x >= bounds.maxX - 340) : (winPoint.x <= bounds.minX + 340)
            let inDrawerY = (winPoint.y >= minY && winPoint.y <= maxY)
            if inDrawerX && inDrawerY {
                // Mouse is inside the drawer card or its interactive controls; stay open
                return
            }
        }

        // Mouse genuinely left the drawer and rail; smoothly retract
        if store.activeDrawerItemId != nil || store.activeDrawerPodId != nil {
            withAnimation(.spring(response: 0.30, dampingFraction: 0.72)) {
                store.activeDrawerItemId = nil
                store.activeDrawerPodId = nil
                store.hoveredPodId = nil
            }
            if let window = self.window as? AmbientRailWindow {
                window.setInteractive(false)
                window.resignKey()
            }
        }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        let isPinned = store.isDrawerPinned || !store.pinnedDrawerItemIds.isEmpty
        guard !isPinned else { return }

        // Guard against premature collapse when mouse moves into subview buttons or text fields
        let mouseLoc = NSEvent.mouseLocation
        if let win = self.window, win.frame.contains(mouseLoc) {
            let winPoint = win.convertPoint(fromScreen: mouseLoc)
            let barW: CGFloat = CGFloat(store.railBarWidth)
            let isOnRail = (edge == .right) ? (winPoint.x >= bounds.maxX - barW - 6) : (winPoint.x <= bounds.minX + barW + 6)
            if isOnRail { return }

            if let activePod = store.activePod, activePod.edge == edge {
                let totalH = bounds.height
                let minY = totalH * (1.0 - (activePod.range.start + activePod.range.length)) - 60
                let maxY = totalH * (1.0 - activePod.range.start) + 60
                let inDrawerX = (edge == .right) ? (winPoint.x >= bounds.maxX - 340) : (winPoint.x <= bounds.minX + 340)
                let inDrawerY = (winPoint.y >= minY && winPoint.y <= maxY)
                if inDrawerX && inDrawerY {
                    return
                }
            }
        }

        withAnimation(.spring(response: 0.30, dampingFraction: 0.72)) {
            store.activeDrawerItemId = nil
            store.activeDrawerPodId = nil
            store.hoveredPodId = nil
        }
        if let window = self.window as? AmbientRailWindow {
            window.setInteractive(false)
            window.resignKey()
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let bounds = self.bounds
        let barW: CGFloat = CGFloat(store.railBarWidth)

        // 1. On rail baseline: always handle interaction
        let isOnRail: Bool
        if edge == .right {
            isOnRail = (point.x >= bounds.maxX - barW - 6)
        } else {
            isOnRail = (point.x <= bounds.minX + barW + 6)
        }
        if isOnRail {
            return super.hitTest(point)
        }

        // 2. Over active/pinned drawer card: intercept events
        let hasActive = (store.activeDrawerItemId != nil || store.activeDrawerPodId != nil || store.isDrawerPinned || !store.pinnedDrawerItemIds.isEmpty)
        if hasActive, let activePod = store.activePod, activePod.edge == edge {
            let totalH = bounds.height
            let minY = totalH * (1.0 - (activePod.range.start + activePod.range.length)) - 60
            let maxY = totalH * (1.0 - activePod.range.start) + 60
            let inDrawerX: Bool
            if edge == .right {
                inDrawerX = (point.x >= bounds.maxX - 340)
            } else {
                inDrawerX = (point.x <= bounds.minX + 340)
            }
            let inDrawerY = (point.y >= minY && point.y <= maxY)
            if inDrawerX && inDrawerY {
                return super.hitTest(point)
            }
        }

        // 3. Transparent area: return nil for 100% pass-through to background apps
        return nil
    }
}
