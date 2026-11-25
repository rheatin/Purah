// Sources/PurahUI/Settings/LiveRailSculptorDockView.swift
import SwiftUI
import AppKit
import PurahCore

public struct LiveRailSculptorDockView: View {
    public let store: PurahWorkspaceStore
    @Environment(\.colorScheme) private var colorScheme

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    private var isDark: Bool { colorScheme == .dark }
    private var tokens: PurahSurfaceTokens { PurahSurfaceTokens(colorScheme: colorScheme) }
    private var accentInk: Color { palette.primaryAccent.adaptiveInk(for: colorScheme) }

    public init(
        store: PurahWorkspaceStore,
        onContentHeightChange: (@MainActor (CGFloat) -> Void)? = nil
    ) {
        self.store = store
    }

    public var body: some View {
        let isOnboarding = store.isOnboardingGuideActive
        let dockShape = RoundedRectangle(cornerRadius: 14, style: .continuous)

        VStack(alignment: .leading, spacing: 10) {
            if isOnboarding {
                OnboardingWorkbenchView(store: store)
                    .environment(\.colorScheme, .dark)
            } else {
                dockHeader

                Divider()
                    .background(isDark ? Color.white.opacity(0.15) : Color.black.opacity(0.10))

                // Row 2: Plugin Add / Unmounted Dock
                unmountedDock
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(width: isOnboarding ? 760 : 720)
        .background(
            ZStack {
                if isOnboarding || isDark {
                    dockShape
                        .fill(Color.black.opacity(isOnboarding ? 0.84 : 0.72))
                        .background(.ultraThinMaterial)
                        .clipShape(dockShape)
                } else {
                    dockShape
                        .fill(.regularMaterial)
                    dockShape
                        .fill(Color.white.opacity(0.72))
                }
            }
        )
        .overlay(
            ZStack {
                if !isOnboarding && !isDark {
                    dockShape
                        .strokeBorder(Color.white.opacity(0.80), lineWidth: 1.0)
                        .padding(0.75)
                }
                dockShape
                    .strokeBorder(
                        (isOnboarding || isDark) ? palette.primaryAccent.opacity(0.65) : accentInk.opacity(0.35),
                        lineWidth: 1.2
                    )
            }
        )
        .shadow(
            color: Color.black.opacity((isOnboarding || isDark) ? 0.45 : 0.14),
            radius: 16,
            x: 0,
            y: 6
        )
        .shadow(
            color: (isOnboarding || isDark) ? .clear : Color.black.opacity(0.06),
            radius: 3,
            x: 0,
            y: 1
        )
    }

    // MARK: - Dock Header

    /// Row 1: title, dynamic-breathing toggle, magic auto-layout, and Done.
    private var dockHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "scope")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(accentInk)

            Text("sculptor.dock.title".localized)
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .foregroundColor(tokens.hudPrimaryInk)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: 4)

            // Quick Dynamic Breathing Toggle
            Button {
                withAnimation(PurahMotionPolicy.surface) {
                    store.setDynamicBreathingEnabled(!store.isDynamicBreathingEnabled)
                    store.triggerControlHaptic(.alignment)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: store.isDynamicBreathingEnabled ? "lungs.fill" : "lungs")
                        .font(.system(size: 10, weight: .bold))
                    Text("overflow.breathing.toggleTitle".localized)
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .foregroundColor(store.isDynamicBreathingEnabled ? accentInk : .secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(store.isDynamicBreathingEnabled ? accentInk.opacity(isDark ? 0.18 : 0.12) : tokens.controlFill)
                .cornerRadius(6)
            }
            .buttonStyle(.tactile)
            .help("overflow.breathing.toggleSubtitle".localized)
            .accessibilityLabel("overflow.breathing.toggleSubtitle".localized)

            // Auto-Layout Button
            Button {
                withAnimation(PurahMotionPolicy.surface) {
                    store.autoLayoutAll()
                    store.triggerControlHaptic(.alignment)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .bold))
                    Text("sculptor.dock.autoLayout".localized)
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .fixedSize(horizontal: true, vertical: false)
                .foregroundColor(tokens.hudPrimaryInk)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(tokens.controlElevatedFill)
                .cornerRadius(6)
            }
            .buttonStyle(.tactile)

            // Prominent Done (Esc) Button
            Button {
                store.triggerControlHaptic(.levelChange)
                store.setLiveRailEditingMode(false)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text("sculptor.dock.done".localized)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .fixedSize(horizontal: true, vertical: false)
                .foregroundColor(palette.primaryAccent.highContrastInk)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(palette.primaryAccent)
                .cornerRadius(6)
            }
            .buttonStyle(.tactile)
            .keyboardShortcut(.cancelAction)
        }
    }

    // MARK: - Unmounted Dock

    @ViewBuilder
    private var unmountedDock: some View {
        let unmounted = store.pods.filter { !$0.isEnabled }

        if unmounted.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 11))
                    .foregroundColor(palette.primaryAccent)
                Text("sculptor.dock.allMounted".localized)
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                unmountedDockStatusLine

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(unmounted) { pod in
                            unmountedPodChip(pod)
                        }
                    }
                }
            }
        }
    }

    /// The hint above the chips: what a drag in flight will do, or the idle tip.
    @ViewBuilder
    private var unmountedDockStatusLine: some View {
        HStack(spacing: 6) {
            Text("sculptor.dock.unmounted".localized)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)

            Spacer(minLength: 4)

            if let draggedId = store.externalDraggedPodId,
               let draggedPod = store.pods.first(where: { $0.id == draggedId }) {
                if let targetPodId = store.externalDragTargetPodId,
                   let targetPod = store.pods.first(where: { $0.id == targetPodId }) {
                    Text(String(format: "sculptor.releaseToStackWith".localized, draggedPod.name, targetPod.name))
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundColor(.orange)
                } else if let targetEdge = store.externalDragTargetEdge {
                    Text("Release to mount \(draggedPod.name) on \(targetEdge == .left ? "Left" : "Right") rail")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundColor(palette.primaryAccent)
                } else {
                    Text(String(format: "sculptor.dragToRail".localized, draggedPod.name))
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .foregroundColor(tokens.hudPrimaryInk.opacity(0.85))
                }
            } else {
                Text("sculptor.dragTip".localized)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary.opacity(0.8))
            }
        }
    }

    /// One unmounted plugin chip: identity, mount buttons, and its drag-to-rail
    /// gesture.
    private func unmountedPodChip(_ pod: SlotPod) -> some View {
        let podColor = palette.podInkColor(for: pod.id, store: store, colorScheme: colorScheme)
        let isBeingDragged = (store.externalDraggedPodId == pod.id)

        return HStack(spacing: 5) {
            Image(systemName: pod.systemIcon)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundColor(podColor)

            Text(pod.name)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundColor(tokens.hudPrimaryInk)
                .lineLimit(1)

            Button {
                withAnimation(PurahMotionPolicy.surface) {
                    store.mountPod(id: pod.id, to: .left)
                    store.triggerControlHaptic(.alignment)
                }
            } label: {
                Text("+L")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(accentInk)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(accentInk.opacity(isDark ? 0.18 : 0.12))
                    .cornerRadius(4)
            }
            .buttonStyle(.tactile)
            .help(String(format: "help.mountLeftRail".localized, pod.name))
            .accessibilityLabel(String(format: "help.mountLeftRail".localized, pod.name))

            Button {
                withAnimation(PurahMotionPolicy.surface) {
                    store.mountPod(id: pod.id, to: .right)
                    store.triggerControlHaptic(.alignment)
                }
            } label: {
                Text("+R")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(accentInk)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(accentInk.opacity(isDark ? 0.18 : 0.12))
                    .cornerRadius(4)
            }
            .buttonStyle(.tactile)
            .help(String(format: "help.mountRightRail".localized, pod.name))
            .accessibilityLabel(String(format: "help.mountRightRail".localized, pod.name))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isBeingDragged ? podColor.opacity(isDark ? 0.26 : 0.16) : (isDark ? Color.white.opacity(0.08) : Color.white.opacity(0.75)))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(
                            isBeingDragged ? Color.orange : podColor.opacity(isDark ? 0.45 : 0.35),
                            lineWidth: isBeingDragged ? 1.6 : 1.0
                        )
                )
        )
        .scaleEffect(isBeingDragged ? 1.04 : 1.0)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 3, coordinateSpace: .global)
                .onChanged { _ in
                    let screenLoc = NSEvent.mouseLocation
                    let screenFrame = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
                    store.updateExternalPodDrag(
                        podId: pod.id,
                        screenPoint: screenLoc,
                        screenFrame: screenFrame
                    )
                }
                .onEnded { _ in
                    let screenFrame = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
                    withAnimation(PurahMotionPolicy.drawerEntrance) {
                        store.commitExternalPodDrag(
                            podId: pod.id,
                            screenFrame: screenFrame
                        )
                    }
                }
        )
    }
}
