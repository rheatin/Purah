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
    private var targetScreen: NSScreen
    private let store: PurahWorkspaceStore

    public init(edge: MountEdge, screen: NSScreen, store: PurahWorkspaceStore) {
        self.edge = edge
        self.targetScreen = screen
        self.store = store

        // Coordinate positioning:
        // 1. Horizontal X coordinates anchor strictly to visible screen boundaries (0 gap).
        // 2. Vertical Y coordinates use screen.visibleFrame to avoid dock and menu bar.
        let visibleRect = screen.visibleFrame
        let maxCanvasWidth: CGFloat = 340.0
        let x = (edge == .left) ? visibleRect.minX : (visibleRect.maxX - maxCanvasWidth)
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
                self.makeKey()
            }
        }
        super.sendEvent(event)
    }

    public func updateWidth() {
        // Redrawn reactively via workspace store
    }

    public func relocate(to screen: NSScreen) {
        self.targetScreen = screen
        let visibleRect = screen.visibleFrame
        let maxCanvasWidth: CGFloat = 340.0
        let x = (edge == .left) ? visibleRect.minX : (visibleRect.maxX - maxCanvasWidth)
        let frame = NSRect(x: x, y: visibleRect.minY, width: maxCanvasWidth, height: visibleRect.height)
        self.setFrame(frame, display: true)
    }
}
