// Sources/PurahApp/WindowControllers/AmbientRailWindow.swift
import AppKit
import SwiftUI
import PurahCore
import PurahUI

@MainActor
public final class AmbientRailWindow: NSPanel {
    public init(edge: MountEdge, screen: NSScreen, store: PurahWorkspaceStore) {
        let screenRect = screen.frame
        let railWidth: CGFloat = 280 // 容纳单项弹出的实心抽屉 (248pt) + 边缘贴合导轨 (6pt)
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
