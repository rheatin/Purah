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
    nonisolated(unsafe) private var screenChangeObserver: (any NSObjectProtocol)?

    public init(store: PurahWorkspaceStore) {
        self.store = store
        setupScreenNotifications()
        rebuildWindows()
    }

    deinit {
        if let observer = screenChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func setupScreenNotifications() {
        screenChangeObserver = NotificationCenter.default.addObserver(
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

        let leftEnabled = store.pods.contains { $0.edge == .left && $0.isEnabled }
        let rightEnabled = store.pods.contains { $0.edge == .right && $0.isEnabled }

        // Smart single-rail sleep: close and release window if rail has zero enabled pods
        if leftEnabled {
            if let existing = leftRailWindow {
                existing.relocate(to: screen)
            } else {
                let win = AmbientRailWindow(edge: .left, screen: screen, store: store)
                leftRailWindow = win
            }
            leftRailWindow?.orderFront(nil)
        } else {
            leftRailWindow?.close()
            leftRailWindow = nil
        }

        if rightEnabled {
            if let existing = rightRailWindow {
                existing.relocate(to: screen)
            } else {
                let win = AmbientRailWindow(edge: .right, screen: screen, store: store)
                rightRailWindow = win
            }
            rightRailWindow?.orderFront(nil)
        } else {
            rightRailWindow?.close()
            rightRailWindow = nil
        }

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
            // Windows maintain full pass-through by default (ignoresMouseEvents = true), enabled only when cursor is inside cards
            leftRailWindow?.ignoresMouseEvents = true
            rightRailWindow?.ignoresMouseEvents = true
        }
    }

    public func updateRailWidths() {
        leftRailWindow?.updateWidth()
        rightRailWindow?.updateWidth()
    }

    /// Dynamically expands rail canvas from 28pt compact docked width to full drawer canvas width (580pt)
    public func expandCanvas(for edge: MountEdge) {
        guard !isFrozen else { return }
        if edge == .left {
            leftRailWindow?.setExpanded(true)
            leftRailWindow?.setInteractive(true)
        } else {
            rightRailWindow?.setExpanded(true)
            rightRailWindow?.setInteractive(true)
        }
    }

    /// Dynamically collapses rail canvas back to 28pt compact width when drawers retract, saving ~20MB framebuffer memory
    public func collapseCanvas(for edge: MountEdge) {
        let hasActive = (store.activePod?.edge == edge) && (store.activeDrawerPodId != nil || store.activeDrawerItemId != nil)
        let hasPinned = store.hasPinnedItem(on: edge)
        guard !hasActive && !hasPinned else { return }

        if edge == .left {
            leftRailWindow?.setExpanded(false)
            leftRailWindow?.setInteractive(false)
        } else {
            rightRailWindow?.setExpanded(false)
            rightRailWindow?.setInteractive(false)
        }
    }

    public func setInteractive(_ interactive: Bool, for edge: MountEdge) {
        guard !isFrozen else { return }
        if interactive {
            expandCanvas(for: edge)
        } else {
            if edge == .left {
                leftRailWindow?.setInteractive(false)
            } else {
                rightRailWindow?.setInteractive(false)
            }
        }
    }

    /// Synchronizes drawer presentation on the unified rail window canvas
    public func syncDrawer(for edge: MountEdge? = nil) {
        guard !isFrozen else { return }
        if let edge = edge {
            expandCanvas(for: edge)
        }
    }

    public func dismissDrawer(for edge: MountEdge? = nil) {
        let targetEdges: [MountEdge] = (edge != nil) ? [edge!] : [.left, .right]

        for targetEdge in targetEdges {
            let activeId = store.activeDrawerItemId ?? store.activeDrawerPodId
            let pod = activeId.flatMap { store.pod(forItemId: $0) }
            let isCurrentOnEdge = (pod?.edge == targetEdge) || (store.activePod?.edge == targetEdge) || (store.activeDrawerPodId != nil)
            let isPinned = activeId.map { store.isItemPinned(id: $0) } ?? false

            if isCurrentOnEdge && !isPinned {
                withAnimation(.spring(response: 0.18, dampingFraction: 0.90)) {
                    store.activeDrawerItemId = nil
                    store.activeDrawerPodId = nil
                    store.hoveredPodId = nil
                }
            }
            // Reset window to pass-through after drawer retraction so clicks pass directly to underlying apps
            setInteractive(false, for: targetEdge)
            EdgeMouseMonitor.shared?.resetEdgeState()

            // Smoothly collapse window canvas back to compact 28pt width once drawer is tucked inside bezel
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
                self?.collapseCanvas(for: targetEdge)
            }
        }
    }
}
