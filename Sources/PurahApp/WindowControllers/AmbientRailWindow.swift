// Sources/PurahApp/WindowControllers/AmbientRailWindow.swift
import AppKit
import SwiftUI
import ObjectiveC
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

        // 关键定位：
        // 1. 水平 X 坐标严格紧贴物理屏幕边缘 screen.frame.minX / maxX (0 间隙，绝对贴边，彻底消除留白)
        // 2. 垂直 Y 坐标与高度使用 screen.visibleFrame，顶部避开菜单栏，底部严格避开 Dock 栏，绝不越界
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
        self.ignoresMouseEvents = false
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let rootView = AmbientRailStripView(edge: edge, store: store)
            .ignoresSafeArea()
        let hostingView = PassThroughHostingView(rootView: rootView, edge: edge, store: store)
        self.contentView = hostingView

        // 核心突破：让底层 NSNextStepFrame 在 contentView 返回 nil 时也严格返回 nil，彻底打通系统级点击穿透
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
            // 仅当子视图（PassThroughHostingView）明确返回可交互视图时才拦截；
            // 否则严格返回 nil，100% 穿透到操作系统底层的其他所有应用！
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

    public func setExpanded(_ expanded: Bool) {
        let targetWidth: CGFloat = expanded ? 340.0 : 14.0
        guard abs(self.frame.width - targetWidth) > 1.0 else { return }

        let screenRect = targetScreen.frame
        let visibleRect = targetScreen.visibleFrame
        let newX = (edge == .left) ? screenRect.minX : (screenRect.maxX - targetWidth)
        let newFrame = NSRect(x: newX, y: visibleRect.minY, width: targetWidth, height: visibleRect.height)
        self.setFrame(newFrame, display: true, animate: false)
    }

    public func updateWidth() {
        // 导轨自定义宽度更新由 store 响应式重绘
    }
}

// MARK: - 智能事件穿透托管视图 (空白区域 100% 穿透到其它 App，仅导轨与活跃抽屉真实几何区域响应交互)
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

        let point = convert(event.locationInWindow, from: nil)
        let barW: CGFloat = CGFloat(store.railBarWidth)
        let isOnRail = (edge == .right) ? (point.x >= bounds.maxX - barW - 6) : (point.x <= bounds.minX + barW + 6)
        if isOnRail { return }

        // 检查是否在活跃抽屉的真实几何纵深区域内 (覆盖展开的 340pt 宽度与高度，确保鼠标进入卡片内部稳定保活)
        if let activePod = store.activePod, activePod.edge == edge {
            let totalH = bounds.height
            let appkitTop = totalH * (1.0 - activePod.range.start) + 40
            let appkitBottom = totalH * (1.0 - (activePod.range.start + activePod.range.length)) - 40
            let inDrawerX = (edge == .right) ? (point.x >= bounds.maxX - 340) : (point.x <= bounds.minX + 340)
            let inDrawerY = (point.y >= appkitBottom && point.y <= appkitTop)
            if inDrawerX && inDrawerY {
                // 鼠标正在抽屉卡片内部查看或操作，坚决保持展开！
                return
            }
        }

        // 鼠标真正移出抽屉和导轨有效区域，自动收缩抽屉释放屏幕
        if store.activeDrawerItemId != nil || store.activeDrawerPodId != nil {
            withAnimation(.spring(response: 0.30, dampingFraction: 0.72)) {
                store.activeDrawerItemId = nil
                store.activeDrawerPodId = nil
                store.hoveredPodId = nil
            }
            if let window = self.window as? AmbientRailWindow {
                window.setExpanded(false)
            }
        }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        let isPinned = store.isDrawerPinned || !store.pinnedDrawerItemIds.isEmpty
        if !isPinned {
            withAnimation(.spring(response: 0.30, dampingFraction: 0.72)) {
                store.activeDrawerItemId = nil
                store.activeDrawerPodId = nil
                store.hoveredPodId = nil
            }
            if let window = self.window as? AmbientRailWindow {
                window.setExpanded(false)
            }
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let bounds = self.bounds
        let barW: CGFloat = CGFloat(store.railBarWidth)

        // 1. 处于导轨基座上时（紧贴物理边缘），绝对响应交互
        let isOnRail: Bool
        if edge == .right {
            isOnRail = (point.x >= bounds.maxX - barW - 6)
        } else {
            isOnRail = (point.x <= bounds.minX + barW + 6)
        }
        if isOnRail {
            return super.hitTest(point)
        }

        // 2. 如果当前有弹出的抽屉或 Pin 住的小窗，仅在其真实几何纵深卡片区域内拦截事件！
        let hasActive = (store.activeDrawerItemId != nil || store.activeDrawerPodId != nil || store.isDrawerPinned || !store.pinnedDrawerItemIds.isEmpty)
        if hasActive, let activePod = store.activePod, activePod.edge == edge {
            let totalH = bounds.height
            // 计算该 Pod 在 AppKit 坐标系（原点在左下角）下的垂直范围
            let appkitTop = totalH * (1.0 - activePod.range.start) + 40
            let appkitBottom = totalH * (1.0 - (activePod.range.start + activePod.range.length)) - 40
            let inDrawerX: Bool
            if edge == .right {
                inDrawerX = (point.x >= bounds.maxX - 340)
            } else {
                inDrawerX = (point.x <= bounds.minX + 340)
            }
            let inDrawerY = (point.y >= appkitBottom && point.y <= appkitTop)
            if inDrawerX && inDrawerY {
                return super.hitTest(point)
            }
        }

        // 3. 其它所有透明空白区域：直接返回 nil，配合 frameView swizzle，100% 穿透到背后的所有应用与桌面图标
        return nil
    }
}
