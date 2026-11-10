// Sources/PurahUI/Settings/LiveRailSculptorDockView.swift
import SwiftUI
import AppKit
import PurahCore

private struct SculptorDockContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

public struct LiveRailSculptorDockView: View {
    public let store: PurahWorkspaceStore
    public var onContentHeightChange: (@MainActor (CGFloat) -> Void)?

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    public init(
        store: PurahWorkspaceStore,
        onContentHeightChange: (@MainActor (CGFloat) -> Void)? = nil
    ) {
        self.store = store
        self.onContentHeightChange = onContentHeightChange
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if store.isOnboardingGuideActive {
                onboardingCoachHUD
            } else {
                dockHeader
            }

            Divider()
                .background(Color.white.opacity(0.15))

            // Row 2: Plugin Add / Unmounted Dock
            unmountedDock
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(width: store.isOnboardingGuideActive ? 760 : 720)
        // The guide dock grows with its content. The panel asks this view for
        // its ideal height instead of compressing a fixed 245/285pt box, which
        // is what let four unmounted chips stack over the mission row.
        .fixedSize(horizontal: false, vertical: store.isOnboardingGuideActive)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.72))
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    store.isOnboardingGuideActive
                        ? Color.white.opacity(0.12)
                        : palette.primaryAccent.opacity(0.65),
                    lineWidth: 1.4
                )
        )
        .shadow(color: Color.black.opacity(0.45), radius: 14, x: 0, y: 6)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: SculptorDockContentHeightKey.self,
                    value: proxy.size.height
                )
            }
        )
        .onPreferenceChange(SculptorDockContentHeightKey.self) { height in
            guard store.isOnboardingGuideActive, height > 0 else { return }
            onContentHeightChange?(height)
        }
    }

    // MARK: - Dock Header

    /// Row 1: title, dynamic-breathing toggle, magic auto-layout, and Done.
    private var dockHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "scope")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(palette.primaryAccent)

            Text("sculptor.dock.title".localized)
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .foregroundColor(.white)
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
                .foregroundColor(store.isDynamicBreathingEnabled ? palette.primaryAccent : .secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(store.isDynamicBreathingEnabled ? palette.primaryAccent.opacity(0.18) : Color.white.opacity(0.08))
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
                .foregroundColor(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.14))
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
                .foregroundColor(.black)
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

                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(unmounted) { pod in
                                unmountedPodChip(pod)
                                    .id(pod.id)
                            }
                        }
                    }
                    .onAppear { scrollMountTarget(into: proxy, unmounted: unmounted) }
                    .onChange(of: store.onboardingTarget) { _, _ in
                        scrollMountTarget(into: proxy, unmounted: unmounted)
                    }
                    .onChange(of: unmounted.map(\.id)) { _, _ in
                        scrollMountTarget(into: proxy, unmounted: unmounted)
                    }
                }
                // Pin the scrolling row to one chip height. The ScrollView's
                // ideal height follows its content, so the dock's measured
                // height would otherwise change with the number of unmounted
                // chips — and round a few points short, drawing the row over
                // the panel's bottom edge. Scrolling is horizontal only.
                .frame(height: 30)
            }
        }
    }

    /// The mount step's callout frames a button inside this row. The row
    /// scrolls horizontally, so the target has to be brought on screen or the
    /// frame would be drawn over whichever chip happens to sit at the edge.
    private func scrollMountTarget(into proxy: ScrollViewProxy, unmounted: [SlotPod]) {
        guard store.isOnboardingGuideActive,
              store.onboardingStep == .firstPod,
              case .dockButton(let podId, _) = store.onboardingTarget,
              unmounted.contains(where: { $0.id == podId }) else { return }
        withAnimation(PurahMotionPolicy.surface) {
            proxy.scrollTo(podId, anchor: .center)
        }
    }

    /// The hint above the chips: what a drag in flight will do, or the idle tip.
    @ViewBuilder
    private var unmountedDockStatusLine: some View {
        let isMountStep = store.isOnboardingGuideActive && store.onboardingStep == .firstPod

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
                        .foregroundColor(.white.opacity(0.85))
                }
            } else if isMountStep, case .dockButton(let podId, let edge) = store.onboardingTarget {
                let podName = store.pods.first(where: { $0.id == podId })?.name ?? podId
                Text(String(
                    format: (edge == .left ? "help.mountLeftRail" : "help.mountRightRail").localized,
                    podName
                ))
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .foregroundColor(palette.primaryAccent)
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
        let podColor = palette.podColor(for: pod.id, store: store)
        let isBeingDragged = (store.externalDraggedPodId == pod.id)
        let isMountStep = store.isOnboardingGuideActive && store.onboardingStep == .firstPod
        let dockTarget: (podId: String, edge: MountEdge)? = {
            guard isMountStep, case .dockButton(let podId, let edge) = store.onboardingTarget else {
                return nil
            }
            return (podId, edge)
        }()
        let isTargetChip = (dockTarget?.podId == pod.id)
        let isTargetLeftButton = isTargetChip && dockTarget?.edge == .left
        let isTargetRightButton = isTargetChip && dockTarget?.edge == .right

        let chip = HStack(spacing: 5) {
            Image(systemName: pod.systemIcon)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundColor(podColor)

            Text(pod.name)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)

            Button {
                withAnimation(PurahMotionPolicy.surface) {
                    store.mountPod(id: pod.id, to: .left)
                    store.triggerControlHaptic(.alignment)
                }
            } label: {
                Text("+L")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(palette.primaryAccent)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(palette.primaryAccent.opacity(0.18))
                    .cornerRadius(4)
            }
            .buttonStyle(.tactile)
            .onboardingCalloutAnchor(
                store: store,
                owner: "dock-mount-left-\(pod.id)",
                step: .firstPod,
                isActive: isTargetLeftButton,
                labelKey: "onboarding.callout.clickHere",
                side: .below,
                arrow: .up
            )
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
                    .foregroundColor(palette.primaryAccent)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(palette.primaryAccent.opacity(0.18))
                    .cornerRadius(4)
            }
            .buttonStyle(.tactile)
            .onboardingCalloutAnchor(
                store: store,
                owner: "dock-mount-right-\(pod.id)",
                step: .firstPod,
                isActive: isTargetRightButton,
                labelKey: "onboarding.callout.clickHere",
                side: .below,
                arrow: .up
            )
            .help(String(format: "help.mountRightRail".localized, pod.name))
            .accessibilityLabel(String(format: "help.mountRightRail".localized, pod.name))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isBeingDragged ? podColor.opacity(0.26) : Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(
                            isBeingDragged ? Color.orange : podColor.opacity(0.45),
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

        return chip
    }

    // MARK: - Onboarding Coach HUD

    @ViewBuilder
    private var onboardingCoachHUD: some View {
        let enabledCount = store.pods.filter(\.isEnabled).count
        let isThinBuild = enabledCount < 6
        let isMissionComplete = store.isCurrentOnboardingMissionCompleted

        VStack(alignment: .leading, spacing: 9) {
            // Header Row: Step badge, 6 dots, Spacer, Skip All button
            HStack(spacing: 10) {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .bold))
                    Text(String(
                        format: "onboarding.stepCounter".localized,
                        store.onboardingStep.rawValue + 1,
                        OnboardingGuideStep.allCases.count
                    ))
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                }
                .foregroundColor(.black)
                .padding(.horizontal, 8)
                .padding(.vertical, 3.5)
                .background(palette.primaryAccent)
                .clipShape(Capsule())

                // 6-dot clickable step indicator
                HStack(spacing: 6) {
                    ForEach(OnboardingGuideStep.allCases) { step in
                        Button {
                            withAnimation(PurahMotionPolicy.surface) {
                                store.selectOnboardingStep(step)
                                store.triggerControlHaptic(.alignment)
                            }
                        } label: {
                            Circle()
                                .fill(step == store.onboardingStep ? palette.primaryAccent : (step.rawValue < store.onboardingStep.rawValue ? palette.primaryAccent.opacity(0.45) : Color.white.opacity(0.25)))
                                .frame(width: step == store.onboardingStep ? 9 : 7, height: step == store.onboardingStep ? 9 : 7)
                        }
                        .buttonStyle(.plain)
                        .help(String(format: "help.step".localized, step.rawValue + 1))
                        .accessibilityLabel(String(format: "help.step".localized, step.rawValue + 1))
                    }
                }

                Spacer()

                Button {
                    store.triggerControlHaptic(.levelChange)
                    store.skipAllOnboardingAndLoadDefaults()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 9))
                        Text("onboarding.skipAll".localized)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(6)
                }
                .buttonStyle(.tactile)
            }

            // Body Card
            onboardingStepBodyCard

            if isThinBuild, store.onboardingStep == .handAndPermissions {
                Text(String(format: "onboarding.finish.fewPods".localized, enabledCount))
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            }

            // Footer Navigation Row
            HStack(spacing: 10) {
                Button {
                    withAnimation(PurahMotionPolicy.surface) {
                        store.previousOnboardingStep()
                        store.triggerControlHaptic(.alignment)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 9, weight: .bold))
                        Text("onboarding.back".localized)
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    }
                    .foregroundColor(store.onboardingStep == .firstPod ? .secondary.opacity(0.4) : .white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4.5)
                    .background(Color.white.opacity(store.onboardingStep == .firstPod ? 0.04 : 0.10))
                    .cornerRadius(6)
                }
                .buttonStyle(.tactile)
                .disabled(store.onboardingStep == .firstPod)

                Spacer()

                if store.onboardingStep != .handAndPermissions {
                    Button {
                        withAnimation(PurahMotionPolicy.surface) {
                            store.skipCurrentOnboardingStep()
                            store.triggerControlHaptic(.alignment)
                        }
                    } label: {
                        Text("onboarding.skipStep".localized)
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4.5)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(6)
                    }
                    .buttonStyle(.tactile)

                    Button {
                        withAnimation(PurahMotionPolicy.surface) {
                            store.nextOnboardingStep()
                            store.triggerControlHaptic(.levelChange)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("onboarding.nextStep".localized)
                                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .foregroundColor(isMissionComplete ? .black : .white)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 4.5)
                        .background(isMissionComplete ? palette.primaryAccent : Color.white.opacity(0.08))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.tactile)
                    // A completed step points at the control that advances it.
                    // The one place that enforces this is the anchor modifier;
                    // this owner is the only one allowed to publish then.
                    .onboardingCalloutAnchor(
                        store: store,
                        owner: "dock-next-step",
                        step: store.onboardingStep,
                        isActive: store.isCurrentOnboardingMissionCompleted,
                        labelKey: "onboarding.callout.clickHere",
                        side: .leading
                    )
                } else {
                    Button {
                        store.triggerControlHaptic(.levelChange)
                        store.finishOnboarding(useRecommendedLayout: true)
                    } label: {
                        Text("onboarding.finishRecommended".localized)
                            .font(.system(
                                size: 10.5,
                                weight: isThinBuild ? .bold : .medium,
                                design: .rounded
                            ))
                            .foregroundColor(isThinBuild ? .black : .white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4.5)
                            .background(isThinBuild ? palette.primaryAccent : Color.white.opacity(0.14))
                            .cornerRadius(6)
                    }
                    .buttonStyle(.tactile)

                    Button {
                        store.triggerControlHaptic(.levelChange)
                        store.finishOnboarding(useRecommendedLayout: false)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10, weight: .bold))
                            Text("onboarding.finish".localized)
                                .font(.system(
                                    size: 10.5,
                                    weight: isThinBuild ? .medium : .bold,
                                    design: .rounded
                                ))
                        }
                        .foregroundColor(isThinBuild ? .white : .black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4.5)
                        .background(isThinBuild ? Color.white.opacity(0.14) : palette.primaryAccent)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.tactile)
                    .onboardingCalloutAnchor(
                        store: store,
                        owner: "dock-next-step",
                        step: store.onboardingStep,
                        isActive: store.isCurrentOnboardingMissionCompleted,
                        labelKey: "onboarding.callout.clickHere",
                        side: .leading
                    )
                }
            }
        }
    }

    // MARK: - Step Body Card & Hands-On Mission HUD

    @ViewBuilder
    private func missionBox<Content: View>(isCompleted: Bool, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: isCompleted ? "checkmark.circle.fill" : "target")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundColor(isCompleted ? .green : palette.primaryAccent)
                Text("onboarding.mission.title".localized)
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundColor(isCompleted ? .green : palette.primaryAccent)

                Spacer()

                Text(isCompleted ? "onboarding.mission.completed".localized : "onboarding.mission.pending".localized)
                    .font(.system(size: 8.5, weight: .bold, design: .rounded))
                    .foregroundColor(isCompleted ? .black : palette.primaryAccent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(isCompleted ? Color.green : palette.primaryAccent.opacity(0.18))
                    .clipShape(Capsule())
            }

            content()
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(isCompleted ? Color.green.opacity(0.4) : palette.primaryAccent.opacity(0.25), lineWidth: 0.8)
                )
        )
    }

    @ViewBuilder
    private func missionCheckItem(isDone: Bool, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 9.5, weight: .bold))
                .foregroundColor(isDone ? .green : .secondary)

            Text(text)
                .font(.system(size: 9.5, weight: isDone ? .semibold : .regular, design: .rounded))
                .foregroundColor(isDone ? .white : .secondary)
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private var onboardingStepBodyCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch store.onboardingStep {
            case .firstPod: firstPodStepBody
            case .edgeUse: edgeUseStepBody
            case .stack: stackStepBody
            case .decomposeDemo: decomposeDemoStepBody
            case .handAndPermissions: handAndPermissionsStepBody
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.05))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(palette.primaryAccent.opacity(0), lineWidth: 1.6)
        )
    }

    /// Title / subtitle pair plus the "Auto Demo" button, shared by the steps
    /// that rehearse a single layout action.
    private func stepHeader(
        titleKey: String,
        subtitleKey: String,
        rehearse: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(titleKey.localized)
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(subtitleKey.localized)
                    .font(.system(size: 9.5, weight: .regular))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button {
                withAnimation(PurahMotionPolicy.surface) {
                    rehearse()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                    Text("onboarding.autoDemo".localized)
                }
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.12))
                .cornerRadius(6)
            }
            .buttonStyle(.tactile)
        }
    }

    // MARK: Step 0 — One pod, and its drawer

    private var firstPodStepBody: some View {
        let isDone = store.isCurrentOnboardingMissionCompleted

        return VStack(alignment: .leading, spacing: 6) {
            stepHeader(
                titleKey: "onboarding.firstPod.title",
                subtitleKey: "onboarding.firstPod.subtitle",
                rehearse: { store.rehearseMountSamplePods() }
            )

            missionBox(isCompleted: isDone) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        missionCheckItem(
                            isDone: isDone,
                            text: "onboarding.firstPod.mission".localized
                        )
                        Spacer()

                        Button {
                            withAnimation(PurahMotionPolicy.surface) {
                                store.applyRecommendedLayout()
                                store.triggerControlHaptic(.alignment)
                            }
                        } label: {
                            Text("onboarding.mount.applyRecommended".localized)
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundColor(palette.primaryAccent)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(palette.primaryAccent.opacity(0.14))
                                .cornerRadius(5)
                        }
                        .buttonStyle(.tactile)
                    }

                    Text("onboarding.firstPod.coach".localized)
                        .font(.system(size: 9, design: .rounded))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Step 1 — The edge is the door

    private var edgeUseStepBody: some View {
        let isDone = store.isCurrentOnboardingMissionCompleted

        return VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text("onboarding.edgeUse.title".localized)
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("onboarding.edgeUse.subtitle".localized)
                    .font(.system(size: 9.5, weight: .regular))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            missionBox(isCompleted: isDone) {
                VStack(alignment: .leading, spacing: 5) {
                    missionCheckItem(
                        isDone: isDone,
                        text: "onboarding.edgeUse.mission".localized
                    )
                    Text("onboarding.edgeUse.invite".localized)
                        .font(.system(size: 9, design: .rounded))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Step 3 — One pod, two shapes

    private var decomposeDemoStepBody: some View {
        let isDone = store.onboardingDidToggleDecompose
        let demoId = store.onboardingDemoPodId ?? "vitals"
        let accent = palette.podColor(for: demoId, store: store)
        let isDecomposed = store.isPodDecomposed(demoId)
        let chipCount: Int = {
            if demoId == "vitals" {
                return max(store._vitalsEnabledMetrics.count, 1)
            }
            return max(store.capabilityProvider(for: demoId)?.subItemCount ?? 0, 3)
        }()

        return VStack(alignment: .leading, spacing: 6) {
            stepHeader(
                titleKey: "onboarding.decompose.title",
                subtitleKey: "onboarding.decompose.subtitle",
                rehearse: { store.rehearseDecomposeDemo() }
            )

            missionBox(isCompleted: isDone) {
                VStack(alignment: .leading, spacing: 6) {
                    missionCheckItem(
                        isDone: isDone,
                        text: "onboarding.decompose.mission".localized
                    )

                    HStack(spacing: 8) {
                        decomposePreviewCard(
                            titleKey: "onboarding.decompose.preview.composite",
                            isActive: !isDecomposed,
                            accent: accent
                        ) {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(accent.opacity(0.85))
                                .frame(width: 10, height: 30)
                        }

                        decomposePreviewCard(
                            titleKey: "onboarding.decompose.preview.chips",
                            isActive: isDecomposed,
                            accent: accent
                        ) {
                            VStack(spacing: 2.5) {
                                ForEach(0..<chipCount, id: \.self) { _ in
                                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                        .fill(accent.opacity(0.85))
                                        .frame(width: 32, height: 4.5)
                                }
                            }
                            .frame(height: 30)
                        }

                        Spacer(minLength: 4)
                    }

                    Text("onboarding.decompose.tradeoff".localized)
                        .font(.system(size: 9, design: .rounded))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("onboarding.decompose.hoverHint".localized)
                        .font(.system(size: 9, design: .rounded))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private func decomposePreviewCard<Diagram: View>(
        titleKey: String,
        isActive: Bool,
        accent: Color,
        @ViewBuilder diagram: () -> Diagram
    ) -> some View {
        VStack(spacing: 3) {
            diagram()
                .frame(width: 44, height: 32)
            Text(titleKey.localized)
                .font(.system(size: 8.5, weight: isActive ? .bold : .medium, design: .rounded))
                .foregroundColor(isActive ? .white : .secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isActive ? accent.opacity(0.16) : Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(isActive ? accent : Color.white.opacity(0.12), lineWidth: isActive ? 1.3 : 0.8)
                )
        )
    }

    // MARK: Step 2 — Two pods, one group

    private var stackStepBody: some View {
        let isDone = store.isCurrentOnboardingMissionCompleted

        return VStack(alignment: .leading, spacing: 6) {
            stepHeader(
                titleKey: "onboarding.stack.title",
                subtitleKey: "onboarding.stack.subtitle",
                rehearse: { store.rehearseStackMerge() }
            )

            missionBox(isCompleted: isDone) {
                VStack(alignment: .leading, spacing: 4) {
                    missionCheckItem(
                        isDone: isDone,
                        text: "onboarding.stack.mission".localized
                    )

                    HStack(spacing: 5) {
                        if isDone {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(.green)
                            Text("onboarding.stack.statusSuccess".localized)
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundColor(.green)
                        } else if store.externalDraggedPodId != nil || store.isDraggingFromDrawer {
                            Image(systemName: "flame.fill")
                                .foregroundColor(.orange)
                            Text("onboarding.stack.statusDragging".localized)
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundColor(.orange)
                        } else {
                            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                                .foregroundColor(.secondary)
                            Text("onboarding.stack.statusHint".localized)
                                .font(.system(size: 9, weight: .regular, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                }
            }
        }
    }

    // MARK: Step 4 — Tune the edge to your hand, and permissions

    /// Both offers live in one step because neither is required to use Purah:
    /// the edge already opened a drawer in step 1, and a skipped permission
    /// only costs that plugin's connected feature.
    private var handAndPermissionsStepBody: some View {
        let rows = PermissionInventory.promptable()

        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("onboarding.hand.title".localized)
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("onboarding.hand.subtitle".localized)
                        .font(.system(size: 9.5, weight: .regular))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)

                triggerModePills
                sensitivityPills
            }

            missionBox(isCompleted: true) {
                VStack(alignment: .leading, spacing: 5) {
                    missionCheckItem(
                        isDone: true,
                        text: "onboarding.hand.mission".localized
                    )

                    HStack(spacing: 4) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 9))
                            .foregroundColor(palette.primaryAccent)
                        Text(store.edgeTriggerMode == .hoverDwell ? "onboarding.edge.descDwell".localized : "onboarding.edge.descBarrier".localized)
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundColor(palette.primaryAccent)
                    }

                    onboardingGateTelemetryMeter

                    Divider()
                        .background(Color.white.opacity(0.10))

                    Text("onboarding.hand.permissionsHeader".localized)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    if rows.isEmpty {
                        missionCheckItem(isDone: true, text: "onboarding.permissions.none".localized)
                    } else {
                        VStack(spacing: 4) {
                            ForEach(rows) { group in
                                permissionRow(group)
                            }
                        }
                    }
                }
            }
        }
        .task {
            PermissionManager.shared.refreshStatuses()
        }
    }

    @ViewBuilder
    private func permissionRow(_ group: PermissionGroup) -> some View {
        let status = PermissionManager.shared.status(for: group.permission)

        HStack(spacing: 7) {
            Image(systemName: group.permission.icon)
                .font(.system(size: 11))
                .foregroundColor(palette.primaryAccent)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 1) {
                Text(group.permission.rawValue)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                Text("permissions.requestedBy".localized + " " + group.pluginNames)
                    .font(.system(size: 8.5))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            if status == .authorized {
                HStack(spacing: 3) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 9.5))
                    Text("permissions.row.granted".localized)
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                }
                .foregroundColor(.green)
            } else if status == .denied || status == .restricted {
                Button {
                    if let anchor = group.permission.privacySettingsAnchor {
                        PermissionManager.shared.openSystemSettings(for: anchor)
                    }
                } label: {
                    Text("permissions.row.openSettings".localized)
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.14))
                        .cornerRadius(5)
                }
                .buttonStyle(.tactile)
                .help("permissions.row.openSettings".localized)
            } else {
                Button {
                    store.triggerControlHaptic(.levelChange)
                    Task { await grant(group.permission) }
                } label: {
                    Text("permissions.row.grant".localized)
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundColor(.black)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(palette.primaryAccent)
                        .cornerRadius(5)
                }
                .buttonStyle(.tactile)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.04))
        .cornerRadius(6)
    }

    private func grant(_ permission: PluginPermission) async {
        guard await PermissionManager.shared.requestAccess(for: permission) else { return }
        switch permission {
        case .calendar:
            SystemCalendarSyncService.shared.syncEvents(into: store)
        case .reminders:
            await SystemRemindersSyncService.shared.syncReminders(into: store)
        default:
            break
        }
    }

    /// Hover-dwell / push-barrier selector pills.
    private var triggerModePills: some View {
        HStack(spacing: 4) {
            Button {
                withAnimation(PurahMotionPolicy.surface) {
                    store.edgeTriggerMode = .hoverDwell
                    store.onboardingDidSwitchTriggerMode = true
                    store.onboardingGateState = .idle
                    store.onboardingGateProgress = 0.0
                    store.onboardingGateCurrentValue = 0
                    store.onboardingGateTargetValue = (store.edgeTriggerSensitivity == .agile ? 0 : (store.edgeTriggerSensitivity == .balanced ? 150 : 280))
                    store.savePersistentState()
                    store.triggerControlHaptic(.alignment)
                }
            } label: {
                Text("onboarding.edge.hoverDwell".localized)
                    .font(.system(size: 9, weight: store.edgeTriggerMode == .hoverDwell ? .bold : .medium, design: .rounded))
                    .foregroundColor(store.edgeTriggerMode == .hoverDwell ? palette.primaryAccent : .secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3.5)
                    .background(store.edgeTriggerMode == .hoverDwell ? palette.primaryAccent.opacity(0.18) : Color.white.opacity(0.08))
                    .cornerRadius(5)
            }
            .buttonStyle(.tactile)

            Button {
                withAnimation(PurahMotionPolicy.surface) {
                    store.edgeTriggerMode = .pushForce
                    store.onboardingDidSwitchTriggerMode = true
                    store.onboardingGateState = .idle
                    store.onboardingGateProgress = 0.0
                    store.onboardingGateCurrentValue = 0
                    store.onboardingGateTargetValue = Int(store.activePushResistanceBarrier)
                    store.savePersistentState()
                    store.triggerControlHaptic(.alignment)
                }
            } label: {
                Text("onboarding.edge.pushBarrier".localized)
                    .font(.system(size: 9, weight: store.edgeTriggerMode == .pushForce ? .bold : .medium, design: .rounded))
                    .foregroundColor(store.edgeTriggerMode == .pushForce ? palette.primaryAccent : .secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3.5)
                    .background(store.edgeTriggerMode == .pushForce ? palette.primaryAccent.opacity(0.18) : Color.white.opacity(0.08))
                    .cornerRadius(5)
            }
            .buttonStyle(.tactile)
        }
    }

    /// Sensitivity presets, labelled with the value each one actually applies.
    private var sensitivityPills: some View {
        HStack(spacing: 3) {
            ForEach([EdgeTriggerSensitivity.agile, .balanced, .cautious]) { sens in
                Button {
                    withAnimation(PurahMotionPolicy.surface) {
                        store.edgeTriggerSensitivity = sens
                        store.onboardingGateState = .idle
                        store.onboardingGateProgress = 0.0
                        store.onboardingGateCurrentValue = 0
                        if store.edgeTriggerMode == .hoverDwell {
                            store.onboardingGateTargetValue = (sens == .agile ? 0 : (sens == .balanced ? 150 : 280))
                        } else {
                            store.onboardingGateTargetValue = Int(sens.pushResistanceBarrier)
                        }
                        store.savePersistentState()
                        store.triggerControlHaptic(.alignment)
                    }
                } label: {
                    Text(sensitivityPillText(for: sens))
                        .font(.system(size: 8.5, weight: store.edgeTriggerSensitivity == sens ? .bold : .medium, design: .rounded))
                        .foregroundColor(store.edgeTriggerSensitivity == sens ? .white : .secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3.5)
                        .background(store.edgeTriggerSensitivity == sens ? Color.white.opacity(0.20) : Color.white.opacity(0.06))
                        .cornerRadius(4)
                }
                .buttonStyle(.tactile)
            }
        }
    }

    private func sensitivityPillText(for sens: EdgeTriggerSensitivity) -> String {
        if store.edgeTriggerMode == .hoverDwell {
            switch sens {
            case .agile: return "\(sens.localizedShortName) (0ms)"
            case .balanced: return "\(sens.localizedShortName) (150ms)"
            case .cautious: return "\(sens.localizedShortName) (280ms)"
            case .custom: return "\(sens.localizedShortName) (\(Int(store.customInitialDwellMs))ms)"
            }
        } else {
            switch sens {
            case .agile: return "\(sens.localizedShortName) (22px)"
            case .balanced: return "\(sens.localizedShortName) (36px)"
            case .cautious: return "\(sens.localizedShortName) (52px)"
            case .custom: return "\(sens.localizedShortName) (\(Int(store.customPushResistanceBarrier))px)"
            }
        }
    }

    /// Live gate telemetry bar: progress fill plus a status line describing what
    /// the edge gate is currently doing.
    private var onboardingGateTelemetryMeter: some View {
        let gateStatusText: String = {
            switch store.onboardingGateState {
            case .idle:
                return "onboarding.edge.gate.idle".localized
            case .dwelling:
                return String(format: "onboarding.edge.gate.dwelling".localized, store.onboardingGateCurrentValue, store.onboardingGateTargetValue)
            case .pushing:
                return String(format: "onboarding.edge.gate.pushing".localized, store.onboardingGateCurrentValue, store.onboardingGateTargetValue)
            case .suppressedFling:
                return String(format: "onboarding.edge.gate.suppressedFling".localized, store.onboardingGateCurrentValue)
            case .opened:
                let unit = store.edgeTriggerMode == .hoverDwell ? "ms" : "px"
                return String(format: "onboarding.edge.gate.opened".localized, store.onboardingGateTargetValue, unit)
            }
        }()

        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text("onboarding.edge.gate.title".localized)
                    .font(.system(size: 8.5, weight: .bold, design: .rounded))
                    .foregroundColor(palette.primaryAccent)
                Spacer()
                Text("\(Int(store.onboardingGateProgress * 100))%")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(store.onboardingGateState == .suppressedFling ? .orange : (store.onboardingGateState == .opened ? .green : palette.primaryAccent))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 5)
                    Capsule()
                        .fill(
                            store.onboardingGateState == .suppressedFling ? Color.orange :
                            (store.onboardingGateState == .opened ? Color.green : palette.primaryAccent)
                        )
                        .frame(width: max(geo.size.width * CGFloat(store.onboardingGateProgress), 4), height: 5)
                        .animation(.linear(duration: 0.05), value: store.onboardingGateProgress)
                }
            }
            .frame(height: 5)

            Text(gateStatusText)
                .font(.system(size: 8, weight: .medium, design: .rounded))
                .foregroundColor(
                    store.onboardingGateState == .suppressedFling ? .orange :
                    (store.onboardingGateState == .opened ? .green : .white.opacity(0.85))
                )
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.black.opacity(0.35))
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(
                            store.onboardingGateState == .suppressedFling ? Color.orange.opacity(0.6) :
                            (store.onboardingGateState == .opened ? Color.green.opacity(0.6) : palette.primaryAccent.opacity(0.25)),
                            lineWidth: 0.8
                        )
                )
        )
    }
}
