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
                                Text(String(format: "sculptor.releaseToStackWith".localized, draggedPod.name, targetPod.name))
                                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                                    .foregroundColor(.orange)
                            } else if let targetEdge = store.externalDragTargetEdge {
                                Text("🧲 Release to Mount \(draggedPod.name) on \(targetEdge == .left ? "Left" : "Right") Rail")
                                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                                    .foregroundColor(palette.primaryAccent)
                            } else {
                                Text(String(format: "sculptor.dragToRail".localized, draggedPod.name))
                                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                                    .foregroundColor(.white.opacity(0.85))
                            }
                        } else {
                            Text("sculptor.dragTip".localized)
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                .foregroundColor(.secondary.opacity(0.8))
                        }
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(unmounted) { pod in
                                 let podColor = palette.podColor(for: pod.id, store: store)
                                 let isBeingDragged = (store.externalDraggedPodId == pod.id)
                                 let isOnboardingDockPulse = store.isOnboardingGuideActive && (store.onboardingStep == .mountPods || store.onboardingStep == .stackDemo)
                                 HStack(spacing: 5) {
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
                                     .help("Mount \(pod.name) to Left Rail")

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
                                     .help("Mount \(pod.name) to Right Rail")

                                     if isOnboardingDockPulse {
                                         Text("onboarding.dock.dragHint".localized)
                                             .font(.system(size: 8, weight: .bold, design: .rounded))
                                             .foregroundColor(palette.primaryAccent)
                                             .padding(.horizontal, 4)
                                             .padding(.vertical, 1.5)
                                             .background(palette.primaryAccent.opacity(0.18))
                                             .cornerRadius(3)
                                     }
                                 }
                                 .padding(.horizontal, 8)
                                 .padding(.vertical, 5)
                                 .background(
                                     RoundedRectangle(cornerRadius: 7, style: .continuous)
                                         .fill(isBeingDragged ? podColor.opacity(0.26) : Color.white.opacity(0.08))
                                         .overlay(
                                             RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                 .stroke(
                                                     isBeingDragged ? Color.orange : (isOnboardingDockPulse ? palette.primaryAccent.opacity(0.85) : podColor.opacity(0.45)),
                                                     lineWidth: (isBeingDragged || isOnboardingDockPulse) ? 1.6 : 1.0
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
                    Text(String(format: "onboarding.stepCounter".localized, store.onboardingStep.rawValue + 1))
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
            case .mountPods:
                let leftCount = store.pods.filter { $0.edge == .left && $0.isEnabled }.count
                let rightCount = store.pods.filter { $0.edge == .right && $0.isEnabled }.count
                let isStepDone = (leftCount >= 1 && rightCount >= 1)

                // Top Row: Title + Subtitle + Auto-Demo
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
                    Button {
                        withAnimation(PurahMotionPolicy.surface) {
                            store.rehearseMountSamplePods()
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

                // Bottom Interactive Mission Box
                missionBox(isCompleted: isStepDone) {
                    HStack(spacing: 16) {
                        missionCheckItem(
                            isDone: leftCount >= 1,
                            text: String(format: "onboarding.step1.missionLeft".localized, leftCount)
                        )
                        missionCheckItem(
                            isDone: rightCount >= 1,
                            text: String(format: "onboarding.step1.missionRight".localized, rightCount)
                        )
                        Spacer()
                    }
                }

            case .decomposeDemo:
                let isDone = store.onboardingDidToggleDecompose

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
                    Button {
                        withAnimation(PurahMotionPolicy.surface) {
                            store.rehearseDecomposeDemo()
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

                missionBox(isCompleted: isDone) {
                    VStack(alignment: .leading, spacing: 5) {
                        missionCheckItem(
                            isDone: isDone,
                            text: "onboarding.step2.mission".localized
                        )

                        HStack(spacing: 8) {
                            let isVitalsDecomp = store.isPodDecomposed("vitals")
                            Button {
                                withAnimation(PurahMotionPolicy.surface) {
                                    store.togglePodDecomposedInSculptor(podId: "vitals")
                                }
                            } label: {
                                Text(isVitalsDecomp ? "onboarding.step2.capsuleButton.bar".localized : "onboarding.step2.capsuleButton.chips".localized)
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .foregroundColor(isVitalsDecomp ? palette.primaryAccent : .white)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(isVitalsDecomp ? palette.primaryAccent.opacity(0.20) : Color.white.opacity(0.12))
                                    .cornerRadius(5)
                            }
                            .buttonStyle(.tactile)

                            Button {
                                withAnimation(PurahMotionPolicy.surface) {
                                    store.isRehearsingBreathingInSculptor.toggle()
                                    store.onWindowsRebuildNeeded?()
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: store.isRehearsingBreathingInSculptor ? "eye.fill" : "hammer.fill")
                                    Text("onboarding.step2.toggleLiveTest".localized)
                                }
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                .foregroundColor(store.isRehearsingBreathingInSculptor ? palette.primaryAccent : .secondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(store.isRehearsingBreathingInSculptor ? palette.primaryAccent.opacity(0.16) : Color.white.opacity(0.08))
                                .cornerRadius(5)
                            }
                            .buttonStyle(.tactile)

                            Spacer()
                        }
                    }
                }

            case .stackDemo:
                let isDone = store.isCurrentOnboardingMissionCompleted

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
                        withAnimation(PurahMotionPolicy.surface) {
                            store.rehearseStackMerge()
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

                missionBox(isCompleted: isDone) {
                    VStack(alignment: .leading, spacing: 4) {
                        missionCheckItem(
                            isDone: isDone,
                            text: "onboarding.step3.mission".localized
                        )

                        HStack(spacing: 5) {
                            if isDone {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundColor(.green)
                                Text("onboarding.step3.statusSuccess".localized)
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .foregroundColor(.green)
                            } else if store.externalDraggedPodId != nil || store.isDraggingFromDrawer {
                                Image(systemName: "flame.fill")
                                    .foregroundColor(.orange)
                                Text("onboarding.step3.statusDragging".localized)
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .foregroundColor(.orange)
                            } else {
                                Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                                    .foregroundColor(.secondary)
                                Text("onboarding.step3.statusHint".localized)
                                    .font(.system(size: 9, weight: .regular, design: .rounded))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                    }
                }

            case .pageDemo:
                let isDone = store.isCurrentOnboardingMissionCompleted

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
                        withAnimation(PurahMotionPolicy.surface) {
                            store.rehearsePaginationFlip()
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

                missionBox(isCompleted: isDone) {
                    HStack(spacing: 16) {
                        missionCheckItem(
                            isDone: store.onboardingDidCreatePage,
                            text: "onboarding.step4.missionCreate".localized
                        )
                        missionCheckItem(
                            isDone: store.onboardingDidSwitchPage,
                            text: "onboarding.step4.missionSwitch".localized
                        )
                        Spacer()
                    }
                }

            case .breathingDemo:
                let hoveredCount = store.onboardingBreathingHoveredPods.count
                let isDone = (hoveredCount >= 2)

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

                    // Temporary 7-Pod Sandbox Toggle / Restore My Layout Button
                    Button {
                        withAnimation(PurahMotionPolicy.surface) {
                            store.toggleTemporaryBreathingSandbox()
                            store.triggerControlHaptic(.alignment)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: store.isUsingTemporaryDemoSandbox ? "arrow.uturn.backward.circle.fill" : "flask.fill")
                                .font(.system(size: 9.5, weight: .bold))
                            Text(store.isUsingTemporaryDemoSandbox ? "onboarding.step5.sandboxRestore".localized : "onboarding.step5.sandboxTry".localized)
                                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(store.isUsingTemporaryDemoSandbox ? .black : .white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(store.isUsingTemporaryDemoSandbox ? Color.orange : Color.white.opacity(0.12))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.tactile)

                    Button {
                        withAnimation(PurahMotionPolicy.surface) {
                            store.rehearseDynamicBreathing()
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

                missionBox(isCompleted: store.isDynamicBreathingEnabled && isDone) {
                    if !store.isDynamicBreathingEnabled {
                        HStack(spacing: 8) {
                            Text("onboarding.step5.dynamicOffPrompt".localized)
                                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                                .foregroundColor(Color.orange.opacity(0.95))
                                .fixedSize(horizontal: false, vertical: true)

                            Spacer(minLength: 4)

                            Button {
                                withAnimation(PurahMotionPolicy.surface) {
                                    store.setDynamicBreathingEnabled(true)
                                    store.triggerControlHaptic(.alignment)
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "lungs.fill")
                                    Text("onboarding.step5.turnOnDynamic".localized)
                                }
                                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                                .foregroundColor(.black)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.orange)
                                .cornerRadius(6)
                            }
                            .buttonStyle(.tactile)
                        }
                    } else {
                        HStack(spacing: 8) {
                            missionCheckItem(
                                isDone: isDone,
                                text: String(format: "onboarding.step5.missionActive".localized, min(hoveredCount, 2))
                            )
                            Spacer()
                        }
                    }
                }

            case .antiTouchCalibration:
                let isDone = store.onboardingDidTriggerEdgeDrawer

                VStack(alignment: .leading, spacing: 5) {
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
                                    let pillText: String = {
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
                                    }()
                                    Text(pillText)
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

                    missionBox(isCompleted: isDone) {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 4) {
                                Image(systemName: "info.circle.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(palette.primaryAccent)
                                Text(store.edgeTriggerMode == .hoverDwell ? "onboarding.step6.descDwell".localized : "onboarding.step6.descBarrier".localized)
                                    .font(.system(size: 9, weight: .medium, design: .rounded))
                                    .foregroundColor(palette.primaryAccent)
                            }

                            missionCheckItem(
                                isDone: isDone,
                                text: String(
                                    format: "onboarding.step6.mission".localized,
                                    isDone ? "onboarding.step6.statusTested".localized : "onboarding.step6.statusWaiting".localized
                                )
                            )

                            // Live Gate Telemetry Meter Bar
                            let gateStatusText: String = {
                                switch store.onboardingGateState {
                                case .idle:
                                    return "onboarding.step6.gate.idle".localized
                                case .dwelling:
                                    return String(format: "onboarding.step6.gate.dwelling".localized, store.onboardingGateCurrentValue, store.onboardingGateTargetValue)
                                case .pushing:
                                    return String(format: "onboarding.step6.gate.pushing".localized, store.onboardingGateCurrentValue, store.onboardingGateTargetValue)
                                case .suppressedFling:
                                    return String(format: "onboarding.step6.gate.suppressedFling".localized, store.onboardingGateCurrentValue)
                                case .opened:
                                    let unit = store.edgeTriggerMode == .hoverDwell ? "ms" : "px"
                                    return String(format: "onboarding.step6.gate.opened".localized, store.onboardingGateTargetValue, unit)
                                }
                            }()

                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 4) {
                                    Text("onboarding.step6.gate.title".localized)
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
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.05))
        .cornerRadius(8)
    }
}
