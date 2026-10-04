// Sources/PurahApp/WindowControllers/AmbientRailWindow.swift
import AppKit
import SwiftUI
import PurahCore
import PurahUI

@MainActor
public final class AmbientRailWindow: NSPanel {
    public override var canBecomeKey: Bool {
        false // 常驻导轨不抢占焦点
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

        // 严格使用 screen.visibleFrame，顶部避开菜单栏，底部严格避开 Dock 栏，绝不超出屏幕底线
        let visibleRect = screen.visibleFrame
        let railWidth = CGFloat(store.railBarWidth)
        let x = (edge == .left) ? visibleRect.minX : (visibleRect.maxX - railWidth)
        let frame = NSRect(x: x, y: visibleRect.minY, width: railWidth, height: visibleRect.height)

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

    /// 更新导轨物理宽度
    public func updateWidth() {
        let visibleRect = targetScreen.visibleFrame
        let railWidth = CGFloat(store.railBarWidth)
        let x = (edge == .left) ? visibleRect.minX : (visibleRect.maxX - railWidth)
        let frame = NSRect(x: x, y: visibleRect.minY, width: railWidth, height: visibleRect.height)
        self.setFrame(frame, display: true)
    }
}
