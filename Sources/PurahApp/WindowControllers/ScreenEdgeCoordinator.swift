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

        rightRailWindow = AmbientRailWindow(edge: .right, screen: screen, store: store)
        rightRailWindow?.orderFront(nil)
    }

    public func updateRailWidths() {
        leftRailWindow?.updateWidth()
        rightRailWindow?.updateWidth()
    }

    /// 同步并展现单项抽屉：完全由 AmbientRailStripView 在同窗口内 0 间隙弹簧滑出，绝不创建多余浮动子窗口
    public func syncDrawer(for edge: MountEdge? = nil) {
        // 状态由 store 响应式驱动
    }

    public func dismissDrawer() {
        store.activeDrawerItemId = nil
        store.activeDrawerPodId = nil
        store.hoveredPodId = nil
    }
}
