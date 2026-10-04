// Sources/PurahApp/WindowControllers/DrawerPanelWindow.swift
import AppKit
import SwiftUI
import PurahCore
import PurahUI

@MainActor
public final class DrawerPanelWindow: NSPanel {
    public override var canBecomeKey: Bool {
        true // 关键修复：允许获取键盘焦点，支持灵感便签 TextEditor 正常打字输入
    }

    public override var canBecomeMain: Bool {
        false
    }

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
            // 单个待办弹出的实心小窗：精确与该事项在导轨上的分段位置水平对齐
            drawerHeight = 44.0
            let count = max(store.todos.count, 1)
            let itemSlotH = barHeight / CGFloat(count)
            let idx = store.todos.firstIndex(where: { $0.id == activeTodo.id }) ?? 0
            let itemYFromTop = fullBarTopY - CGFloat(idx) * itemSlotH
            originY = itemYFromTop - drawerHeight
        } else if let activeEvent = activeEvent, pod.id == "calendar" {
            // 单个日程弹出的实心小窗：精确与该日程在时间轴上的位置对齐
            drawerHeight = 48.0
            let count = max(store.calendarEvents.count, 1)
            let itemSlotH = barHeight / CGFloat(count)
            let idx = store.calendarEvents.firstIndex(where: { $0.id == activeEvent.id }) ?? 0
            let itemYFromTop = fullBarTopY - CGFloat(idx) * itemSlotH
            originY = itemYFromTop - drawerHeight
        } else if pod.id == "notes" {
            // 便签小窗：给足打字输入高度 (150pt)
            drawerHeight = 150.0
            originY = fullBarTopY - drawerHeight
        } else if pod.id == "shelf" {
            // 暂存架小窗：给足文件收纳与拖拽区域 (160pt)
            drawerHeight = 160.0
            originY = fullBarTopY - drawerHeight
        } else if pod.id == "music" {
            drawerHeight = 54.0
            originY = fullBarTopY - drawerHeight
        } else {
            drawerHeight = max(barHeight, 140.0)
            originY = screenRect.minY + (screenRect.height * (1.0 - CGFloat(pod.range.start + pod.range.length)))
        }

        // 抽屉无缝紧贴 8px 导轨边缘 (0 间隙)
        let originX: CGFloat = (pod.edge == .left)
            ? (screenRect.minX + 8)
            : (screenRect.maxX - drawerWidth - 8)

        let initialFrame = NSRect(x: originX, y: max(screenRect.minY + 10, originY), width: drawerWidth, height: drawerHeight)

        super.init(
            contentRect: initialFrame,
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
                default:
                    AnyView(Text("Slot Pod \(pod.name)"))
                }
            }
        }
        self.contentView = NSHostingView(rootView: container)
    }
}
