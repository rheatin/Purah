// Sources/PurahApp/WindowControllers/DrawerPanelWindow.swift
import AppKit
import SwiftUI
import PurahCore
import PurahUI

@MainActor
public final class DrawerPanelWindow: NSPanel {
    public init(pod: SlotPod, screen: NSScreen, store: PurahWorkspaceStore, onClose: @escaping () -> Void) {
        let screenRect = screen.frame
        let drawerWidth = CGFloat(pod.drawerWidth)

        // 【关键要求】：展开内容的高度与该 Pod 在屏幕边缘的 Bar 物理高度严格一致
        let barHeight = CGFloat(pod.range.length) * screenRect.height
        let drawerHeight = max(barHeight, 140.0)

        // 严格以 Bar 的起始与终止物理坐标为基准对齐
        let originY = screenRect.minY + (screenRect.height * (1.0 - CGFloat(pod.range.start + pod.range.length)))

        // 抽屉无缝贴合屏幕物理边缘 (0 间隙)
        let originX: CGFloat = (pod.edge == .left)
            ? screenRect.minX
            : (screenRect.maxX - drawerWidth)

        let initialFrame = NSRect(x: originX, y: originY, width: drawerWidth, height: drawerHeight)

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
