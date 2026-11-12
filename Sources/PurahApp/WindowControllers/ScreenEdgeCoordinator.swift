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

/// One click-through surface for the onboarding focus frame. It never becomes
/// key and never receives a mouse event; all interaction stays in the control
/// being framed.
@MainActor
private final class OnboardingCalloutPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
public final class ScreenEdgeCoordinator {
    private let store: PurahWorkspaceStore
    private var leftRailWindow: AmbientRailWindow?
    private var rightRailWindow: AmbientRailWindow?
    private var sculptorDockWindow: NSPanel?
    private var sculptorDockMeasuredHeight: CGFloat = 0
    private var onboardingCalloutWindow: NSPanel?
    private var appliedOnboardingCallout: AppliedOnboardingCallout?
    public private(set) var activeScreen: NSScreen?
    public private(set) var isFrozen: Bool = false
    private var isDismissingEdge: [MountEdge: Bool] = [:]
    private var collapseTasks: [MountEdge: Task<Void, Never>] = [:]
    nonisolated(unsafe) private var screenChangeObserver: (any NSObjectProtocol)?

    public init(store: PurahWorkspaceStore) {
        self.store = store
        setupScreenNotifications()
        rebuildWindows()
        observeOnboardingCallout()
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
                EdgeMouseMonitor.updateCachedScreenEdges()
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
                return all.first { $0.frame.contains(point) } ?? all.first { $0.frame.insetBy(dx: -2, dy: -2).contains(point) } ?? activeScreen ?? NSScreen.main ?? all.first
            } else {
                let loc = EdgeMouseMonitor.isTestingEnvironment ? (all.first?.frame.origin ?? .zero) : NSEvent.mouseLocation
                return all.first { $0.frame.contains(loc) } ?? all.first { $0.frame.insetBy(dx: -2, dy: -2).contains(loc) } ?? activeScreen ?? NSScreen.main ?? all.first
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
        let isSculptingRails = isLiveEditing
            && !store.isRehearsingBreathingInSculptor
            && !store.isOnboardingGuideShowingAmbientRail
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
            let dockWidth: CGFloat = store.isOnboardingGuideActive ? 760 : 720
            let dockHeight: CGFloat = store.isOnboardingGuideActive ? 430 : 96
            let dockX = visibleRect.midX - (dockWidth * 0.5)
            let dockY = store.isOnboardingGuideActive
                ? max(visibleRect.midY - (dockHeight * 0.5), visibleRect.minY + 20)
                : visibleRect.maxY - dockHeight - 14
            let dockFrame = NSRect(x: dockX, y: dockY, width: dockWidth, height: dockHeight)

            if let existingDock = sculptorDockWindow {
                existingDock.setFrame(dockFrame, display: true)
            } else {
                let panel = SculptorDockPanel(contentRect: dockFrame, store: store)
                panel.contentView = NSHostingView(rootView: LiveRailSculptorDockView(store: store) { [weak self] contentHeight in
                    self?.applySculptorDockContentHeight(contentHeight)
                })
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

        applyOnboardingCalloutTarget()
    }

    /// The guide dock is content-sized. The SwiftUI view measures its own
    /// ideal height (it is vertically `fixedSize` while the guide is active)
    /// and this keeps the AppKit panel — and its top edge — in step with it.
    ///
    /// The measurement is the truth: compare it against the panel's actual
    /// frame rather than a memo of the last value. The memo used to stand in
    /// front of `setFrame`, so a step whose measured height happened to match
    /// a stale memo (or arrived while `rebuildWindows` was mid-flight) never
    /// reached the window.
    private func applySculptorDockContentHeight(_ contentHeight: CGFloat) {
        guard store.isLiveRailEditingMode, store.isOnboardingGuideActive else { return }
        guard let screen = activeScreen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let visibleRect = screen.visibleFrame
        let clampedHeight = max(min(contentHeight, visibleRect.height - 60), 140)
        sculptorDockMeasuredHeight = clampedHeight
        guard let panel = sculptorDockWindow else { return }
        let dockWidth: CGFloat = 760
        let dockX = visibleRect.midX - (dockWidth * 0.5)
        let dockY = visibleRect.maxY - clampedHeight - 14
        guard abs(panel.frame.height - clampedHeight) > 0.01
            || abs(panel.frame.origin.y - dockY) > 0.01
            || abs(panel.frame.origin.x - dockX) > 0.01 else { return }
        panel.setFrame(
            NSRect(x: dockX, y: dockY, width: dockWidth, height: clampedHeight),
            display: true
        )
    }

    // MARK: - Onboarding focus frame

    private struct AppliedOnboardingCallout: Equatable {
        var layout: OnboardingFocusLayout
        var labelText: String
        var accentHex: String?
        var reduceMotion: Bool
    }

    /// The frame is drawn by the app shell, not by the rail or dock that owns
    /// the control, so it can extend past a 28pt rail window without clipping.
    private func observeOnboardingCallout() {
        withObservationTracking {
            _ = store.onboardingCalloutTarget
            _ = store.isOnboardingGuideActive
            _ = store.isLiveRailEditingMode
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.applyOnboardingCalloutTarget()
                self.observeOnboardingCallout()
            }
        }
    }

    private func applyOnboardingCalloutTarget() {
        guard let target = store.onboardingCalloutTarget,
              store.isOnboardingGuideActive,
              store.isLiveRailEditingMode,
              let screen = NSScreen.screens.first(where: { $0.frame.intersects(target.screenRect) })
                ?? activeScreen
                ?? NSScreen.main
        else {
            onboardingCalloutWindow?.orderOut(nil)
            appliedOnboardingCallout = nil
            return
        }

        let visible = screen.visibleFrame
        let labelText = target.labelKey.localized
        let layout = OnboardingFocusFrameGeometry.layout(
            targetScreenRect: target.screenRect,
            visibleScreenRect: visible,
            labelSize: OnboardingFocusLabelMetrics.pillSize(for: labelText),
            preferredSide: target.sideCandidate,
            arrow: target.arrow
        )
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let applied = AppliedOnboardingCallout(
            layout: layout,
            labelText: labelText,
            accentHex: target.accentHex,
            reduceMotion: reduceMotion
        )

        let panel = onboardingCalloutWindow ?? makeOnboardingCalloutWindow()
        if appliedOnboardingCallout != applied {
            panel.contentView = NSHostingView(
                rootView: OnboardingFocusFrameView(
                    layout: layout,
                    labelText: labelText,
                    accentHex: target.accentHex,
                    reduceMotion: reduceMotion
                )
            )
            appliedOnboardingCallout = applied
        }

        let frame = OnboardingFocusFrameGeometry.appKitRect(layout.calloutBounds, in: visible)
        if abs(panel.frame.minX - frame.minX) > 0.01
            || abs(panel.frame.minY - frame.minY) > 0.01
            || abs(panel.frame.width - frame.width) > 0.01
            || abs(panel.frame.height - frame.height) > 0.01 {
            panel.setFrame(frame, display: true)
        }
        panel.orderFrontRegardless()
    }

    private func makeOnboardingCalloutWindow() -> NSPanel {
        let panel = OnboardingCalloutPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: EmptyView())
        onboardingCalloutWindow = panel
        return panel
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

    /// Dynamically expands rail canvas from 28pt compact docked width to full drawer canvas width (580pt)
    public func expandCanvas(for edge: MountEdge) {
        guard !isFrozen else { return }
        collapseTasks[edge]?.cancel()
        collapseTasks[edge] = nil
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

    /// Returns whether the rail window canvas for the given edge is currently expanded
    public func isCanvasExpanded(for edge: MountEdge) -> Bool {
        if edge == .left {
            return leftRailWindow?.isExpanded ?? false
        } else {
            return rightRailWindow?.isExpanded ?? false
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
                store.activeDropdownScreenFrame = nil
                withAnimation(.spring(response: 0.20, dampingFraction: 0.92)) {
                    store.activeDrawerItemId = nil
                    store.activeDrawerPodId = nil
                    store.hoveredPodId = nil
                    store.invalidateLayoutCache()
                }
            } else if let hoveredId = store.hoveredPodId,
                      store.pod(forItemId: hoveredId)?.edge == targetEdge {
                withAnimation(.spring(response: 0.20, dampingFraction: 0.92)) {
                    store.hoveredPodId = nil
                    store.invalidateLayoutCache()
                }
            }
            // Reset window to pass-through after drawer retraction so clicks pass directly to underlying apps
            setInteractive(false, for: targetEdge)
            EdgeMouseMonitor.shared?.resetEdgeState()

            // Smoothly collapse window canvas back to compact 28pt width once drawer is 100% tucked inside bezel (~160ms animation + 140ms safe buffer = 300ms)
            collapseTasks[targetEdge]?.cancel()
            collapseTasks[targetEdge] = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled, let self = self else { return }
                self.isDismissingEdge[targetEdge] = false
                self.collapseTasks[targetEdge] = nil
                self.collapseCanvas(for: targetEdge)
            }
        }
    }
}
