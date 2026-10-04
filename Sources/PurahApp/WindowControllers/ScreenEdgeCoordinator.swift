// Sources/PurahApp/WindowControllers/ScreenEdgeCoordinator.swift
import AppKit
import SwiftUI
import PurahCore
import PurahUI

@MainActor
public final class ScreenEdgeCoordinator {
    private let store: PurahWorkspaceStore
    private var leftRailWindow: AmbientRailWindow?
    private var rightRailWindow: AmbientRailWindow?

    public init(store: PurahWorkspaceStore) {
        self.store = store
        setupScreenNotifications()
        rebuildWindows()
    }

    private func setupScreenNotifications() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.rebuildWindows()
            }
        }
    }

    public func rebuildWindows() {
        // 优先使用当前用户活跃屏幕 NSScreen.main
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        leftRailWindow?.close()
        rightRailWindow?.close()

        leftRailWindow = AmbientRailWindow(edge: .left, screen: screen, store: store)
        leftRailWindow?.orderFront(nil)
        leftRailWindow?.setExpanded(false)

        rightRailWindow = AmbientRailWindow(edge: .right, screen: screen, store: store)
        rightRailWindow?.orderFront(nil)
        rightRailWindow?.setExpanded(false)
    }

    public func updateRailWidths() {
        leftRailWindow?.updateWidth()
        rightRailWindow?.updateWidth()
    }

    public func expandRail(for edge: MountEdge) {
        if edge == .left {
            leftRailWindow?.setExpanded(true)
        } else {
            rightRailWindow?.setExpanded(true)
        }
    }

    public func collapseRail(for edge: MountEdge) {
        let isLeftPinned = store.isDrawerPinned || store.pinnedDrawerItemIds.contains(where: { store.pod(forItemId: $0)?.edge == .left })
        let isRightPinned = store.isDrawerPinned || store.pinnedDrawerItemIds.contains(where: { store.pod(forItemId: $0)?.edge == .right })
        if edge == .left && !isLeftPinned {
            leftRailWindow?.setExpanded(false)
        } else if edge == .right && !isRightPinned {
            rightRailWindow?.setExpanded(false)
        }
    }

    /// 同步并展现单项抽屉：完全由 AmbientRailStripView 在同窗口内 0 间隙弹簧滑出，绝不创建多余浮动子窗口
    public func syncDrawer(for edge: MountEdge? = nil) {
        if let edge = edge {
            expandRail(for: edge)
        }
    }

    public func dismissDrawer() {
        store.activeDrawerItemId = nil
        store.activeDrawerPodId = nil
        store.hoveredPodId = nil
        collapseRail(for: .left)
        collapseRail(for: .right)
    }
}
