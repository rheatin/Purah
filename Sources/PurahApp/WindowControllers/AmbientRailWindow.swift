// Sources/PurahApp/WindowControllers/AmbientRailWindow.swift
import AppKit
import SwiftUI
import PurahCore
import PurahUI

@MainActor
public final class AmbientRailWindow: NSPanel {
    public override var canBecomeKey: Bool {
        true // 允许获取键盘焦点，支持便签 TextEditor 打字输入
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
        self.ignoresMouseEvents = false
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let rootView = AmbientRailStripView(edge: edge, store: store)
            .ignoresSafeArea()
        self.contentView = PassThroughHostingView(rootView: rootView, edge: edge, store: store)
    }

    public func updateWidth() {
        // 画布尺寸由 PassThroughHostingView 智能穿透控制
    }
}

// MARK: - 智能事件穿透托管视图 (空白区域 100% 穿透到其它 App，仅导轨与弹出抽屉响应交互)
final class PassThroughHostingView<Content: View>: NSHostingView<Content> {
    private let edge: MountEdge
    private let store: PurahWorkspaceStore

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

    override func hitTest(_ point: NSPoint) -> NSView? {
        let bounds = self.bounds
        let barW: CGFloat = CGFloat(store.railBarWidth)

        // 1. 处于导轨基座上时，绝对响应交互
        let isOnRail: Bool
        if edge == .right {
            isOnRail = (point.x >= bounds.maxX - barW - 6)
        } else {
            isOnRail = (point.x <= bounds.minX + barW + 6)
        }
        if isOnRail {
            return super.hitTest(point)
        }

        // 2. 如果当前有弹出的抽屉或 Pin 住的小窗
        let hasActive = (store.activeDrawerItemId != nil || store.activeDrawerPodId != nil || store.isDrawerPinned || !store.pinnedDrawerItemIds.isEmpty)
        if hasActive, let activePod = store.activePod, activePod.edge == edge {
            let isInDrawerArea: Bool
            if edge == .right {
                isInDrawerArea = (point.x >= bounds.maxX - 310)
            } else {
                isInDrawerArea = (point.x <= bounds.minX + 310)
            }
            if isInDrawerArea {
                return super.hitTest(point)
            }
        }

        // 3. 其它所有透明空白区域：直接返回 nil，100% 穿透到背后的所有应用与桌面图标
        return nil
    }
}
