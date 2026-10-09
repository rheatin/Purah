// Sources/PurahApp/WindowControllers/AmbientRailWindow.swift
import AppKit
import SwiftUI
import PurahCore
import PurahUI

@MainActor
public final class AmbientRailWindow: NSPanel {
    public static let maxCanvasWidth: CGFloat = 580.0

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
        let maxCanvasWidth = Self.maxCanvasWidth
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
        self.acceptsMouseMovedEvents = true // Enable local .mouseMoved event dispatch for edge tracking
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let rootView = AmbientRailStripView(edge: edge, store: store)
            .ignoresSafeArea()
        let hostingView = PassThroughHostingView(rootView: rootView, edge: edge, store: store)
        hostingView.wantsLayer = true
        hostingView.layer?.drawsAsynchronously = true
        hostingView.layerContentsRedrawPolicy = .onSetNeedsDisplay
        self.contentView = hostingView
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
        let maxCanvasWidth = Self.maxCanvasWidth
        let x = (edge == .left) ? visibleRect.minX : (visibleRect.maxX - maxCanvasWidth)
        let frame = NSRect(x: x, y: visibleRect.minY, width: maxCanvasWidth, height: visibleRect.height)
        self.setFrame(frame, display: true)
    }
}
