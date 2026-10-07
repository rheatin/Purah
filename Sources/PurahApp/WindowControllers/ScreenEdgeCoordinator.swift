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
    public private(set) var activeScreen: NSScreen?
    public private(set) var isFrozen: Bool = false

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

    public func targetScreen(for point: NSPoint? = nil) -> NSScreen? {
        let all = NSScreen.screens
        guard !all.isEmpty else { return nil }

        switch store.displayTargetMode {
        case .followCursor:
            if let point = point {
                return all.first { $0.frame.insetBy(dx: -2, dy: -2).contains(point) } ?? activeScreen ?? NSScreen.main ?? all.first
            } else {
                let loc = NSEvent.mouseLocation
                return all.first { $0.frame.insetBy(dx: -2, dy: -2).contains(loc) } ?? activeScreen ?? NSScreen.main ?? all.first
            }
        case .primaryOnly:
            return all.first
        case .externalOnly:
            return all.count > 1 ? all[1] : all.first
        }
    }

    public func updateActiveScreenIfNeeded(for point: NSPoint) {
        guard store.displayTargetMode == .followCursor else { return }
        guard let newScreen = targetScreen(for: point), newScreen != activeScreen else { return }
        relocateToScreen(newScreen)
    }

    public func relocateToScreen(_ screen: NSScreen) {
        self.activeScreen = screen
        leftRailWindow?.relocate(to: screen)
        rightRailWindow?.relocate(to: screen)
    }

    public func rebuildWindows() {
        guard let screen = targetScreen() ?? NSScreen.main ?? NSScreen.screens.first else { return }
        self.activeScreen = screen
        leftRailWindow?.close()
        rightRailWindow?.close()

        leftRailWindow = AmbientRailWindow(edge: .left, screen: screen, store: store)
        leftRailWindow?.orderFront(nil)

        rightRailWindow = AmbientRailWindow(edge: .right, screen: screen, store: store)
        rightRailWindow?.orderFront(nil)

        if isFrozen {
            leftRailWindow?.alphaValue = 0.0
            rightRailWindow?.alphaValue = 0.0
            leftRailWindow?.ignoresMouseEvents = true
            rightRailWindow?.ignoresMouseEvents = true
        }
    }

    public func setFrozen(_ isFrozen: Bool) {
        self.isFrozen = isFrozen
        if isFrozen {
            dismissDrawer(for: nil)
            leftRailWindow?.animator().alphaValue = 0.0
            rightRailWindow?.animator().alphaValue = 0.0
            leftRailWindow?.ignoresMouseEvents = true
            rightRailWindow?.ignoresMouseEvents = true
        } else {
            leftRailWindow?.animator().alphaValue = 1.0
            rightRailWindow?.animator().alphaValue = 1.0
            // 默认窗口严格保持全透明穿透态 (ignoresMouseEvents = true)，仅由 2D 碰撞检测在卡片内开启交互
            leftRailWindow?.ignoresMouseEvents = true
            rightRailWindow?.ignoresMouseEvents = true
        }
    }

    public func updateRailWidths() {
        leftRailWindow?.updateWidth()
        rightRailWindow?.updateWidth()
    }

    public func setInteractive(_ interactive: Bool, for edge: MountEdge) {
        guard !isFrozen else { return }
        if edge == .left {
            leftRailWindow?.setInteractive(interactive)
        } else {
            rightRailWindow?.setInteractive(interactive)
        }
    }

    /// Synchronizes drawer presentation on the unified rail window canvas
    public func syncDrawer(for edge: MountEdge? = nil) {
        guard !isFrozen else { return }
        if let edge = edge {
            setInteractive(true, for: edge)
        }
    }

    public func dismissDrawer(for edge: MountEdge? = nil) {
        if let edge = edge {
            let activeId = store.activeDrawerItemId ?? store.activeDrawerPodId
            let pod = activeId.flatMap { store.pod(forItemId: $0) }
            let isCurrentOnEdge = (pod?.edge == edge) || (store.activePod?.edge == edge) || (store.activeDrawerPodId != nil)
            let isPinned = activeId.map { store.isItemPinned(id: $0) } ?? false

            if isCurrentOnEdge && !isPinned {
                withAnimation(.spring(response: 0.18, dampingFraction: 0.90)) {
                    store.activeDrawerItemId = nil
                    store.activeDrawerPodId = nil
                    store.hoveredPodId = nil
                }
            }
            // 抽屉收回后默认将窗口置为全穿透态，光标在卡片外绝不截留鼠标事件
            setInteractive(false, for: edge)
            EdgeMouseMonitor.shared?.resetEdgeState()
        } else {
            withAnimation(.spring(response: 0.18, dampingFraction: 0.90)) {
                store.activeDrawerItemId = nil
                store.activeDrawerPodId = nil
                store.hoveredPodId = nil
            }
            setInteractive(false, for: .left)
            setInteractive(false, for: .right)
            EdgeMouseMonitor.shared?.resetEdgeState()
        }
    }
}
