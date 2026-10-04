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
        guard let screen = NSScreen.screens.first ?? NSScreen.main else { return }
        leftRailWindow?.close()
        rightRailWindow?.close()

        leftRailWindow = AmbientRailWindow(edge: .left, screen: screen, store: store)
        leftRailWindow?.orderFront(nil)

        rightRailWindow = AmbientRailWindow(edge: .right, screen: screen, store: store)
        rightRailWindow?.orderFront(nil)
    }

    public func setRailExpanded(_ isExpanded: Bool, for edge: MountEdge? = nil) {
        if edge == nil || edge == .left {
            leftRailWindow?.setExpanded(isExpanded)
        }
        if edge == nil || edge == .right {
            rightRailWindow?.setExpanded(isExpanded)
        }
    }

    public func syncDrawer() {
        // 单项物理抽屉直接在 AmbientRailWindow 中呈现一体化滑动
        let hasActive = (store.activeDrawerItemId != nil || store.activeDrawerPodId != nil)
        setRailExpanded(hasActive)
    }

    public func dismissDrawer() {
        store.activeDrawerItemId = nil
        store.activeDrawerPodId = nil
        setRailExpanded(false)
    }
}
