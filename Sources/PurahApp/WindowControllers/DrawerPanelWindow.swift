// Sources/PurahApp/WindowControllers/DrawerPanelWindow.swift
import AppKit
import SwiftUI
import PurahCore
import PurahUI

@MainActor
public final class DrawerPanelWindow: NSPanel {
    public override var canBecomeKey: Bool {
        true // 关键修复：允许获取键盘焦点，支持便签 TextEditor 正常打字输入
    }

    public override var canBecomeMain: Bool {
        false
    }

    private let targetFrame: NSRect
    private let mountEdge: MountEdge

    public init(pod: SlotPod, screen: NSScreen, store: PurahWorkspaceStore, onClose: @escaping () -> Void) {
        let screenRect = screen.frame
        let drawerWidth: CGFloat = 260.0

        // 计算当前是否命中单个 item 抽屉
        let activeItemId = store.activeDrawerItemId
        let activeTodo = store.todos.first(where: { $0.id == activeItemId })
        let activeEvent = store.calendarEvents.first(where: { $0.id == activeItemId })

        let barHeight = CGFloat(pod.range.length) * screenRect.height
        let fullBarTopY = screenRect.minY + (screenRect.height * (1.0 - CGFloat(pod.range.start)))

        let drawerHeight: CGFloat
        let originY: CGFloat

        if let activeTodo = activeTodo, pod.id == "todo" {
            // 单个待办弹出的实心小窗
            drawerHeight = 44.0
            let count = max(store.todos.count, 1)
            let itemSlotH = barHeight / CGFloat(count)
            let idx = store.todos.firstIndex(where: { $0.id == activeTodo.id }) ?? 0
            let itemYFromTop = fullBarTopY - CGFloat(idx) * itemSlotH
            originY = itemYFromTop - drawerHeight
        } else if let activeEvent = activeEvent, pod.id == "calendar" {
            // 单个日程弹出的实心小窗
            drawerHeight = 52.0
            let count = max(store.calendarEvents.count, 1)
            let itemSlotH = barHeight / CGFloat(count)
            let idx = store.calendarEvents.firstIndex(where: { $0.id == activeEvent.id }) ?? 0
            let itemYFromTop = fullBarTopY - CGFloat(idx) * itemSlotH
            originY = itemYFromTop - drawerHeight
        } else if pod.id == "calendar" {
            // 完整日程列表小窗：给足高度空间 (至少 240pt)，彻底解决卡片挤压模糊
            drawerHeight = max(barHeight, 240.0)
            originY = screenRect.minY + (screenRect.height * (1.0 - CGFloat(pod.range.start + pod.range.length)))
        } else if pod.id == "todo" {
            // 完整待办列表小窗：给足高度空间 (至少 220pt)
            drawerHeight = max(barHeight, 220.0)
            originY = screenRect.minY + (screenRect.height * (1.0 - CGFloat(pod.range.start + pod.range.length)))
        } else if pod.id == "vitals" {
            // 性能热态脉搏：CPU/内存 Top3 列表高度 (140pt)
            drawerHeight = 140.0
            originY = fullBarTopY - drawerHeight
        } else if pod.id == "scripts" {
            // 脚本跑道小窗：快捷指令动作列表高度 (160pt)
            drawerHeight = 160.0
            originY = fullBarTopY - drawerHeight
        } else if pod.id == "notes" {
            // 便签小窗：给足打字输入高度 (160pt)
            drawerHeight = 160.0
            originY = fullBarTopY - drawerHeight
        } else if pod.id == "shelf" {
            // 暂存架小窗：给足文件收纳与拖拽区域 (170pt)
            drawerHeight = 170.0
            originY = fullBarTopY - drawerHeight
        } else if pod.id == "music" {
            drawerHeight = 54.0
            originY = fullBarTopY - drawerHeight
        } else {
            drawerHeight = max(barHeight, 160.0)
            originY = screenRect.minY + (screenRect.height * (1.0 - CGFloat(pod.range.start + pod.range.length)))
        }

        // 抽屉无缝紧贴 8px 导轨边缘 (0 间隙)
        let originX: CGFloat = (pod.edge == .left)
            ? (screenRect.minX + 8)
            : (screenRect.maxX - drawerWidth - 8)

        let initialFrame = NSRect(x: originX, y: max(screenRect.minY + 10, originY), width: drawerWidth, height: drawerHeight)
        self.targetFrame = initialFrame
        self.mountEdge = pod.edge

        // 初始动画位置：从边缘外缩进 40px，准备向屏幕中间弹射滑入
        let slideOffset: CGFloat = (pod.edge == .left) ? -40 : 40
        let offscreenFrame = NSRect(x: initialFrame.origin.x + slideOffset, y: initialFrame.origin.y, width: initialFrame.width, height: initialFrame.height)

        super.init(
            contentRect: offscreenFrame,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.collectionBehavior = [.canJoinAllSpaces, .transient]

        let container = DrawerContainerView(
            pod: pod,
            store: store,
            onClose: onClose
        ) {
            Group {
                switch pod.id {
                case "calendar":
                    AnyView(CalendarDrawerView(store: store))
                case "todo":
                    AnyView(TodoDrawerView(store: store))
                case "music":
                    AnyView(MusicDrawerView(store: store))
                case "shelf":
                    AnyView(DropShelfDrawerView(store: store))
                case "notes":
                    AnyView(QuickNoteDrawerView(store: store))
                case "vitals":
                    AnyView(HardwareVitalsDrawerView(store: store))
                case "scripts":
                    AnyView(ScriptRunwayDrawerView(store: store))
                default:
                    AnyView(Text("Slot Pod \(pod.name)"))
                }
            }
        }
        self.contentView = NSHostingView(rootView: container)
    }

    /// 执行从边缘往屏幕中间弹出来的物理弹簧动效
    public func presentWithSpring() {
        self.orderFront(nil)
        self.alphaValue = 0.2
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.24
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().setFrame(self.targetFrame, display: true)
            self.animator().alphaValue = 1.0
        }
    }
}
