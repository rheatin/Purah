// Sources/PurahUI/Settings/LiveRailSculptorDockView.swift
import SwiftUI
import AppKit
import PurahCore

public struct LiveRailSculptorDockView: View {
    public let store: PurahWorkspaceStore

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    public init(store: PurahWorkspaceStore) {
        self.store = store
    }

    public var body: some View {
        let unmounted = store.pods.filter { !$0.isEnabled }

        VStack(alignment: .leading, spacing: 10) {
            if store.isOnboardingGuideActive {
                onboardingCoachHUD
            } else {
                // Row 1: Top Header Bar
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
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
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

                    // Auto-Layout Button
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
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

            Divider()
                .background(Color.white.opacity(0.15))

            // Row 2: Plugin Add / Unmounted Dock
            if !unmounted.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text("sculptor.dock.unmounted".localized)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)

                        Spacer(minLength: 4)

                        if let draggedId = store.externalDraggedPodId,
                           let draggedPod = store.pods.first(where: { $0.id == draggedId }) {
                            if let targetPodId = store.externalDragTargetPodId,
                               let targetPod = store.pods.first(where: { $0.id == targetPodId }) {
                                Text("📦 Release to Stack \(draggedPod.name) with \(targetPod.name)")
                                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                                    .foregroundColor(.orange)
                            } else if let targetEdge = store.externalDragTargetEdge {
                                Text("🧲 Release to Mount \(draggedPod.name) on \(targetEdge == .left ? "Left" : "Right") Rail")
                                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                                    .foregroundColor(palette.primaryAccent)
                            } else {
                                Text("Drag \(draggedPod.name) to Left/Right Rail or onto any Pod to Stack")
                                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                                    .foregroundColor(.white.opacity(0.85))
                            }
                        } else {
                            Text("Tip: Drag any pill onto a Rail or Stack, or click +L / +R")
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                .foregroundColor(.secondary.opacity(0.8))
                        }
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(unmounted) { pod in
                                let podColor = palette.podColor(for: pod.id, store: store)
                                let isBeingDragged = (store.externalDraggedPodId == pod.id)
                                HStack(spacing: 5) {
                                    Image(systemName: pod.systemIcon)
                                        .font(.system(size: 10.5, weight: .semibold))
                                        .foregroundColor(podColor)

                                    Text(pod.name)
                                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                                        .foregroundColor(.white)
                                        .lineLimit(1)

                                    Button {
                                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
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
                                    .help("Mount \(pod.name) to Left Rail")

                                    Button {
                                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
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
                                    .help("Mount \(pod.name) to Right Rail")
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
                                            withAnimation(.spring(response: 0.30, dampingFraction: 0.80)) {
                                                store.commitExternalPodDrag(
                                                    podId: pod.id,
                                                    screenFrame: screenFrame
                                                )
                                            }
                                        }
                                    )
                            }
                        }
                    }
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 11))
                        .foregroundColor(palette.primaryAccent)
                    Text("sculptor.dock.allMounted".localized)
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(width: store.isOnboardingGuideActive ? 760 : 720)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.72))
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(palette.primaryAccent.opacity(0.65), lineWidth: 1.4)
        )
        .shadow(color: Color.black.opacity(0.45), radius: 14, x: 0, y: 6)
    }

    // MARK: - Onboarding Coach HUD

    @ViewBuilder
    private var onboardingCoachHUD: some View {
        VStack(alignment: .leading, spacing: 9) {
            // Header Row: Step badge, 6 dots, Spacer, Skip All button
            HStack(spacing: 10) {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .bold))
                    Text("STEP \(store.onboardingStep.rawValue + 1) / 6")
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
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                store.selectOnboardingStep(step)
                                store.triggerControlHaptic(.alignment)
                            }
                        } label: {
                            Circle()
                                .fill(step == store.onboardingStep ? palette.primaryAccent : (step.rawValue < store.onboardingStep.rawValue ? palette.primaryAccent.opacity(0.45) : Color.white.opacity(0.25)))
                                .frame(width: step == store.onboardingStep ? 9 : 7, height: step == store.onboardingStep ? 9 : 7)
                        }
                        .buttonStyle(.plain)
                        .help("Step \(step.rawValue + 1)")
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

            // Footer Navigation Row
            HStack(spacing: 10) {
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
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
                    .foregroundColor(store.onboardingStep == .mountPods ? .secondary.opacity(0.4) : .white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4.5)
                    .background(Color.white.opacity(store.onboardingStep == .mountPods ? 0.04 : 0.10))
                    .cornerRadius(6)
                }
                .buttonStyle(.tactile)
                .disabled(store.onboardingStep == .mountPods)

                Spacer()

                if store.onboardingStep != .antiTouchCalibration {
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
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
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
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
                        .foregroundColor(.black)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 4.5)
                        .background(palette.primaryAccent)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.tactile)
                } else {
                    Button {
                        store.triggerControlHaptic(.levelChange)
                        store.finishOnboarding(useRecommendedLayout: true)
                    } label: {
                        Text("onboarding.finishRecommended".localized)
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4.5)
                            .background(Color.white.opacity(0.14))
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
                                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4.5)
                        .background(palette.primaryAccent)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.tactile)
                }
            }
        }
    }

    // MARK: - Step Body Card

    @ViewBuilder
    private var onboardingStepBodyCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch store.onboardingStep {
            case .mountPods:
                let leftCount = store.pods.filter { $0.edge == .left && $0.isEnabled }.count
                let rightCount = store.pods.filter { $0.edge == .right && $0.isEnabled }.count

                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("onboarding.step1.title".localized)
                            .font(.system(size: 11.5, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("onboarding.step1.subtitle".localized)
                            .font(.system(size: 9.5, weight: .regular))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    HStack(spacing: 6) {
                        Text("Left: \(leftCount) · Right: \(rightCount)")
                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            .foregroundColor(palette.primaryAccent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3.5)
                            .background(palette.primaryAccent.opacity(0.14))
                            .clipShape(Capsule())

                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                store.rehearseMountSamplePods()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "sparkles")
                                Text("onboarding.step1.autoMount".localized)
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

            case .decomposeDemo:
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("onboarding.step2.title".localized)
                            .font(.system(size: 11.5, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("onboarding.step2.subtitle".localized)
                            .font(.system(size: 9.5, weight: .regular))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    HStack(spacing: 6) {
                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                store.rehearseDecomposeDemo(decomposed: false)
                            }
                        } label: {
                            Text("onboarding.step2.composite".localized)
                                .font(.system(size: 9.5, weight: !store._isScriptsDecomposed ? .bold : .medium, design: .rounded))
                                .foregroundColor(!store._isScriptsDecomposed ? palette.primaryAccent : .secondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(!store._isScriptsDecomposed ? palette.primaryAccent.opacity(0.18) : Color.white.opacity(0.08))
                                .cornerRadius(5)
                        }
                        .buttonStyle(.tactile)

                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                store.rehearseDecomposeDemo(decomposed: true)
                            }
                        } label: {
                            Text("onboarding.step2.decomposed".localized)
                                .font(.system(size: 9.5, weight: store._isScriptsDecomposed ? .bold : .medium, design: .rounded))
                                .foregroundColor(store._isScriptsDecomposed ? palette.primaryAccent : .secondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(store._isScriptsDecomposed ? palette.primaryAccent.opacity(0.18) : Color.white.opacity(0.08))
                                .cornerRadius(5)
                        }
                        .buttonStyle(.tactile)

                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                store.rehearseDecomposeDemo()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "sparkles")
                                Text("onboarding.step2.rehearse".localized)
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

            case .stackDemo:
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("onboarding.step3.title".localized)
                            .font(.system(size: 11.5, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("onboarding.step3.subtitle".localized)
                            .font(.system(size: 9.5, weight: .regular))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            store.rehearseStackMerge()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "square.stack.3d.up.fill")
                            Text("onboarding.step3.rehearse".localized)
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

            case .pageDemo:
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("onboarding.step4.title".localized)
                            .font(.system(size: 11.5, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("onboarding.step4.subtitle".localized)
                            .font(.system(size: 9.5, weight: .regular))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            store.rehearsePaginationFlip()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "book.pages.fill")
                            Text("onboarding.step4.rehearse".localized)
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

            case .breathingDemo:
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("onboarding.step5.title".localized)
                            .font(.system(size: 11.5, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("onboarding.step5.subtitle".localized)
                            .font(.system(size: 9.5, weight: .regular))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            store.rehearseDynamicBreathing()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "lungs.fill")
                            Text("onboarding.step5.rehearse".localized)
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

            case .antiTouchCalibration:
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("onboarding.step6.title".localized)
                                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            Text("onboarding.step6.subtitle".localized)
                                .font(.system(size: 9.5, weight: .regular))
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        // Mode Selector Pills
                        HStack(spacing: 4) {
                            Button {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                    store.edgeTriggerMode = .hoverDwell
                                    store.savePersistentState()
                                    store.triggerControlHaptic(.alignment)
                                }
                            } label: {
                                Text("onboarding.step6.hoverDwell".localized)
                                    .font(.system(size: 9, weight: store.edgeTriggerMode == .hoverDwell ? .bold : .medium, design: .rounded))
                                    .foregroundColor(store.edgeTriggerMode == .hoverDwell ? palette.primaryAccent : .secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3.5)
                                    .background(store.edgeTriggerMode == .hoverDwell ? palette.primaryAccent.opacity(0.18) : Color.white.opacity(0.08))
                                    .cornerRadius(5)
                            }
                            .buttonStyle(.tactile)

                            Button {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                    store.edgeTriggerMode = .pushForce
                                    store.savePersistentState()
                                    store.triggerControlHaptic(.alignment)
                                }
                            } label: {
                                Text("onboarding.step6.pushBarrier".localized)
                                    .font(.system(size: 9, weight: store.edgeTriggerMode == .pushForce ? .bold : .medium, design: .rounded))
                                    .foregroundColor(store.edgeTriggerMode == .pushForce ? palette.primaryAccent : .secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3.5)
                                    .background(store.edgeTriggerMode == .pushForce ? palette.primaryAccent.opacity(0.18) : Color.white.opacity(0.08))
                                    .cornerRadius(5)
                            }
                            .buttonStyle(.tactile)
                        }

                        // Sensitivity Selector Pills
                        HStack(spacing: 3) {
                            ForEach([EdgeTriggerSensitivity.agile, .balanced, .cautious]) { sens in
                                Button {
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                        store.edgeTriggerSensitivity = sens
                                        store.savePersistentState()
                                        store.triggerControlHaptic(.alignment)
                                    }
                                } label: {
                                    Text(sens.localizedShortName)
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

                    HStack(spacing: 4) {
                        Image(systemName: "hand.point.up.left.and.text.fill")
                            .font(.system(size: 9.5))
                            .foregroundColor(palette.primaryAccent)
                        Text("onboarding.step6.livePrompt".localized)
                            .font(.system(size: 9.5, weight: .medium, design: .rounded))
                            .foregroundColor(palette.primaryAccent)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.05))
        .cornerRadius(8)
    }
}
