// Sources/PurahApp/WindowControllers/ScreenEdgeCoordinator.swift
import AppKit
import SwiftUI
import PurahCore
import PurahUI

@MainActor
private final class SculptorDockPanel: NSPanel {
    private let store: PurahWorkspaceStore

    init(contentRect: NSRect, store: PurahWorkspaceStore) {
        self.store = store
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown && event.keyCode == 53 && store.isLiveRailEditingMode {
            store.setLiveRailEditingMode(false)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

@MainActor
public final class ScreenEdgeCoordinator {
    private let store: PurahWorkspaceStore
    private var leftRailWindow: AmbientRailWindow?
    private var rightRailWindow: AmbientRailWindow?
    private var sculptorDockWindow: NSPanel?
    public private(set) var activeScreen: NSScreen?
    public private(set) var isFrozen: Bool = false
    private var isDismissingEdge: [MountEdge: Bool] = [:]
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
                let loc = EdgeMouseMonitor.isTestingEnvironment ? (all.first?.frame.origin ?? .zero) : NSEvent.mouseLocation
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

        let isLiveEditing = store.isLiveRailEditingMode
        let isSculptingRails = isLiveEditing && !store.isRehearsingBreathingInSculptor
        let leftEnabled = isLiveEditing || store.pods.contains { $0.edge == .left && $0.isEnabled }
        let rightEnabled = isLiveEditing || store.pods.contains { $0.edge == .right && $0.isEnabled }

        // Smart single-rail sleep: close and release window if rail has zero enabled pods (unless in Live Rail Sculptor mode)
        if leftEnabled {
            if let existing = leftRailWindow {
                existing.relocate(to: screen)
            } else {
                let win = AmbientRailWindow(edge: .left, screen: screen, store: store)
                leftRailWindow = win
            }
            if isSculptingRails {
                leftRailWindow?.setExpanded(true)
                leftRailWindow?.setInteractive(true)
            } else if !store.hasPinnedItem(on: .left) && store.activePod?.edge != .left {
                leftRailWindow?.setExpanded(false)
                leftRailWindow?.setInteractive(false)
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
            if isSculptingRails {
                rightRailWindow?.setExpanded(true)
                rightRailWindow?.setInteractive(true)
            } else if !store.hasPinnedItem(on: .right) && store.activePod?.edge != .right {
                rightRailWindow?.setExpanded(false)
                rightRailWindow?.setInteractive(false)
            }
            rightRailWindow?.orderFront(nil)
        } else {
            rightRailWindow?.close()
            rightRailWindow = nil
        }

        if isLiveEditing {
            let visibleRect = screen.visibleFrame
            let dockWidth: CGFloat = store.isOnboardingGuideActive ? 780 : 720
            let dockHeight: CGFloat = store.isOnboardingGuideActive ? 285 : 96
            let dockX = visibleRect.midX - (dockWidth * 0.5)
            let dockY = visibleRect.maxY - dockHeight - 14
            let dockFrame = NSRect(x: dockX, y: dockY, width: dockWidth, height: dockHeight)

            if let existingDock = sculptorDockWindow {
                existingDock.setFrame(dockFrame, display: true)
            } else {
                let panel = SculptorDockPanel(contentRect: dockFrame, store: store)
                panel.contentView = NSHostingView(rootView: LiveRailSculptorDockView(store: store))
                sculptorDockWindow = panel
            }
            sculptorDockWindow?.makeKeyAndOrderFront(nil)
        } else {
            sculptorDockWindow?.orderOut(nil)
            sculptorDockWindow = nil
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
        isDismissingEdge[edge] = false
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
        guard isDismissingEdge[edge] != true else { return }
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
            expandCanvas(for: edge)
        }
    }

    public func dismissDrawer(for edge: MountEdge? = nil) {
        let targetEdges: [MountEdge] = (edge != nil) ? [edge!] : [.left, .right]

        for targetEdge in targetEdges {
            let activeId = store.activeDrawerItemId ?? store.activeDrawerPodId
            let pod = activeId.flatMap { store.pod(forItemId: $0) }
            let isCurrentOnEdge = (pod?.edge == targetEdge) || (store.activePod?.edge == targetEdge)
            let isPinned = activeId.map { store.isItemPinned(id: $0) } ?? false

            if isCurrentOnEdge && !isPinned {
                isDismissingEdge[targetEdge] = true
                store.onDismissPreviewPanel?()
                store.activePreviewScreenFrame = nil
                withAnimation(.spring(response: 0.30, dampingFraction: 0.80, blendDuration: 0.08)) {
                    store.activeDrawerItemId = nil
                    store.activeDrawerPodId = nil
                    store.hoveredPodId = nil
                    store.invalidateLayoutCache()
                }
            } else if let hoveredId = store.hoveredPodId,
                      store.pod(forItemId: hoveredId)?.edge == targetEdge {
                withAnimation(.spring(response: 0.30, dampingFraction: 0.80, blendDuration: 0.08)) {
                    store.hoveredPodId = nil
                    store.invalidateLayoutCache()
                }
            }
            // Reset window to pass-through after drawer retraction so clicks pass directly to underlying apps
            setInteractive(false, for: targetEdge)
            EdgeMouseMonitor.shared?.resetEdgeState()

            // Smoothly collapse window canvas back to compact 28pt width once drawer is 100% tucked inside bezel (~160ms animation + 140ms safe buffer = 300ms)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) { [weak self] in
                self?.isDismissingEdge[targetEdge] = false
                self?.collapseCanvas(for: targetEdge)
            }
        }
    }
}
