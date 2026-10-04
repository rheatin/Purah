// Sources/PurahApp/WindowControllers/AmbientRailWindow.swift
import AppKit
import SwiftUI
import PurahCore
import PurahUI

@MainActor
public final class AmbientRailWindow: NSPanel {
    public override var canBecomeKey: Bool {
        false // 仅为常驻微光导轨，不抢焦点
    }

    public override var canBecomeMain: Bool {
        false
    }

    public init(edge: MountEdge, screen: NSScreen, store: PurahWorkspaceStore) {
        let screenRect = screen.frame
        let railWidth: CGFloat = 8 // 仅占用屏幕物理黑边 8px，绝不阻挡任何其他应用程序与桌面点击
        let x = (edge == .left) ? screenRect.minX : (screenRect.maxX - railWidth)
        let frame = NSRect(x: x, y: screenRect.minY, width: railWidth, height: screenRect.height)

        super.init(
            contentRect: frame,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        self.level = .statusBar
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = false
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let rootView = AmbientRailStripView(edge: edge, store: store)
            .ignoresSafeArea()
        self.contentView = NSHostingView(rootView: rootView)
    }
}
