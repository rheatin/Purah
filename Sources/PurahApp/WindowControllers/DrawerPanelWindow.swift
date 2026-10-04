// Sources/PurahApp/WindowControllers/DrawerPanelWindow.swift
import AppKit
import SwiftUI
import PurahCore
import PurahUI

@MainActor
public final class DrawerPanelWindow: NSPanel {
    public override var canBecomeKey: Bool {
        true // 允许获取键盘焦点，支持便签 TextEditor 正常打字输入
    }

    public override var canBecomeMain: Bool {
        false
    }

    private let targetFrame: NSRect
    private let mountEdge: MountEdge

    public init(pod: SlotPod, screen: NSScreen, store: PurahWorkspaceStore, onClose: @escaping () -> Void) {
        // Layout calculations anchored to screen.visibleFrame
        let visibleRect = screen.visibleFrame
        let railWidth = CGFloat(store.railBarWidth)
        let drawerWidth: CGFloat = (pod.id == "music" ? 300.0 : 280.0)

        let activeItemId = store.activeDrawerItemId
        let activeTodo = store.todos.first(where: { $0.id == activeItemId })
        let activeEvent = store.calendarEvents.first(where: { $0.id == activeItemId })

        let barHeight = CGFloat(pod.range.length) * visibleRect.height
        let fullBarTopY = visibleRect.minY + (visibleRect.height * (1.0 - CGFloat(pod.range.start)))

        let drawerHeight: CGFloat
        let originY: CGFloat

        if let activeTodo = activeTodo, pod.id == "todo" {
            let count = max(store.todos.count, 1)
            let spacing: CGFloat = 2.5
            let totalSpacing = spacing * CGFloat(count - 1)
            let itemSlotH = max((barHeight - totalSpacing) / CGFloat(count), 28.0)
            let idx = store.todos.firstIndex(where: { $0.id == activeTodo.id }) ?? 0
            let itemYFromTop = fullBarTopY - CGFloat(idx) * (itemSlotH + spacing)

            drawerHeight = itemSlotH
            originY = itemYFromTop - drawerHeight
        } else if let activeEvent = activeEvent, pod.id == "calendar" {
            let count = max(store.calendarEvents.count, 1)
            let spacing: CGFloat = 2.5
            let totalSpacing = spacing * CGFloat(count - 1)
            let itemSlotH = max((barHeight - totalSpacing) / CGFloat(count), 30.0)
            let idx = store.calendarEvents.firstIndex(where: { $0.id == activeEvent.id }) ?? 0
            let itemYFromTop = fullBarTopY - CGFloat(idx) * (itemSlotH + spacing)

            drawerHeight = itemSlotH
            originY = itemYFromTop - drawerHeight
        } else if pod.id == "calendar" {
            drawerHeight = max(barHeight, 220.0)
            originY = visibleRect.minY + (visibleRect.height * (1.0 - CGFloat(pod.range.start + pod.range.length)))
        } else if pod.id == "todo" {
            drawerHeight = max(barHeight, 200.0)
            originY = visibleRect.minY + (visibleRect.height * (1.0 - CGFloat(pod.range.start + pod.range.length)))
        } else if pod.id == "vitals" {
            drawerHeight = 140.0
            originY = fullBarTopY - drawerHeight
        } else if pod.id == "scripts" {
            drawerHeight = 160.0
            originY = fullBarTopY - drawerHeight
        } else if pod.id == "notes" {
            drawerHeight = 160.0
            originY = fullBarTopY - drawerHeight
        } else if pod.id == "shelf" {
            drawerHeight = 170.0
            originY = fullBarTopY - drawerHeight
        } else if pod.id == "music" {
            drawerHeight = 118.0
            originY = fullBarTopY - drawerHeight
        } else {
            drawerHeight = max(barHeight, 140.0)
            originY = visibleRect.minY + (visibleRect.height * (1.0 - CGFloat(pod.range.start + pod.range.length)))
        }

        // 0-gap edge alignment
        let originX: CGFloat = (pod.edge == .left)
            ? (visibleRect.minX + railWidth)
            : (visibleRect.maxX - railWidth - drawerWidth)

        let initialFrame = NSRect(
            x: originX,
            y: min(max(visibleRect.minY + 4, originY), visibleRect.maxY - drawerHeight - 4),
            width: drawerWidth,
            height: drawerHeight
        )
        self.targetFrame = initialFrame
        self.mountEdge = pod.edge

        let startX: CGFloat = (pod.edge == .left) ? (visibleRect.minX - drawerWidth) : (visibleRect.maxX)
        let offscreenFrame = NSRect(x: startX, y: initialFrame.origin.y, width: initialFrame.width, height: initialFrame.height)

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

    /// 执行纯水平 X 轴从边缘向中间弹出的物理弹簧动效 (绝无从下往上的垂直移动)
    public func presentWithSpring() {
        self.orderFront(nil)
        self.alphaValue = 0.5
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().setFrame(self.targetFrame, display: true)
            self.animator().alphaValue = 1.0
        }
    }
}
