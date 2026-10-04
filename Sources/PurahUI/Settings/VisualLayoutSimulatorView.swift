// Sources/PurahUI/Settings/VisualLayoutSimulatorView.swift
import SwiftUI
import PurahCore

public struct VisualLayoutSimulatorView: View {
    public let store: PurahWorkspaceStore

    private var theme: ThemeManager {
        ThemeManager.shared
    }

    public init(store: PurahWorkspaceStore) {
        self.store = store
    }

    public var body: some View {
        let palette = theme.palette

        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 16) {
                // Top Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Image(systemName: "slider.horizontal.2.square")
                                .foregroundColor(palette.primaryAccent)
                                .font(.title2)
                            Text("simulator.title".localized)
                                .font(palette.fontTitle)
                                .foregroundColor(palette.style == .native ? Color.primary : .white)
                        }
                        Text("simulator.subtitle".localized)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }

                    Spacer()

                    // “一键人体工学排布”按钮 (Magic Ergonomics Button)
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            store.autoLayoutAll()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                            Text("simulator.magicButton".localized)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(palette.style == .native ? Color.white : Color.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(palette.primaryAccent)
                        .cornerRadius(8)
                        .modifier(OptionalGlow(color: palette.primaryAccent, enabled: palette.useGlow))
                    }
                    .buttonStyle(.plain)
                }

                // 主题切换选择器 (Theme Style Picker: Native by default vs Purah Pad)
                HStack {
                    Text("界面主题风格:")
                        .font(palette.fontMono)
                        .foregroundColor(palette.primaryAccent)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { theme.currentStyle },
                        set: { theme.currentStyle = $0 }
                    )) {
                        ForEach(AppThemeStyle.allCases) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 340)
                }
                .padding(.horizontal, 4)

                // 动效风格选择器 (华丽磁吸联动默认 vs 极简轻量可选)
                HStack {
                    Text("边缘体感动效:")
                        .font(palette.fontMono)
                        .foregroundColor(palette.primaryAccent)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { store.animationStyle },
                        set: { store.animationStyle = $0 }
                    )) {
                        ForEach(AnimationStyle.allCases) { anim in
                            Text(anim.title).tag(anim)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 340)
                }
                .padding(.horizontal, 4)

                // 导轨微光条宽度自定义 (4px ~ 16px)
                HStack {
                    Text("导轨微光条宽度:")
                        .font(palette.fontMono)
                        .foregroundColor(palette.primaryAccent)
                    Slider(value: Binding(
                        get: { store.railBarWidth },
                        set: { store.railBarWidth = $0 }
                    ), in: 4.0...16.0, step: 1.0)
                    Text("\(Int(store.railBarWidth)) px")
                        .font(palette.fontMono)
                        .foregroundColor(.gray)
                        .frame(width: 45)
                }
                .padding(.horizontal, 4)

                // 各功能专属色彩自定义
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("各功能槽位专属色彩自定义:")
                            .font(palette.fontMono)
                            .foregroundColor(palette.primaryAccent)
                        Spacer()
                        Button("恢复默认色彩") {
                            store.customPodColors.removeAll()
                        }
                        .buttonStyle(.plain)
                        .font(.caption2)
                        .foregroundColor(.gray)
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 6) {
                        ForEach(store.pods) { pod in
                            HStack(spacing: 6) {
                                Image(systemName: pod.systemIcon)
                                    .font(.caption2)
                                    .foregroundColor(palette.podColor(for: pod.id, store: store))

                                Text(pod.name)
                                    .font(.caption2)
                                    .lineLimit(1)

                                Spacer()

                                ColorPicker("", selection: Binding(
                                    get: { palette.podColor(for: pod.id, store: store) },
                                    set: { newColor in
                                        if let hex = newColor.toHex() {
                                            store.setPodColorHex(podId: pod.id, hex: hex)
                                        }
                                    }
                                ))
                                .labelsHidden()
                                .scaleEffect(0.8)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(palette.surfaceBackground)
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(palette.podColor(for: pod.id, store: store).opacity(0.4), lineWidth: 1)
                            )
                        }
                    }
                }
                .padding(.horizontal, 4)

                // 模块启用与挂载装配区 (Pod Module Selection & Activation)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("边缘槽位模块装配 (点击勾选挂载 / 取消)")
                            .font(palette.fontMono)
                            .foregroundColor(palette.primaryAccent)
                        Spacer()
                        Text("已挂载 \(store.pods.filter { $0.isEnabled }.count)/\(store.pods.count)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.gray)
                    }

                    HStack(spacing: 8) {
                        ForEach(store.pods) { pod in
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                    store.togglePodEnabled(id: pod.id)
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: pod.isEnabled ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(pod.isEnabled ? palette.primaryAccent : .gray)
                                        .font(.caption)

                                    Image(systemName: pod.systemIcon)
                                        .font(.caption2)
                                        .foregroundColor(pod.isEnabled ? (palette.style == .native ? Color.primary : .white) : .gray)

                                    Text(pod.name)
                                        .font(.caption)
                                        .foregroundColor(pod.isEnabled ? (palette.style == .native ? Color.primary : .white) : .gray)

                                    Text(pod.edge == .left ? "左轨" : "右轨")
                                        .font(.system(size: 8, weight: .bold))
                                        .padding(.horizontal, 3)
                                        .padding(.vertical, 1)
                                        .background(pod.isEnabled ? palette.primaryAccent.opacity(0.15) : Color.gray.opacity(0.15))
                                        .foregroundColor(pod.isEnabled ? palette.primaryAccent : .gray)
                                        .cornerRadius(3)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(pod.isEnabled ? palette.surfaceBackground : Color(nsColor: .controlBackgroundColor).opacity(0.2))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(pod.isEnabled ? palette.primaryAccent.opacity(0.5) : palette.borderColor.opacity(0.4), lineWidth: 1)
                                )
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // 模拟器微缩屏幕
                ScreenSimulationCanvas(store: store)

                // 槽位内容精细化调整设置 (日历时间范围 & 待办分类过滤，在此统一配置)
                VStack(alignment: .leading, spacing: 8) {
                    Text("槽位内容显示偏好 (在设置中统一配置，侧边小窗纯粹展示)")
                        .font(palette.fontMono)
                        .foregroundColor(palette.primaryAccent)

                    HStack(spacing: 16) {
                        // 日历范围
                        VStack(alignment: .leading, spacing: 4) {
                            Text("日程表跨度:")
                                .font(.caption2)
                                .foregroundColor(.gray)
                            Picker("", selection: Binding(
                                get: { store.calendarScope },
                                set: { newScope in
                                    store.calendarScope = newScope
                                    SystemCalendarSyncService.shared.syncEvents(into: store, scope: newScope)
                                }
                            )) {
                                ForEach(CalendarTimeScope.allCases) { scope in
                                    Text(scope.title).tag(scope)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        // 待办范围
                        VStack(alignment: .leading, spacing: 4) {
                            Text("待办分类:")
                                .font(.caption2)
                                .foregroundColor(.gray)
                            Picker("", selection: Binding(
                                get: { store.remindersScope },
                                set: { newScope in
                                    store.remindersScope = newScope
                                    Task {
                                        await SystemRemindersSyncService.shared.syncReminders(into: store, scope: newScope)
                                    }
                                }
                            )) {
                                ForEach(RemindersScope.allCases) { scope in
                                    Text(scope.title).tag(scope)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    }

                    Divider()
                        .background(palette.borderColor.opacity(0.4))

                    HStack(spacing: 24) {
                        Toggle("到点日程呼吸发光提醒", isOn: Binding(
                            get: { store.isEventGlowAlertEnabled },
                            set: { store.isEventGlowAlertEnabled = $0 }
                        ))
                        .font(.caption)

                        Toggle("音乐播放动态频谱动画", isOn: Binding(
                            get: { store.isMusicWaveformAnimationEnabled },
                            set: { store.isMusicWaveformAnimationEnabled = $0 }
                        ))
                        .font(.caption)
                    }
                    .foregroundColor(palette.style == .native ? Color.primary : .white)
                }
                .padding(10)
                .background(palette.surfaceBackground)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(palette.borderColor.opacity(0.5), lineWidth: 1)
                )

                // 预设模式切换
                VStack(alignment: .leading, spacing: 8) {
                    Text("simulator.presets".localized)
                        .font(palette.fontMono)
                        .foregroundColor(palette.primaryAccent)

                    HStack(spacing: 10) {
                        ForEach(PodPreset.allCases) { preset in
                            Button {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    store.applyPreset(preset)
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(preset.defaultTitle)
                                        .font(.subheadline)
                                        .fontWeight(.bold)
                                        .foregroundColor(store.currentPreset == preset ? palette.primaryAccent : (palette.style == .native ? Color.primary : .white))
                                    Text(preset.defaultDescription)
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, minHeight: 65, alignment: .topLeading)
                                .background(store.currentPreset == preset ? palette.surfaceBackground : (palette.style == .native ? Color(nsColor: .controlBackgroundColor).opacity(0.4) : Color(white: 0.12)))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(store.currentPreset == preset ? palette.primaryAccent : Color.clear, lineWidth: 1.5)
                                )
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(20)
            .frame(width: 580)
        }
        .frame(minHeight: 520)
    }
}
