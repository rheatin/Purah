// Sources/PurahApp/WindowControllers/AmbientRailWindow.swift
import AppKit
import SwiftUI
import PurahCore
import PurahUI

@MainActor
public final class AmbientRailWindow: NSPanel {
    public static let maxCanvasWidth: CGFloat = 580.0
    public static let compactCanvasWidth: CGFloat = 28.0

    public override var canBecomeKey: Bool {
        true // Allow key window status for text editing in notes
    }

    public override var canBecomeMain: Bool {
        false
    }

    private let edge: MountEdge
    private var targetScreen: NSScreen
    private let store: PurahWorkspaceStore
    public private(set) var isExpanded: Bool = false

    public init(edge: MountEdge, screen: NSScreen, store: PurahWorkspaceStore) {
        self.edge = edge
        self.targetScreen = screen
        self.store = store

        // Coordinate positioning:
        // Starts in ultra-lightweight compact canvas (28pt) to save ~20MB framebuffer memory when docked.
        let visibleRect = screen.visibleFrame
        let initialWidth = Self.compactCanvasWidth
        let x = (edge == .left) ? visibleRect.minX : (visibleRect.maxX - initialWidth)
        let frame = NSRect(x: x, y: visibleRect.minY, width: initialWidth, height: visibleRect.height)

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
        // Symmetrically anchor layer contents to the physical screen border:
        // Left rail anchors to .topLeft, Right rail anchors to .topRight.
        // Even when canvas resizes between 28pt and 580pt, physical content never shifts.
        hostingView.layerContentsPlacement = (edge == .right) ? .topRight : .topLeft
        hostingView.layer?.contentsGravity = (edge == .right) ? .topRight : .topLeft
        self.contentView = hostingView
    }

    public func setExpanded(_ expanded: Bool) {
        guard isExpanded != expanded else { return }
        self.isExpanded = expanded
        updateFrame(display: true)
    }

    public func updateFrame(display: Bool = true) {
        let visibleRect = targetScreen.visibleFrame
        let targetWidth = isExpanded ? Self.maxCanvasWidth : Self.compactCanvasWidth
        let x = (edge == .left) ? visibleRect.minX : (visibleRect.maxX - targetWidth)
        let newFrame = NSRect(x: x, y: visibleRect.minY, width: targetWidth, height: visibleRect.height)
        if self.frame != newFrame {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.setFrame(newFrame, display: display)
            CATransaction.commit()
        }
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

    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else {
            return super.performKeyEquivalent(with: event)
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""

        if flags == .command {
            switch chars {
            case "c":
                if NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self) { return true }
            case "v":
                if NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self) { return true }
            case "x":
                if NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: self) { return true }
            case "a":
                if NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: self) { return true }
            case "z":
                if NSApp.sendAction(Selector(("undo:")), to: nil, from: self) { return true }
            default:
                break
            }
        } else if flags == [.command, .shift] && chars == "z" {
            if NSApp.sendAction(Selector(("redo:")), to: nil, from: self) { return true }
        }

        return super.performKeyEquivalent(with: event)
    }

    public func updateWidth() {
        updateFrame(display: true)
    }

    public func relocate(to screen: NSScreen) {
        self.targetScreen = screen
        updateFrame(display: true)
    }
}
