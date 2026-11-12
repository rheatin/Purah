// Sources/PurahUI/Settings/OnboardingWorkbenchView.swift
import SwiftUI
import AppKit
import PurahCore

public struct OnboardingWorkbenchView: View {
    public let store: PurahWorkspaceStore

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    // Act 1 Live Meter States
    @State private var liveHoverCharge: CGFloat = 0.0
    @State private var livePushCharge: CGFloat = 0.0
    @State private var isMistouchBlockedAlert: Bool = false
    @State private var meterStatusText: String = "已加载你的默认参数 (80ms 极速悬停 · 24px 阻尼 · 180ms 宽限期) · 移至边缘或点击测试"
    @State private var chargeTimer: Timer? = nil
    @State private var showBothParameterMeters: Bool = false

    // Act 2 Preset Selection State
    @State private var selectedRigMode: OnboardingRigPreset = .developer
    @State private var isCustomWorkbenchExpanded: Bool = false
    @State private var positionActionFeedback: String? = nil

    // Act 3 Grammar Playground State
    @State private var activeGrammarTab: GrammarTab = .positionResize
    @State private var completedGrammarTabs: Set<GrammarTab> = [.positionResize]

    // Act 4 App-Aware Context Profile State
    @State private var simulatedFrontmostApp: OnboardingSimulatedApp = .xcode
    @State private var appSwitchBannerText: String? = nil

    // Act 5 Permission state
    @State private var grantedPermissions: Set<PluginPermission> = []

    public init(store: PurahWorkspaceStore) {
        self.store = store
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            // 1. Top Step Navigation Pills
            topStepNavigationPills

            // 2. Title & Subtitle Banner
            actHeaderBanner

            // Feedback Banner (if active)
            if let feedback = positionActionFeedback, store.onboardingStep == .pickOrCustomRig {
                toastFeedbackBadge(feedback, color: .yellow)
            } else if let appBanner = appSwitchBannerText, store.onboardingStep == .appContextSwitch {
                toastFeedbackBadge(appBanner, color: simulatedFrontmostApp.accent)
            }

            Divider()
                .background(Color.white.opacity(0.12))

            // 3. Main Act Body
            Group {
                switch store.onboardingStep {
                case .feelTheEdge:
                    act1FeelTheEdgeBody
                case .pickOrCustomRig:
                    act2PickOrCustomRigBody
                case .coreGrammar:
                    act3CoreGrammarBody
                case .appContextSwitch:
                    act4AppContextSwitchBody
                case .permissions:
                    act5PermissionsBody
                }
            }

            Divider()
                .background(Color.white.opacity(0.12))

            // 4. Navigation Footer Row
            navigationFooter
        }
        .onDisappear {
            chargeTimer?.invalidate()
            chargeTimer = nil
        }
    }

    // MARK: - 1. Top Step Navigation Pills

    private var topStepNavigationPills: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                ForEach(OnboardingGuideStep.allCases) { step in
                    stepPillButton(step)
                }
            }

            Spacer()

            Button {
                store.triggerControlHaptic(.levelChange)
                store.skipAllOnboardingAndLoadDefaults()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 8.5))
                    Text("跳过全部")
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.08))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
    }

    private func stepPillButton(_ step: OnboardingGuideStep) -> some View {
        let isCurrent = (step == store.onboardingStep)
        let isPassed = (step.rawValue < store.onboardingStep.rawValue)
        let fg: Color = isCurrent ? .black : (isPassed ? .white : .secondary)
        let bg: Color = isCurrent ? palette.primaryAccent : (isPassed ? Color.green.opacity(0.18) : Color.white.opacity(0.06))

        return Button {
            withAnimation(PurahMotionPolicy.surface) {
                store.selectOnboardingStep(step)
                store.triggerControlHaptic(.alignment)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isPassed ? "checkmark.circle.fill" : step.icon)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(isCurrent ? .black : (isPassed ? .green : .secondary))
                Text(step.shortTitle)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(fg)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(bg))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 2. Act Header Banner

    private var actHeaderBanner: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(store.onboardingStep.badge)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(palette.primaryAccent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(palette.primaryAccent.opacity(0.15))
                    .clipShape(Capsule())

                Text(store.onboardingStep.title)
                    .font(.system(size: 14.5, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }

            Text(store.onboardingStep.subtitle)
                .font(.system(size: 10.5, design: .rounded))
                .foregroundColor(.white.opacity(0.76))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func toastFeedbackBadge(_ text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .foregroundColor(color)
                .font(.system(size: 9.5))
            Text(text)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(color.opacity(0.18))
                .overlay(Capsule().stroke(color.opacity(0.6), lineWidth: 1))
        )
    }

    // MARK: - Act 1: 边缘唤醒破冰 (Feel the Edge)

    private var act1FeelTheEdgeBody: some View {
        let isDone = store.onboardingDidTriggerEdgeDrawer
        return VStack(alignment: .leading, spacing: 9) {
            // Top Status Banner
            HStack(spacing: 10) {
                Image(systemName: isDone ? "checkmark.circle.fill" : "cursorarrow.motionlines")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(isDone ? .green : palette.primaryAccent)
                    .frame(width: 32, height: 32)
                    .background((isDone ? Color.green : palette.primaryAccent).opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(isDone ? "太棒了！你已成功唤醒边缘抽屉" : "去碰一下屏幕最左或最右侧的彩色轨道条")
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .foregroundColor(isDone ? .green : .white)
                    Text("轨道条有多长，滑出的抽屉就有多高。将鼠标移至左右边缘触发，下方 Meter 会实时显示蓄力进度与当前手感参数。")
                        .font(.system(size: 9.5, design: .rounded))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    startLiveDemonstrationCharge()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 8.5))
                        Text("演示蓄力唤醒")
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(palette.primaryAccent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(palette.primaryAccent.opacity(0.16))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(isDone ? Color.green.opacity(0.45) : palette.primaryAccent.opacity(0.28), lineWidth: 1)
                    )
            )

            // Trigger Mode Selector Cards
            HStack(spacing: 8) {
                modeCard(
                    title: "悬停唤醒 (\(Int(store.customInitialDwellMs))ms)",
                    desc: "光标贴边停留 \(Int(store.customInitialDwellMs))ms 即滑出，适合触控板与轻快操作",
                    icon: "timer",
                    isSelected: store.edgeTriggerMode == .hoverDwell
                ) {
                    withAnimation(PurahMotionPolicy.surface) {
                        isMistouchBlockedAlert = false
                        store.edgeTriggerMode = .hoverDwell
                        store.onboardingGateTargetValue = max(Int(store.activeInitialDwellSeconds * 1000), 1)
                        if store.activeDrawerPodId == nil {
                            store.onboardingGateState = .idle
                            store.onboardingGateProgress = 0.0
                            store.onboardingGateCurrentValue = 0
                        }
                        store.savePersistentState()
                        store.triggerControlHaptic(.alignment)
                    }
                }

                modeCard(
                    title: "轻推突破防误触 (\(Int(store.customPushResistanceBarrier))px)",
                    desc: "向屏幕外侧继续轻推突破物理阻力墙才展开，彻底杜绝边缘误触",
                    icon: "shield.lefthalf.filled",
                    isSelected: store.edgeTriggerMode == .pushForce
                ) {
                    withAnimation(PurahMotionPolicy.surface) {
                        isMistouchBlockedAlert = false
                        store.edgeTriggerMode = .pushForce
                        store.onboardingGateTargetValue = max(Int(store.activePushResistanceBarrier), 1)
                        if store.activeDrawerPodId == nil {
                            store.onboardingGateState = .idle
                            store.onboardingGateProgress = 0.0
                            store.onboardingGateCurrentValue = 0
                        }
                        store.savePersistentState()
                        store.triggerControlHaptic(.alignment)
                    }
                }
            }

            // Dual-Meter Console: Live Charge Meter + Focused/Dual Param Meters
            act1DualMeterConsole
        }
        .onChange(of: store.onboardingGateState) { _, newState in
            if newState != .idle {
                chargeTimer?.invalidate()
                chargeTimer = nil
                liveHoverCharge = 0.0
                livePushCharge = 0.0
                if newState != .suppressedFling {
                    isMistouchBlockedAlert = false
                }
            }
        }
        .onChange(of: store.activeDrawerPodId) { _, newPodId in
            if newPodId != nil {
                isMistouchBlockedAlert = false
            }
        }
    }

    private func modeCard(title: String, desc: String, icon: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(isSelected ? palette.primaryAccent : .secondary)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .foregroundColor(isSelected ? .white : .secondary)
                    Text(desc)
                        .font(.system(size: 9, design: .rounded))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(palette.primaryAccent)
                        .font(.system(size: 11))
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? palette.primaryAccent.opacity(0.14) : Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? palette.primaryAccent : Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var effectiveLiveCharge: CGFloat {
        if chargeTimer != nil {
            return (store.edgeTriggerMode == .hoverDwell) ? liveHoverCharge : livePushCharge
        }
        if isMistouchBlockedAlert && store.onboardingGateState == .idle && store.activeDrawerPodId == nil {
            return (store.edgeTriggerMode == .hoverDwell) ? liveHoverCharge : livePushCharge
        }
        if store.activeDrawerPodId != nil || store.activeDrawerItemId != nil || store.onboardingGateState == .opened {
            return 1.0
        }
        if store.onboardingGateState == .suppressedFling {
            return 0.22
        }
        return CGFloat(min(max(store.onboardingGateProgress, 0.0), 1.0))
    }

    private var effectiveIsMistouchBlocked: Bool {
        store.onboardingGateState == .suppressedFling || (isMistouchBlockedAlert && store.activeDrawerPodId == nil && store.onboardingGateState != .opened && store.onboardingGateState != .dwelling && store.onboardingGateState != .pushing)
    }

    private var effectiveMeterStatusText: String {
        if chargeTimer != nil {
            return meterStatusText
        }
        if store.onboardingGateState == .suppressedFling {
            return "🚫 [防误触拦截生效] 检测到贴边高速划过 (\(store.onboardingGateCurrentValue) pt/s)，已自动屏蔽！"
        }
        if isMistouchBlockedAlert && store.activeDrawerPodId == nil && store.onboardingGateState == .idle {
            return meterStatusText
        }
        if let openPodId = store.activeDrawerPodId ?? store.activePod?.id,
           let pod = store.pods.first(where: { $0.id == openPodId }) {
            let modeDesc = (store.edgeTriggerMode == .hoverDwell)
                ? "\(Int(store.customInitialDwellMs))ms 悬停达标"
                : "\(Int(store.customPushResistanceBarrier))px 推压突破"
            return "✅ 已唤醒『\(pod.name)』(\(modeDesc) · 100%) — 移开光标即自动收起"
        }
        switch store.onboardingGateState {
        case .dwelling:
            let pct = Int(min(max(store.onboardingGateProgress, 0.0), 1.0) * 100)
            let target = max(store.onboardingGateTargetValue, Int(store.customInitialDwellMs))
            return "⏳ 正在边缘悬停蓄力：\(store.onboardingGateCurrentValue) / \(target) ms (\(pct)%)"
        case .pushing:
            let pct = Int(min(max(store.onboardingGateProgress, 0.0), 1.0) * 100)
            let target = max(store.onboardingGateTargetValue, Int(store.customPushResistanceBarrier))
            return "🛡️ 正在推压边缘阻力墙：\(store.onboardingGateCurrentValue) / \(target) px (\(pct)%)"
        case .opened:
            return "✅ 达到触发阈值 (100%)，边缘抽屉已解锁滑出！"
        case .suppressedFling:
            return "🚫 [防误触拦截生效] 检测到贴边高速划过 (\(store.onboardingGateCurrentValue) pt/s)，已自动屏蔽！"
        case .idle:
            if store.edgeTriggerMode == .hoverDwell {
                return "已就绪 (\(Int(store.customInitialDwellMs))ms 悬停唤醒 · \(Int(store.customExitGraceMs))ms 宽限期) · 请将光标移至左右屏幕边缘触发"
            } else {
                return "已就绪 (\(Int(store.customPushResistanceBarrier))px 轻推防误触 · \(Int(store.customExitGraceMs))ms 宽限期) · 请在屏幕边缘向外轻推触发"
            }
        }
    }

    private var act1DualMeterConsole: some View {
        let activeCharge = effectiveLiveCharge
        let isBlocked = effectiveIsMistouchBlocked
        let chargeColor: Color = isBlocked
            ? .orange
            : (activeCharge >= 1.0 ? .green : palette.primaryAccent)

        return VStack(alignment: .leading, spacing: 7) {
            // 1. Live Charge / Telemetry Strip
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(chargeColor)
                        .frame(width: 6, height: 6)

                    Text("实时触发蓄力 Meter")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    Text(effectiveMeterStatusText)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(isBlocked ? .orange : (activeCharge >= 1.0 ? .green : palette.primaryAccent))
                        .lineLimit(1)

                    Spacer()

                    Text("\(Int(activeCharge * 100))%")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(chargeColor)
                        .frame(width: 34, alignment: .trailing)

                    Button {
                        simulateFastFlickMistouch()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "hand.raised.slash.fill")
                                .font(.system(size: 8))
                            Text("模拟甩鼠误触拦截")
                                .font(.system(size: 8.5, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(.orange)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.16))
                        .cornerRadius(5)
                    }
                    .buttonStyle(.plain)

                    Button {
                        withAnimation(PurahMotionPolicy.surface) {
                            showBothParameterMeters.toggle()
                            store.triggerControlHaptic(.alignment)
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 8))
                            Text(showBothParameterMeters ? "仅看当前模式表盘 ▴" : "同时对比双表盘 ▾")
                                .font(.system(size: 8.5, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(.white.opacity(0.85))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.10))
                        .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                }

                // 24-Segment LED Live Charge Bar
                GeometryReader { geo in
                    let totalSegments = 24
                    let spacing: CGFloat = 2.5
                    let segWidth = (geo.size.width - CGFloat(totalSegments - 1) * spacing) / CGFloat(totalSegments)

                    ZStack(alignment: .leading) {
                        HStack(spacing: spacing) {
                            ForEach(0..<totalSegments, id: \.self) { i in
                                let threshold = CGFloat(i + 1) / CGFloat(totalSegments)
                                let isLit = activeCharge >= threshold || (activeCharge > 0 && i == 0)
                                let segColor: Color = {
                                    if isBlocked { return .orange }
                                    if i < 8 { return palette.primaryAccent }
                                    if i < 18 { return Color(red: 0.25, green: 0.92, blue: 0.75) }
                                    return .green
                                }()
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(isLit ? segColor : Color.white.opacity(0.08))
                                    .frame(width: max(segWidth, 4), height: 8)
                            }
                        }
                        .animation(.linear(duration: 0.04), value: activeCharge)

                        HStack {
                            Spacer()
                            Text(activeCharge >= 1.0 ? "🔓 已展开 (100%)" : "🔒 触发线 100%")
                                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                                .foregroundColor(activeCharge >= 1.0 ? .green : .white.opacity(0.55))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.black.opacity(0.75))
                                .cornerRadius(3)
                        }
                    }
                }
                .frame(height: 10)
            }
            .padding(7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.black.opacity(0.40))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(chargeColor.opacity(0.32), lineWidth: 0.9)
                    )
            )

            // 2. Parameter Meter(s): Focused Active Mode Meter by default, or Side-by-Side Dual Meters on demand
            if showBothParameterMeters {
                HStack(spacing: 8) {
                    hoverTimeMeterCard
                    antiMistouchMeterCard
                }
            } else {
                if store.edgeTriggerMode == .hoverDwell {
                    hoverTimeMeterCard
                } else {
                    antiMistouchMeterCard
                }
            }
        }
    }

    private var hoverTimeMeterCard: some View {
        let norm = CGFloat((store.customInitialDwellMs - 50.0) / 350.0)
        let speedLabel: String = {
            if store.customInitialDwellMs <= 90 { return "⚡ 极速响应" }
            if store.customInitialDwellMs <= 180 { return "🎯 黄金均衡" }
            if store.customInitialDwellMs <= 280 { return "🛡️ 沉稳防抖" }
            return "🔒 强力防误触"
        }()

        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "timer")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundColor(palette.primaryAccent)
                    Text("Hover 悬停时间 Meter")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                Spacer()
                Text("\(Int(store.customInitialDwellMs)) ms · \(speedLabel)")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundColor(palette.primaryAccent)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(palette.primaryAccent.opacity(0.15))
                    .cornerRadius(4)
            }

            VStack(spacing: 2) {
                GeometryReader { geo in
                    let w = geo.size.width
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.white.opacity(0.08))
                            .frame(height: 7)

                        // Golden zone highlight (120ms ~ 200ms)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.green.opacity(0.22))
                            .frame(width: w * 0.25, height: 7)
                            .offset(x: w * 0.20)

                        RoundedRectangle(cornerRadius: 3)
                            .fill(
                                LinearGradient(
                                    colors: [palette.primaryAccent, .green],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(6, w * norm), height: 7)

                        Circle()
                            .fill(Color.white)
                            .frame(width: 10, height: 10)
                            .shadow(color: palette.primaryAccent, radius: 2)
                            .offset(x: min(max(0, w * norm - 5), w - 10))
                    }
                }
                .frame(height: 10)

                Slider(value: Binding(
                    get: { store.customInitialDwellMs },
                    set: { val in
                        isMistouchBlockedAlert = false
                        store.customInitialDwellMs = val
                        store.edgeTriggerSensitivity = .custom
                        store.edgeTriggerMode = .hoverDwell
                        store.onboardingGateTargetValue = Int(val)
                        store.savePersistentState()
                    }
                ), in: 50...400, step: 10)
                .controlSize(.mini)
                .tint(palette.primaryAccent)
                .accessibilityLabel("Hover 悬停时间")
            }

            HStack(spacing: 3) {
                ForEach([(80.0, "80ms 极速"), (150.0, "150ms 推荐"), (240.0, "240ms 稳健"), (360.0, "360ms 防抖")], id: \.0) { val, label in
                    let isCurrent = abs(store.customInitialDwellMs - val) < 15
                    Button {
                        withAnimation(PurahMotionPolicy.surface) {
                            isMistouchBlockedAlert = false
                            store.customInitialDwellMs = val
                            store.edgeTriggerSensitivity = .custom
                            store.edgeTriggerMode = .hoverDwell
                            store.onboardingGateTargetValue = Int(val)
                            store.savePersistentState()
                            store.triggerControlHaptic(.alignment)
                        }
                    } label: {
                        Text(label)
                            .font(.system(size: 8, weight: isCurrent ? .bold : .medium, design: .monospaced))
                            .foregroundColor(isCurrent ? .black : .white.opacity(0.75))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 2.5)
                            .background(isCurrent ? palette.primaryAccent : Color.white.opacity(0.07))
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.035))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(store.edgeTriggerMode == .hoverDwell ? palette.primaryAccent.opacity(0.55) : Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private var antiMistouchMeterCard: some View {
        let norm = CGFloat((store.customPushResistanceBarrier - 16.0) / 56.0)
        let armorLabel: String = {
            if store.customPushResistanceBarrier <= 22 { return "🪶 轻触级" }
            if store.customPushResistanceBarrier <= 40 { return "⚖️ 黄金阻尼" }
            if store.customPushResistanceBarrier <= 56 { return "🛡️ 强防误触" }
            return "🏰 重装锁定"
        }()

        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundColor(.orange)
                    Text("防误触阻力墙 Meter")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                Spacer()
                Text("\(Int(store.customPushResistanceBarrier)) px · \(armorLabel)")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundColor(.orange)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Color.orange.opacity(0.16))
                    .cornerRadius(4)
            }

            VStack(spacing: 2) {
                GeometryReader { geo in
                    let w = geo.size.width
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.white.opacity(0.08))
                            .frame(height: 7)

                        RoundedRectangle(cornerRadius: 3)
                            .fill(
                                LinearGradient(
                                    colors: [.yellow, .orange, .red],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(6, w * norm), height: 7)

                        Circle()
                            .fill(Color.white)
                            .frame(width: 10, height: 10)
                            .shadow(color: .orange, radius: 2)
                            .offset(x: min(max(0, w * norm - 5), w - 10))
                    }
                }
                .frame(height: 10)

                Slider(value: Binding(
                    get: { store.customPushResistanceBarrier },
                    set: { val in
                        isMistouchBlockedAlert = false
                        store.customPushResistanceBarrier = val
                        store.edgeTriggerSensitivity = .custom
                        store.edgeTriggerMode = .pushForce
                        store.onboardingGateTargetValue = Int(val)
                        store.savePersistentState()
                    }
                ), in: 16...72, step: 4)
                .controlSize(.mini)
                .tint(.orange)
                .accessibilityLabel("防误触阻力墙")
            }

            HStack(spacing: 3) {
                ForEach([(20.0, "20px 轻柔"), (24.0, "24px 默认"), (36.0, "36px 推荐"), (52.0, "52px 强阻")], id: \.0) { val, label in
                    let isCurrent = abs(store.customPushResistanceBarrier - val) < 3
                    Button {
                        withAnimation(PurahMotionPolicy.surface) {
                            isMistouchBlockedAlert = false
                            store.customPushResistanceBarrier = val
                            store.edgeTriggerSensitivity = .custom
                            store.edgeTriggerMode = .pushForce
                            store.onboardingGateTargetValue = Int(val)
                            store.savePersistentState()
                            store.triggerControlHaptic(.alignment)
                        }
                    } label: {
                        Text(label)
                            .font(.system(size: 8, weight: isCurrent ? .bold : .medium, design: .monospaced))
                            .foregroundColor(isCurrent ? .black : .white.opacity(0.75))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 2.5)
                            .background(isCurrent ? Color.orange : Color.white.opacity(0.07))
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.035))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(store.edgeTriggerMode == .pushForce ? Color.orange.opacity(0.65) : Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func startLiveDemonstrationCharge() {
        chargeTimer?.invalidate()
        isMistouchBlockedAlert = false
        liveHoverCharge = 0.0
        livePushCharge = 0.0

        let totalMs = max(store.customInitialDwellMs, 50.0)
        let stepMs: Double = 16.0
        let increment = CGFloat(stepMs / totalMs)

        meterStatusText = (store.edgeTriggerMode == .hoverDwell)
            ? "⏳ 正在边缘悬停蓄力 (0 / \(Int(totalMs)) ms)…"
            : "🛡️ 正在推压边缘阻力墙 (0 / \(Int(store.customPushResistanceBarrier)) px)…"

        chargeTimer = Timer.scheduledTimer(withTimeInterval: stepMs / 1000.0, repeats: true) { timer in
            Task { @MainActor in
                let next = min(self.liveHoverCharge + increment, 1.0)
                self.liveHoverCharge = next
                self.livePushCharge = next
                if next < 1.0 {
                    let elapsed = Int(Double(next) * totalMs)
                    self.meterStatusText = "⏳ 蓄力中：\(elapsed) / \(Int(totalMs)) ms (\(Int(next * 100))%)"
                } else {
                    self.chargeTimer?.invalidate()
                    self.chargeTimer = nil
                    self.meterStatusText = "✅ 达到阈值，抽屉已解锁滑出！"
                    withAnimation(PurahMotionPolicy.drawerEntrance) {
                        self.store.onboardingDidTriggerEdgeDrawer = true
                        if let firstRight = self.store.pods.first(where: { $0.edge == .right && $0.isEnabled }) {
                            self.store.activateDrawer(podId: firstRight.id)
                        }
                    }
                }
            }
        }
    }

    private func simulateFastFlickMistouch() {
        chargeTimer?.invalidate()
        chargeTimer = nil
        store.dismissActiveDrawer()
        isMistouchBlockedAlert = true
        liveHoverCharge = 0.20
        livePushCharge = 0.25
        meterStatusText = "🚫 [防误触拦截生效] 检测到快速甩动光标，驻留不足 \(Int(store.customInitialDwellMs))ms，已自动屏蔽！"
    }

    // MARK: - Act 2: 预设与位置调整 (Presets & Progressive 3-Column Position/Height Workbench)

    private var act2PickOrCustomRigBody: some View {
        let showFullWorkbench = (selectedRigMode == .custom) || isCustomWorkbenchExpanded

        return VStack(alignment: .leading, spacing: 8) {
            // Top Row: 4 Rig Mode Preset Cards
            HStack(spacing: 6) {
                ForEach(OnboardingRigPreset.allCases) { preset in
                    rigPresetCard(preset)
                }
            }

            if showFullWorkbench {
                // Header bar for expanded 3-column workbench
                HStack(spacing: 6) {
                    Image(systemName: "slider.vertical.3")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundColor(palette.primaryAccent)
                    Text("三栏位置与高矮工作台：点击 ↑/↓ 调整上下顺序，点击百分比调节高度，点击 ⇄ 切换左右边缘")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.82))
                    Spacer()
                    if selectedRigMode != .custom {
                        Button {
                            withAnimation(PurahMotionPolicy.surface) {
                                isCustomWorkbenchExpanded = false
                                store.triggerControlHaptic(.alignment)
                            }
                        } label: {
                            Text("收起三栏工作台 ▴")
                                .font(.system(size: 8.5, weight: .bold, design: .rounded))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2.5)
                                .background(Color.white.opacity(0.08))
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // 3-Column Position & Height Workbench
                HStack(alignment: .top, spacing: 7) {
                    // Column 1: Left Rail
                    railColumnView(title: "◀ 左轨位置顺序 (上→下)", accent: palette.primaryAccent, edge: .left)

                    // Column 2: Unmounted Library
                    unmountedLibraryColumn

                    // Column 3: Right Rail
                    railColumnView(title: "右轨位置顺序 (上→下) ▶", accent: .orange, edge: .right)
                }
            } else {
                // Clean, Scannable Left/Right Summary Preview + One-Click Expand Workbench Button
                compactRigSummaryCard
            }
        }
    }

    private var compactRigSummaryCard: some View {
        let leftPods = store.pods.filter { $0.edge == .left && $0.isEnabled }
            .sorted { $0.range.start < $1.range.start }
        let rightPods = store.pods.filter { $0.edge == .right && $0.isEnabled }
            .sorted { $0.range.start < $1.range.start }

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                compactRailPreviewBox(title: "◀ 左侧屏幕边缘 (从上到下 \(leftPods.count) 个模块)", pods: leftPods, accent: palette.primaryAccent)
                compactRailPreviewBox(title: "右侧屏幕边缘 (从上到下 \(rightPods.count) 个模块) ▶", pods: rightPods, accent: .orange)
            }

            HStack {
                Text("💡 想要调整某个插件的上下顺序、高矮比例，或增删模块？")
                    .font(.system(size: 9.5, design: .rounded))
                    .foregroundColor(.secondary)

                Spacer()

                Button {
                    withAnimation(PurahMotionPolicy.surface) {
                        isCustomWorkbenchExpanded = true
                        store.triggerControlHaptic(.alignment)
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up.and.down.text.horizontal")
                            .font(.system(size: 9.5, weight: .bold))
                        Text("🛠️ 展开三栏工作台：调整每个插件位置与高矮 ▾")
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background(palette.primaryAccent)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(0.035))
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
        )
    }

    private func compactRailPreviewBox(title: String, pods: [SlotPod], accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundColor(accent)

            FlowLayoutPodsPreview(pods: pods, store: store, palette: palette)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.black.opacity(0.28))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(accent.opacity(0.25), lineWidth: 1)
                )
        )
    }

    private func rigPresetCard(_ preset: OnboardingRigPreset) -> some View {
        let isSel = (selectedRigMode == preset)
        let accentColor: Color = {
            switch preset {
            case .developer: return palette.primaryAccent
            case .creator: return Color(red: 0.98, green: 0.52, blue: 0.24)
            case .minimal: return Color(red: 0.35, green: 0.88, blue: 0.62)
            case .custom: return Color(red: 0.85, green: 0.45, blue: 0.98)
            }
        }()

        return Button {
            withAnimation(PurahMotionPolicy.surface) {
                selectedRigMode = preset
                if preset == .custom {
                    isCustomWorkbenchExpanded = true
                    positionActionFeedback = "🛠️ 已展开自由自定义工作台，可按需调整每个插件的上下顺序、高矮与左右归属"
                } else {
                    store.applyOnboardingRigPreset(preset)
                    positionActionFeedback = "✅ 已套用「\(preset.title)」预设"
                }
                store.triggerControlHaptic(.alignment)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: preset.icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(accentColor)
                    .frame(width: 22, height: 22)
                    .background(accentColor.opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 5))

                VStack(alignment: .leading, spacing: 1) {
                    Text(preset.title)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text(preset.subtitle)
                        .font(.system(size: 8.5, design: .rounded))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(6)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSel ? accentColor.opacity(0.16) : Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSel ? accentColor : Color.white.opacity(0.08), lineWidth: isSel ? 1.4 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func railColumnView(title: String, accent: Color, edge: MountEdge) -> some View {
        let railPods = store.pods.filter { $0.edge == edge && $0.isEnabled }
            .sorted { $0.range.start < $1.range.start }

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundColor(accent)
                Spacer()
                Text("↑↓换位 · 百分比调高")
                    .font(.system(size: 8, design: .rounded))
                    .foregroundColor(.secondary)
            }

            if railPods.isEmpty {
                Text("空轨道（从中间点 +左轨 / +右轨 添加）")
                    .font(.system(size: 9, design: .rounded))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                ForEach(Array(railPods.enumerated()), id: \.element.id) { idx, pod in
                    mountedRow(pod: pod, index: idx, totalCount: railPods.count, accent: accent)
                }
            }
        }
        .padding(7)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.03))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(accent.opacity(0.25), lineWidth: 1))
        )
    }

    private func mountedRow(pod: SlotPod, index: Int, totalCount: Int, accent: Color) -> some View {
        let podColor = palette.podColor(for: pod.id, store: store)
        let zoneLabel: String = (index == 0) ? "顶部" : (index == totalCount - 1 && totalCount > 2 ? "底部" : "顺手区")

        return HStack(spacing: 3) {
            Text(zoneLabel)
                .font(.system(size: 7.5, weight: .bold, design: .rounded))
                .foregroundColor(zoneLabel == "顺手区" ? .yellow : .secondary)
                .frame(width: 28, alignment: .leading)

            Image(systemName: pod.systemIcon)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(podColor)

            Text(pod.name)
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)

            Spacer(minLength: 2)

            // Reorder Up
            Button {
                withAnimation(PurahMotionPolicy.surface) {
                    selectedRigMode = .custom
                    store.movePodInOrder(id: pod.id, direction: -1)
                    positionActionFeedback = "✅ 已将「\(pod.name)」上移"
                    store.triggerControlHaptic(.alignment)
                }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(index > 0 ? .white : .secondary.opacity(0.25))
                    .frame(width: 15, height: 15)
                    .background(Color.white.opacity(index > 0 ? 0.12 : 0.03))
                    .cornerRadius(3)
            }
            .buttonStyle(.plain)
            .disabled(index == 0)
            .help("上移位置")

            // Reorder Down
            Button {
                withAnimation(PurahMotionPolicy.surface) {
                    selectedRigMode = .custom
                    store.movePodInOrder(id: pod.id, direction: 1)
                    positionActionFeedback = "✅ 已将「\(pod.name)」下移"
                    store.triggerControlHaptic(.alignment)
                }
            } label: {
                Image(systemName: "arrow.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(index < totalCount - 1 ? .white : .secondary.opacity(0.25))
                    .frame(width: 15, height: 15)
                    .background(Color.white.opacity(index < totalCount - 1 ? 0.12 : 0.03))
                    .cornerRadius(3)
            }
            .buttonStyle(.plain)
            .disabled(index >= totalCount - 1)
            .help("下移位置")

            // Height Stretch Badge (- / +)
            Button {
                withAnimation(PurahMotionPolicy.surface) {
                    selectedRigMode = .custom
                    let delta = (pod.range.length >= 0.32) ? -0.08 : 0.06
                    store.adjustPodLength(id: pod.id, delta: delta)
                    positionActionFeedback = "📐 已调整「\(pod.name)」高度占比为 \(Int(pod.range.length * 100))%"
                    store.triggerControlHaptic(.alignment)
                }
            } label: {
                Text("\(Int(pod.range.length * 100))%")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.yellow)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1.5)
                    .background(Color.yellow.opacity(0.14))
                    .cornerRadius(3)
            }
            .buttonStyle(.plain)
            .help("点击调节高度占比（轨道多长 = 弹出的抽屉多高）")

            // Flip Left <-> Right Edge
            Button {
                withAnimation(PurahMotionPolicy.surface) {
                    selectedRigMode = .custom
                    store.flipPodEdge(id: pod.id)
                    positionActionFeedback = "⇄ 已将「\(pod.name)」换至另一侧轨道"
                    store.triggerControlHaptic(.alignment)
                }
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundColor(palette.primaryAccent)
                    .frame(width: 15, height: 15)
                    .background(palette.primaryAccent.opacity(0.14))
                    .cornerRadius(3)
            }
            .buttonStyle(.plain)
            .help("切换至另一侧屏幕边缘")

            // Unmount
            Button {
                withAnimation(PurahMotionPolicy.surface) {
                    selectedRigMode = .custom
                    store.unmountPod(id: pod.id)
                    positionActionFeedback = "➖ 已收起「\(pod.name)」至待命库"
                    store.triggerControlHaptic(.alignment)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 14, height: 15)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(3)
            }
            .buttonStyle(.plain)
            .help("暂不启用此模块")
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3.5)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.white.opacity(0.05))
        )
    }

    private var unmountedLibraryColumn: some View {
        let unmounted = store.pods.filter { !$0.isEnabled }

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("📦 待命模块库")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    withAnimation(PurahMotionPolicy.surface) {
                        store.autoLayoutAll()
                        positionActionFeedback = "✨ 已执行人体工学智能排布！"
                        store.triggerControlHaptic(.alignment)
                    }
                } label: {
                    Text("✨ 智能排布")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundColor(.yellow)
                }
                .buttonStyle(.plain)
            }

            if unmounted.isEmpty {
                Text("全部模块已挂载至两侧轨道")
                    .font(.system(size: 9, design: .rounded))
                    .foregroundColor(.green)
                    .frame(maxWidth: .infinity, minHeight: 70)
            } else {
                ForEach(unmounted) { pod in
                    let podColor = palette.podColor(for: pod.id, store: store)
                    HStack(spacing: 4) {
                        Image(systemName: pod.systemIcon)
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundColor(podColor)
                        Text(pod.name)
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.85))
                            .lineLimit(1)
                        Spacer()
                        Button {
                            withAnimation(PurahMotionPolicy.surface) {
                                selectedRigMode = .custom
                                store.mountPod(id: pod.id, to: .left)
                                positionActionFeedback = "➕ 已将「\(pod.name)」挂载至左轨"
                                store.triggerControlHaptic(.alignment)
                            }
                        } label: {
                            Text("+左轨")
                                .font(.system(size: 8, weight: .bold, design: .rounded))
                                .foregroundColor(palette.primaryAccent)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1.5)
                                .background(palette.primaryAccent.opacity(0.15))
                                .cornerRadius(3)
                        }
                        .buttonStyle(.plain)

                        Button {
                            withAnimation(PurahMotionPolicy.surface) {
                                selectedRigMode = .custom
                                store.mountPod(id: pod.id, to: .right)
                                positionActionFeedback = "➕ 已将「\(pod.name)」挂载至右轨"
                                store.triggerControlHaptic(.alignment)
                            }
                        } label: {
                            Text("+右轨")
                                .font(.system(size: 8, weight: .bold, design: .rounded))
                                .foregroundColor(.orange)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1.5)
                                .background(Color.orange.opacity(0.15))
                                .cornerRadius(3)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3.5)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.03)))
                }
            }
        }
        .padding(7)
        .frame(width: 185, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.02))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08), lineWidth: 1))
        )
    }

    // MARK: - Act 3: 进阶空间技巧 (5 Core Spatial Mechanics)

    private enum GrammarTab: String, CaseIterable, Identifiable {
        case positionResize = "positionResize"
        case decompose = "decompose"
        case stack = "stack"
        case pages = "pages"
        case breathing = "breathing"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .positionResize: return "1. 位置与高矮"
            case .decompose: return "2. 独立胶囊 (分解)"
            case .stack: return "3. 共享抽屉 (堆叠)"
            case .pages: return "4. 多页翻页"
            case .breathing: return "5. 自动伸缩 (呼吸)"
            }
        }

        var badge: String {
            switch self {
            case .positionResize: return "上下换位 · 轨长=抽屉高"
            case .decompose: return "多项内容独立秒开"
            case .stack: return "多插件合一省空间"
            case .pages: return "上下传送门切页"
            case .breathing: return "平时收拢 · 悬停舒展"
            }
        }

        var icon: String {
            switch self {
            case .positionResize: return "arrow.up.and.down.text.horizontal"
            case .decompose: return "rectangle.split.1x2.fill"
            case .stack: return "square.stack.3d.up.fill"
            case .pages: return "book.pages.fill"
            case .breathing: return "lungs.fill"
            }
        }

        var color: Color {
            switch self {
            case .positionResize: return .yellow
            case .decompose: return .cyan
            case .stack: return .orange
            case .pages: return .purple
            case .breathing: return .mint
            }
        }

        var guideText: String {
            switch self {
            case .positionResize:
                return "【位置与等高法则】你既可以在两侧轨道上直接上下拖拽换位、拖拽底边拉长高度，也可点击右侧按钮体验：拉长轨道条 = 同步拉高弹出的抽屉！"
            case .decompose:
                return "【独立胶囊 (分解)】看左侧的『Vitals 硬件遥测』：开启分解后，一条长轨裂变为 CPU、内存、网络独立胶囊，悬停哪枚就单独滑出哪枚！"
            case .stack:
                return "【共享抽屉 (堆叠)】你的默认布局已内置三组黄金堆叠（左轨『暂存+剪贴+便签』、右顶『日历+待办』、右底『终端+音乐+脚本』），共享同一个抽屉并通过顶部 Tab 秒切！"
            case .pages:
                return "【多页翻页】当单侧插件较多时，轨道上下两端会出现『▲ 1/2 ▼ 翻页传送门』，悬停或点击即可切换到第 2 页轨道！"
            case .breathing:
                return "【自动伸缩 (呼吸)】当一条轨道挂载了较多模块时，平时会自动收拢；鼠标滑过哪个模块，哪个模块就像手风琴一样原地舒展放大！"
            }
        }
    }

    private var act3CoreGrammarBody: some View {
        VStack(alignment: .leading, spacing: 9) {
            // 5 Skill Tab Cards
            HStack(spacing: 6) {
                ForEach(GrammarTab.allCases) { tab in
                    let isSel = (activeGrammarTab == tab)
                    let isDone = completedGrammarTabs.contains(tab)
                    Button {
                        withAnimation(PurahMotionPolicy.surface) {
                            activeGrammarTab = tab
                            store.onboardingActiveGrammarSubstep = tab.rawValue
                            completedGrammarTabs.insert(tab)
                            applyGrammarLiveEffect(tab)
                            store.triggerControlHaptic(.alignment)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Image(systemName: tab.icon)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(tab.color)
                                Spacer()
                                if isDone {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 9))
                                        .foregroundColor(.green)
                                }
                            }
                            Text(tab.title)
                                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            Text(tab.badge)
                                .font(.system(size: 8, weight: .semibold, design: .rounded))
                                .foregroundColor(tab.color)
                                .lineLimit(1)
                        }
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isSel ? tab.color.opacity(0.16) : Color.white.opacity(0.04))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(isSel ? tab.color : Color.white.opacity(0.08), lineWidth: isSel ? 1.4 : 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            // Interactive Live Control Row for Selected Grammar Skill
            HStack(spacing: 10) {
                Text(activeGrammarTab.guideText)
                    .font(.system(size: 9.5, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                grammarActionControls(activeGrammarTab)
            }
            .padding(9)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(activeGrammarTab.color.opacity(0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(activeGrammarTab.color.opacity(0.4), lineWidth: 1)
                    )
            )
        }
        .onAppear {
            store.onboardingActiveGrammarSubstep = activeGrammarTab.rawValue
        }
    }

    @ViewBuilder
    private func grammarActionControls(_ tab: GrammarTab) -> some View {
        switch tab {
        case .positionResize:
            HStack(spacing: 5) {
                Button {
                    withAnimation(PurahMotionPolicy.surface) {
                        if let first = store.pods.first(where: { $0.edge == .left && $0.isEnabled }) {
                            store.movePodInOrder(id: first.id, direction: 1)
                        }
                        store.triggerControlHaptic(.alignment)
                    }
                } label: {
                    Text("⇅ 演示换位")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.yellow)
                        .cornerRadius(5)
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(PurahMotionPolicy.surface) {
                        let targetId = store.activeDrawerPodId ?? "terminal"
                        let curLen = store.pods.first(where: { $0.id == targetId })?.range.length ?? 0.20
                        store.adjustPodLength(id: targetId, delta: curLen >= 0.30 ? -0.10 : 0.08)
                        store.triggerControlHaptic(.alignment)
                    }
                } label: {
                    Text("⇕ 演示拉高")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(.yellow)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.yellow.opacity(0.18))
                        .cornerRadius(5)
                }
                .buttonStyle(.plain)
            }

        case .decompose:
            let isVitalsDecomp = store.isPodDecomposed("vitals")
            Button {
                withAnimation(PurahMotionPolicy.surface) {
                    store.togglePodDecomposedInSculptor(podId: "vitals")
                    store.triggerControlHaptic(.alignment)
                }
            } label: {
                Text(isVitalsDecomp ? "切换回：整条长轨 (Bar)" : "切换为：3枚独立胶囊 (Chips)")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundColor(.black)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.cyan)
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)

        case .stack:
            Button {
                withAnimation(PurahMotionPolicy.surface) {
                    store.rehearseStackMerge()
                    store.triggerControlHaptic(.alignment)
                }
            } label: {
                Text("演示左轨模块磁吸堆叠")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundColor(.black)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.orange)
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)

        case .pages:
            Button {
                withAnimation(PurahMotionPolicy.surface) {
                    store.cycleRailPage(for: .right)
                    store.triggerControlHaptic(.alignment)
                }
            } label: {
                Text("翻转右轨页码 (当前 Page \(store.rightRailPage + 1))")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.purple)
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)

        case .breathing:
            Button {
                withAnimation(PurahMotionPolicy.surface) {
                    store.setDynamicBreathingEnabled(!store.isDynamicBreathingEnabled)
                    store.triggerControlHaptic(.alignment)
                }
            } label: {
                Text(store.isDynamicBreathingEnabled ? "自动伸缩中 (点击关闭)" : "开启自动伸缩演示")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundColor(.black)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.mint)
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
    }

    private func applyGrammarLiveEffect(_ tab: GrammarTab) {
        store.onboardingActiveGrammarSubstep = tab.rawValue
        switch tab {
        case .positionResize:
            break
        case .decompose:
            if !store.pods.contains(where: { $0.id == "vitals" && $0.isEnabled }) {
                store.mountPod(id: "vitals", to: .left)
            }
        case .stack:
            break
        case .pages:
            store.rehearsePaginationFlip()
        case .breathing:
            store.setDynamicBreathingEnabled(true)
        }
    }

    // MARK: - Act 4: App 智能场景调度 (App-Aware Context Profiles - Non-Destructive Sandbox)

    public enum OnboardingSimulatedApp: String, CaseIterable, Identifiable {
        case xcode = "xcode"
        case safari = "safari"
        case figma = "figma"

        public var id: String { rawValue }

        public var appName: String {
            switch self {
            case .xcode: return "Xcode / Cursor"
            case .safari: return "Safari / Arc 浏览器"
            case .figma: return "Figma / Apple Music"
            }
        }

        public var bundleIcon: String {
            switch self {
            case .xcode: return "hammer.fill"
            case .safari: return "safari.fill"
            case .figma: return "paintpalette.fill"
            }
        }

        public var profileName: String {
            switch self {
            case .xcode: return "Coding 极客场景"
            case .safari: return "Research 收集场景"
            case .figma: return "Creative 灵感场景"
            }
        }

        public var accent: Color {
            switch self {
            case .xcode: return .cyan
            case .safari: return .blue
            case .figma: return .pink
            }
        }

        public var description: String {
            switch self {
            case .xcode: return "自动挂载：左轨 [Vitals + Terminal + Scripts] · 右轨 [AI + Clipboard]"
            case .safari: return "自动挂载：左轨 [Drop Shelf 暂存架 + Notes 便签] · 右轨 [AI 摘要 + Clipboard]"
            case .figma: return "自动挂载：左轨 [Music 黑胶 + Drop Shelf] · 右轨 [Calendar 日程 + Todo 待办]"
            }
        }
    }

    private var act4AppContextSwitchBody: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles.tv.fill")
                        .foregroundColor(palette.primaryAccent)
                        .font(.system(size: 11))
                    Text("点击下方模拟切换前台软件，在两侧轨道预览场景自动变身效果：")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                }
                Spacer()
                Toggle("开启随前台 App 自动切换", isOn: Binding(
                    get: { store.isAppProfileSwitchingEnabled },
                    set: { val in
                        store.isAppProfileSwitchingEnabled = val
                        store.savePersistentState()
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
            }

            HStack(spacing: 8) {
                ForEach(OnboardingSimulatedApp.allCases) { app in
                    let isSel = (simulatedFrontmostApp == app && store.isUsingTemporaryDemoSandbox)
                    Button {
                        withAnimation(PurahMotionPolicy.surface) {
                            simulatedFrontmostApp = app
                            applySimulatedAppProfile(app)
                            appSwitchBannerText = "🎯 正在预览「\(app.profileName)」(离开此步将自动恢复你的第 2 步默认布局)"
                            store.triggerControlHaptic(.alignment)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Image(systemName: app.bundleIcon)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(app.accent)
                                    .frame(width: 24, height: 24)
                                    .background(app.accent.opacity(0.18))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                Spacer()
                                Text(app.profileName)
                                    .font(.system(size: 8.5, weight: .bold, design: .rounded))
                                    .foregroundColor(isSel ? .black : app.accent)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(isSel ? app.accent : app.accent.opacity(0.15))
                                    .clipShape(Capsule())
                            }

                            Text("预览切到 \(app.appName)")
                                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                                .foregroundColor(.white)

                            Text(app.description)
                                .font(.system(size: 8.5, design: .rounded))
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(isSel ? app.accent.opacity(0.15) : Color.white.opacity(0.04))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 9)
                                        .stroke(isSel ? app.accent : Color.white.opacity(0.08), lineWidth: isSel ? 1.4 : 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "shield.checkered")
                    .font(.system(size: 9.5))
                    .foregroundColor(palette.primaryAccent)
                Text("安全沙盒保障：上方场景仅为临时预览，不会覆盖你在第 2 步设好的默认布局；当你正在抽屉内输入时，后台切换 App 也不会打断你。")
                    .font(.system(size: 9, design: .rounded))
                    .foregroundColor(.secondary)

                Spacer()

                if store.isUsingTemporaryDemoSandbox {
                    Button {
                        withAnimation(PurahMotionPolicy.surface) {
                            store.restoreUserLayoutSnapshotIfNeeded()
                            appSwitchBannerText = "✅ 已恢复你在第 2 步设好的默认布局"
                            store.triggerControlHaptic(.alignment)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.uturn.backward.circle.fill")
                                .font(.system(size: 9))
                            Text("立即恢复我的第 2 步布局")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(.black)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color.green)
                        .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func applySimulatedAppProfile(_ app: OnboardingSimulatedApp) {
        // Save the user's Act 2 layout before applying temporary scene preview!
        store.saveUserLayoutSnapshotIfNeeded()
        store.isUsingTemporaryDemoSandbox = true

        let leftIds: [String]
        let rightIds: [String]
        switch app {
        case .xcode:
            leftIds = ["vitals", "terminal", "scripts"]
            rightIds = ["ai", "clipboard"]
        case .safari:
            leftIds = ["shelf", "notes"]
            rightIds = ["ai", "clipboard"]
        case .figma:
            leftIds = ["music", "shelf"]
            rightIds = ["calendar", "todo"]
        }

        for idx in store.pods.indices {
            let id = store.pods[idx].id
            if let lPos = leftIds.firstIndex(of: id) {
                store.pods[idx].isEnabled = true
                store.pods[idx].edge = .left
                store.pods[idx].majorGroupId = nil
                store.pods[idx].pageIndex = 0
                store.pods[idx].range.start = Double(lPos) * 0.30 + 0.04
                store.pods[idx].range.length = 0.26
            } else if let rPos = rightIds.firstIndex(of: id) {
                store.pods[idx].isEnabled = true
                store.pods[idx].edge = .right
                store.pods[idx].majorGroupId = nil
                store.pods[idx].pageIndex = 0
                store.pods[idx].range.start = Double(rPos) * 0.30 + 0.04
                store.pods[idx].range.length = 0.26
            } else {
                store.pods[idx].isEnabled = false
            }
        }
        store.autoLayoutAll()
    }

    // MARK: - Act 5: 按需权限连接 (Connect Permissions)

    private struct PermissionDisplayItem: Identifiable {
        let permission: PluginPermission
        let name: String
        let icon: String
        let usedBy: String

        var id: String { permission.rawValue }
    }

    private var activePermissionItems: [PermissionDisplayItem] {
        let enabledIds = Set(store.pods.compactMap { $0.isEnabled ? $0.id : nil })
        var items: [PermissionDisplayItem] = [
            PermissionDisplayItem(permission: .fileSystem, name: "辅助功能与边缘阻力监测", icon: "hand.point.up.braille.fill", usedBy: "边缘轻推突破 (Push Force) 与全局快捷键")
        ]
        if enabledIds.contains("calendar") {
            items.append(PermissionDisplayItem(permission: .calendar, name: "日历访问权限 (Calendar)", icon: "calendar.badge.clock", usedBy: "Calendar 边缘日程芯片与会议提醒"))
        }
        if enabledIds.contains("todo") {
            items.append(PermissionDisplayItem(permission: .reminders, name: "提醒事项权限 (Reminders)", icon: "checklist.checked", usedBy: "Reminders 待办事项双向同步"))
        }
        if enabledIds.contains("terminal") || enabledIds.contains("scripts") {
            items.append(PermissionDisplayItem(permission: .shellExecution, name: "终端与自动化权限", icon: "terminal.fill", usedBy: "Terminal ?? 命令生成与 Script Runway 执行"))
        }
        if enabledIds.contains("music") {
            items.append(PermissionDisplayItem(permission: .appleMusic, name: "系统媒体播放控制", icon: "music.note.list", usedBy: "Music 黑胶唱片封面与实时音频波形"))
        }
        return items
    }

    private var act5PermissionsBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(activePermissionItems) { item in
                let status = PermissionManager.shared.status(for: item.permission)
                let isGranted = (status == .authorized) || grantedPermissions.contains(item.permission)

                HStack(spacing: 9) {
                    Image(systemName: item.icon)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(isGranted ? .green : palette.primaryAccent)
                        .frame(width: 24, height: 24)
                        .background((isGranted ? Color.green : palette.primaryAccent).opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.name)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text(item.usedBy)
                            .font(.system(size: 8.5, design: .rounded))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button {
                        Task { @MainActor in
                            store.triggerControlHaptic(.levelChange)
                            let ok = await PermissionManager.shared.requestAccess(for: item.permission)
                            if ok {
                                grantedPermissions.insert(item.permission)
                                if item.permission == .calendar {
                                    SystemCalendarSyncService.shared.syncEvents(into: store)
                                } else if item.permission == .reminders {
                                    await SystemRemindersSyncService.shared.syncReminders(into: store)
                                }
                            }
                        }
                    } label: {
                        Text(isGranted ? "✓ 已授权" : "授权")
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .foregroundColor(isGranted ? .green : .black)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3.5)
                            .background(isGranted ? Color.green.opacity(0.16) : palette.primaryAccent)
                            .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                }
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.04)))
            }
        }
    }

    // MARK: - 4. Navigation Footer Row

    private var navigationFooter: some View {
        HStack(spacing: 10) {
            if store.onboardingStep != .feelTheEdge {
                Button {
                    withAnimation(PurahMotionPolicy.surface) {
                        store.previousOnboardingStep()
                        store.triggerControlHaptic(.alignment)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 8.5, weight: .bold))
                        Text("上一步")
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.10))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            if store.onboardingStep != .permissions {
                Button {
                    withAnimation(PurahMotionPolicy.surface) {
                        store.skipCurrentOnboardingStep()
                        store.triggerControlHaptic(.alignment)
                    }
                } label: {
                    Text("跳过此步")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(PurahMotionPolicy.surface) {
                        store.nextOnboardingStep()
                        store.triggerControlHaptic(.levelChange)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("下一步")
                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8.5, weight: .bold))
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(palette.primaryAccent)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    store.triggerControlHaptic(.levelChange)
                    store.completeOnboardingCoach()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text("完成引导，开启 Purah")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5.5)
                    .background(Color.green)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct FlowLayoutPodsPreview: View {
    let pods: [SlotPod]
    let store: PurahWorkspaceStore
    let palette: ThemePalette

    var body: some View {
        if pods.isEmpty {
            Text("当前未挂载模块")
                .font(.system(size: 8.5, design: .rounded))
                .foregroundColor(.secondary)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(Array(pods.enumerated()), id: \.element.id) { idx, pod in
                        let podColor = palette.podColor(for: pod.id, store: store)
                        HStack(spacing: 4) {
                            Text("\(idx + 1)")
                                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                                .foregroundColor(.black)
                                .padding(.horizontal, 3.5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(podColor))

                            Image(systemName: pod.systemIcon)
                                .font(.system(size: 8.5, weight: .bold))
                                .foregroundColor(podColor)

                            Text(pod.name)
                                .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3.5)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(podColor.opacity(0.14))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .stroke(podColor.opacity(0.40), lineWidth: 0.8)
                                )
                        )
                    }
                }
            }
        }
    }
}

