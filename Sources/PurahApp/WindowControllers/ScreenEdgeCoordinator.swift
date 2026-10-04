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

    /// 严格独立控制左右侧边导轨展开状态，绝不联动推挤对侧窗口
    public func setRailExpanded(_ isExpanded: Bool, for edge: MountEdge) {
        if edge == .left {
            leftRailWindow?.setExpanded(isExpanded)
            rightRailWindow?.setExpanded(false)
        } else {
            rightRailWindow?.setExpanded(isExpanded)
            leftRailWindow?.setExpanded(false)
        }
    }

    public func syncDrawer(for edge: MountEdge? = nil) {
        if let targetEdge = edge ?? store.activePod?.edge {
            let hasActive = (store.activeDrawerItemId != nil || store.activeDrawerPodId != nil)
            setRailExpanded(hasActive, for: targetEdge)
        } else {
            dismissDrawer()
        }
    }

    public func dismissDrawer() {
        store.activeDrawerItemId = nil
        store.activeDrawerPodId = nil
        leftRailWindow?.setExpanded(false)
        rightRailWindow?.setExpanded(false)
    }
}
