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
    private var activeDrawerWindow: DrawerPanelWindow?
    private var currentDisplayedItemId: String?

    public var activeDrawerFrame: NSRect? {
        activeDrawerWindow?.frame
    }

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

    public func syncDrawer() {
        let activeId = store.activeDrawerItemId ?? store.activeDrawerPodId
        guard let activeId = activeId, let screen = NSScreen.screens.first ?? NSScreen.main else {
            dismissDrawer()
            return
        }

        // 查找所属 Pod
        let pod: SlotPod?
        if let p = store.pods.first(where: { $0.id == activeId }) {
            pod = p
        } else if store.todos.contains(where: { $0.id == activeId }) {
            pod = store.pods.first(where: { $0.id == "todo" })
        } else if store.calendarEvents.contains(where: { $0.id == activeId }) {
            pod = store.pods.first(where: { $0.id == "calendar" })
        } else {
            pod = nil
        }

        guard let pod = pod, pod.isEnabled else {
            dismissDrawer()
            return
        }

        if activeDrawerWindow == nil || currentDisplayedItemId != activeId {
            activeDrawerWindow?.orderOut(nil)
            activeDrawerWindow?.close()
            currentDisplayedItemId = activeId

            activeDrawerWindow = DrawerPanelWindow(
                pod: pod,
                screen: screen,
                store: store
            ) { [weak self] in
                self?.dismissDrawer()
            }
            activeDrawerWindow?.presentWithSpring()
        }
    }

    public func dismissDrawer() {
        store.activeDrawerItemId = nil
        store.activeDrawerPodId = nil
        currentDisplayedItemId = nil
        activeDrawerWindow?.orderOut(nil)
        activeDrawerWindow?.close()
        activeDrawerWindow = nil
    }
}
