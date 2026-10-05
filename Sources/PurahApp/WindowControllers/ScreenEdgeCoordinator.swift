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
        // Prefer current active screen NSScreen.main
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

    public func setInteractive(_ interactive: Bool, for edge: MountEdge) {
        if edge == .left {
            leftRailWindow?.setInteractive(interactive)
        } else {
            rightRailWindow?.setInteractive(interactive)
        }
    }

    /// Synchronizes drawer presentation on the unified rail window canvas
    public func syncDrawer(for edge: MountEdge? = nil) {
        if let edge = edge {
            setInteractive(true, for: edge)
        }
    }

    public func dismissDrawer() {
        store.activeDrawerItemId = nil
        store.activeDrawerPodId = nil
        store.hoveredPodId = nil

        let hasLeftPinned = store.pods.contains { $0.edge == .left && store.isItemPinned(id: $0.id) } || store.isDrawerPinned
        let hasRightPinned = store.pods.contains { $0.edge == .right && store.isItemPinned(id: $0.id) } || store.isDrawerPinned
        setInteractive(hasLeftPinned, for: .left)
        setInteractive(hasRightPinned, for: .right)
    }
}
