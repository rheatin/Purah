// Sources/PurahUI/Settings/InteractionSettingsView.swift
import SwiftUI
import PurahCore

public struct InteractionSettingsView: View {
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
            VStack(spacing: 20) {
                // Top Header
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Image(systemName: "wand.and.stars")
                                .foregroundColor(palette.primaryAccent)
                                .font(.title2)
                            Text("motion.title".localized)
                                .font(.title3.weight(.bold))
                                .foregroundColor(palette.style == .native ? Color.primary : .white)
                                .lineLimit(1)
                        }
                        Text("motion.subtitle".localized)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .padding(.horizontal, 4)

                // 1. Edge Trigger & Motion Physics Card
                settingsCard(title: "interaction.trigger.card".localized, icon: "cursorarrow.motionlines") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("interaction.trigger.mode.title".localized)
                                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                                    .foregroundColor(palette.style == .native ? Color.primary : .white)
                                Text(store.edgeTriggerMode.localizedSubtitle)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            PurahThemedSegmentedPicker(
                                options: EdgeTriggerMode.allCases,
                                selection: Binding(
                                    get: { store.edgeTriggerMode },
                                    set: {
                                        store.edgeTriggerMode = $0
                                        store.onboardingGateTargetValue = ($0 == .hoverDwell ? Int(store.activeInitialDwellSeconds * 1000) : Int(store.activePushResistanceBarrier))
                                        store.onboardingGateState = .idle
                                        store.onboardingGateProgress = 0.0
                                        store.onboardingGateCurrentValue = 0
                                        store.savePersistentState()
                                    }
                                ),
                                titleForOption: { $0.localizedDisplayName }
                            )
                            .frame(width: 210)
                        }

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("interaction.trigger.sensitivity.title".localized)
                                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                                    .foregroundColor(palette.style == .native ? Color.primary : .white)
                                Text("interaction.trigger.sensitivity.subtitle".localized)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            PurahThemedMenuPicker(
                                options: EdgeTriggerSensitivity.allCases,
                                selection: Binding(
                                    get: { store.edgeTriggerSensitivity },
                                    set: {
                                        store.applySensitivityPreset($0)
                                        store.onboardingGateTargetValue = (store.edgeTriggerMode == .hoverDwell ? Int(store.activeInitialDwellSeconds * 1000) : Int(store.activePushResistanceBarrier))
                                        store.onboardingGateState = .idle
                                        store.onboardingGateProgress = 0.0
                                        store.onboardingGateCurrentValue = 0
                                    }
                                ),
                                titleForOption: { $0.localizedDisplayName }
                            )
                            .frame(width: 280)
                        }

                        // Live Anti-Touch Gate Telemetry Meter
                        PurahEdgeGateMeterView(store: store)

                        VStack(spacing: 8) {
                            if store.edgeTriggerMode == .hoverDwell {
                                PurahThemedSliderRow(
                                    title: "interaction.trigger.dwell.title".localized,
                                    subtitle: "interaction.trigger.dwell.subtitle".localized,
                                    value: Binding(
                                        get: { store.customInitialDwellMs },
                                        set: {
                                            store.customInitialDwellMs = $0
                                            store.edgeTriggerSensitivity = .custom
                                            if store.edgeTriggerMode == .hoverDwell {
                                                store.onboardingGateTargetValue = Int($0)
                                            }
                                            store.scheduleSavePersistentState()
                                        }
                                    ),
                                    range: 0...1000,
                                    step: 25,
                                    valueBadgeText: "\(Int(store.customInitialDwellMs)) ms"
                                )
                            } else {
                                PurahThemedSliderRow(
                                    title: "interaction.trigger.barrier.title".localized,
                                    subtitle: "interaction.trigger.barrier.subtitle".localized,
                                    value: Binding(
                                        get: { store.customPushResistanceBarrier },
                                        set: {
                                            store.customPushResistanceBarrier = $0
                                            store.edgeTriggerSensitivity = .custom
                                            if store.edgeTriggerMode == .pushForce {
                                                store.onboardingGateTargetValue = Int($0)
                                            }
                                            store.scheduleSavePersistentState()
                                        }
                                    ),
                                    range: 20...120,
                                    step: 5,
                                    valueBadgeText: "\(Int(store.customPushResistanceBarrier)) px"
                                )
                            }

                            PurahThemedSliderRow(
                                title: "interaction.trigger.grace.title".localized,
                                subtitle: "interaction.trigger.grace.subtitle".localized,
                                value: Binding(
                                    get: { store.customExitGraceMs },
                                    set: {
                                        store.customExitGraceMs = $0
                                        store.edgeTriggerSensitivity = .custom
                                        store.scheduleSavePersistentState()
                                    }
                                ),
                                range: 100...600,
                                step: 20,
                                valueBadgeText: "\(Int(store.customExitGraceMs)) ms"
                            )

                            PurahThemedSliderRow(
                                title: "interaction.trigger.corridor.title".localized,
                                subtitle: "interaction.trigger.corridor.subtitle".localized,
                                value: Binding(
                                    get: { store.customCatchCorridorPt },
                                    set: {
                                        store.customCatchCorridorPt = $0
                                        store.edgeTriggerSensitivity = .custom
                                        store.scheduleSavePersistentState()
                                    }
                                ),
                                range: 20...90,
                                step: 5,
                                valueBadgeText: "+\(Int(store.customCatchCorridorPt)) pt"
                            )
                        }
                        .padding(10)
                        .background(Color.primary.opacity(0.035))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(palette.borderColor.opacity(0.2), lineWidth: 1)
                        )
                    }
                }

                // 2. Dynamic Attention Alerts Card
                settingsCard(title: "interaction.alerts.card".localized, icon: "bell.badge.waveform.fill") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("interaction.alerts.dynamic.title".localized)
                                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                                    .foregroundColor(palette.style == .native ? Color.primary : .white)
                                Text(store.alertStyle.localizedSubtitle)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            PurahThemedMenuPicker(
                                options: PluginAlertStyle.allCases,
                                selection: Binding(
                                    get: { store.alertStyle },
                                    set: {
                                        store.alertStyle = $0
                                        store.isEventGlowAlertEnabled = ($0 != .off)
                                        store.savePersistentState()
                                    }
                                ),
                                titleForOption: { $0.localizedDisplayName }
                            )
                        }
                    }
                }

                // 3. Quiet Hours Card
                quietHoursCard(store: store, palette: palette)

                // 4. Sensory Feedback Card
                settingsCard(title: "interaction.sensory.card".localized, icon: "hand.tap.fill") {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle(isOn: Binding(
                                get: { store.isToastSoundEnabled },
                                set: {
                                    store.isToastSoundEnabled = $0
                                    store.savePersistentState()
                                    if $0 {
                                        _ = store.previewToastSound()
                                    }
                                }
                            )) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("sensory.toastSound.title".localized)
                                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                                        .foregroundColor(palette.style == .native ? Color.primary : .white)
                                    Text("sensory.toastSound.subtitle".localized)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }

                            if store.isToastSoundEnabled {
                                HStack(spacing: 10) {
                                    Text("sensory.soundPicker.title".localized)
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    PurahThemedMenuPicker(
                                        options: ToastNotificationSound.allCases,
                                        selection: Binding(
                                            get: { store.toastNotificationSound },
                                            set: {
                                                store.toastNotificationSound = $0
                                                store.savePersistentState()
                                                _ = store.previewToastSound()
                                            }
                                        ),
                                        titleForOption: { $0.localizedName }
                                    )

                                    Button {
                                        _ = store.previewToastSound()
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "speaker.wave.2.fill")
                                                .font(.system(size: 10.5))
                                            Text("sensory.soundPreview".localized)
                                                .font(.system(size: 11, weight: .medium))
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color(nsColor: .controlBackgroundColor))
                                        .cornerRadius(6)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(palette.borderColor.opacity(0.25), lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.tactile)
                                    .help("help.previewSound".localized)
                                    .accessibilityLabel("help.previewSound".localized)
                                }
                                .padding(.leading, 18)
                            }
                        }

                        Divider()
                            .background(palette.borderColor.opacity(0.2))

                        VStack(alignment: .leading, spacing: 8) {
                            Toggle(isOn: Binding(
                                get: { store.isTrackpadHapticsEnabled },
                                set: {
                                    store.isTrackpadHapticsEnabled = $0
                                    store.savePersistentState()
                                    if $0 {
                                        _ = store.triggerControlHaptic(.levelChange)
                                    }
                                }
                            )) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("sensory.haptics.title".localized)
                                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                                        .foregroundColor(palette.style == .native ? Color.primary : .white)
                                    Text("sensory.haptics.subtitle".localized)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }

                            if store.isTrackpadHapticsEnabled {
                                VStack(alignment: .leading, spacing: 6) {
                                    Toggle("sensory.haptics.drawerPop".localized, isOn: Binding(
                                        get: { store.isDrawerPopHapticEnabled },
                                        set: {
                                            store.isDrawerPopHapticEnabled = $0
                                            store.savePersistentState()
                                            if $0 {
                                                _ = store.triggerControlHaptic(.alignment)
                                            }
                                        }
                                    ))
                                    .font(.caption)

                                    Toggle("sensory.haptics.controls".localized, isOn: Binding(
                                        get: { store.isControlHapticEnabled },
                                        set: {
                                            store.isControlHapticEnabled = $0
                                            store.savePersistentState()
                                            if $0 {
                                                _ = store.triggerControlHaptic(.alignment)
                                            }
                                        }
                                    ))
                                    .font(.caption)
                                }
                                .padding(.leading, 18)
                            }
                        }
                    }
                }
            }
            .padding(24)
            .frame(width: 680)
        }
        .frame(minHeight: 560)
        .onAppear {
            store.isInteractionSettingsTelemetryActive = true
            store.onboardingGateState = .idle
            store.onboardingGateProgress = 0.0
            store.onboardingGateCurrentValue = 0
            store.onboardingGateTargetValue = store.edgeTriggerMode == .hoverDwell
                ? Int(store.activeInitialDwellSeconds * 1000)
                : Int(store.activePushResistanceBarrier)
        }
        .onDisappear {
            store.isInteractionSettingsTelemetryActive = false
        }
    }

    @ViewBuilder
    private func settingsCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        let palette = theme.palette
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(palette.primaryAccent)
                Text(title)
                    .font(.headline)
                    .foregroundColor(palette.style == .native ? Color.primary : .white)
                    .lineLimit(1)
            }

            content()
        }
        .padding(16)
        // The card must fill the column regardless of what it holds. Without
        // this its width is its content's intrinsic width, so a card with a
        // trailing Spacer ran edge to edge while a card holding just a Toggle
        // shrank and was centred by the parent VStack — the two sat misaligned
        // side by side.
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surfaceBackground)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(palette.borderColor.opacity(0.35), lineWidth: 1)
        )
    }

    // MARK: - Quiet Hours

    /// A daily window that holds back alerts and toasts.
    ///
    /// The two ends are minute pickers rather than `DatePicker`s: this is a
    /// recurring wall-clock window, not a date, and a date picker would imply
    /// the day matters. Times are stored as minutes-since-midnight, so the
    /// picker round-trips without an arbitrary reference date.
    @ViewBuilder
    private func quietHoursCard(store: PurahWorkspaceStore, palette: ThemePalette) -> some View {
        settingsCard(title: "interaction.quiet.card".localized, icon: "moon.zzz.fill") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: Binding(
                    get: { store.quietHours.isEnabled },
                    set: { newValue in
                        var updated = store.quietHours
                        updated.isEnabled = newValue
                        store.quietHours = updated
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("interaction.quiet.toggle".localized)
                            .font(.system(size: 11.5, weight: .medium, design: .rounded))
                            .foregroundColor(palette.style == .native ? Color.primary : .white)
                        Text("interaction.quiet.description".localized)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if store.quietHours.isEnabled {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Text("interaction.quiet.start".localized)
                                .font(.caption)
                                .foregroundColor(.secondary)

                            minutePicker(
                                binding: Binding(
                                    get: { store.quietHours.startMinute },
                                    set: { newValue in
                                        var updated = store.quietHours
                                        updated.startMinute = newValue
                                        store.quietHours = updated
                                    }
                                ),
                                palette: palette
                            )

                            Text("interaction.quiet.end".localized)
                                .font(.caption)
                                .foregroundColor(.secondary)

                            minutePicker(
                                binding: Binding(
                                    get: { store.quietHours.endMinute },
                                    set: { newValue in
                                        var updated = store.quietHours
                                        updated.endMinute = newValue
                                        store.quietHours = updated
                                    }
                                ),
                                palette: palette
                            )

                            Spacer()
                        }

                        HStack(spacing: 6) {
                            Text("interaction.quiet.days".localized)
                                .font(.caption)
                                .foregroundColor(.secondary)

                            ForEach(Weekday.allCases) { day in
                                let isOn = store.quietHours.weekdays.contains(day)
                                Button {
                                    var updated = store.quietHours
                                    if isOn { updated.weekdays.remove(day) } else { updated.weekdays.insert(day) }
                                    store.quietHours = updated
                                } label: {
                                    Text(day.localizedShortName)
                                        .font(.system(size: 10, weight: isOn ? .bold : .medium, design: .rounded))
                                        .foregroundColor(isOn ? palette.primaryAccent : .secondary)
                                        .frame(width: 30, height: 22)
                                        .background(
                                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                                .fill(isOn ? palette.primaryAccent.opacity(0.14) : Color.primary.opacity(0.04))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                                .stroke(isOn ? palette.primaryAccent.opacity(0.45) : palette.borderColor.opacity(0.2), lineWidth: 1)
                                        )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(day.localizedShortName)
                                .accessibilityAddTraits(isOn ? [.isSelected] : [])
                            }

                            if store.quietHours.weekdays.isEmpty {
                                Text("interaction.quiet.everyDay".localized)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.leading, 2)

                        // Explain the two configurations that look like bugs:
                        // a window spanning midnight, and one whose ends meet.
                        if store.quietHours.isZeroLength {
                            inlineNote("interaction.quiet.zeroLength".localized, palette: palette, isWarning: true)
                        } else if store.quietHours.crossesMidnight {
                            inlineNote("interaction.quiet.crossMidnight".localized, palette: palette, isWarning: false)
                        }

                        if store.isQuietNow() {
                            inlineNote("interaction.quiet.activeNow".localized, palette: palette, isWarning: false)
                        }
                    }
                    .padding(.leading, 18)
                }
            }
        }
    }

    @ViewBuilder
    private func inlineNote(_ text: String, palette: ThemePalette, isWarning: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: isWarning ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .font(.system(size: 9))
            Text(text)
                .font(.system(size: 9.5))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundColor(isWarning ? .orange : .secondary)
    }

    /// Half-hour steps, which is the resolution people actually pick with.
    private func minutePicker(binding: Binding<Int>, palette: ThemePalette) -> some View {
        let options = Array(stride(from: 0, to: QuietHours.minutesPerDay, by: 30))
        return PurahThemedMenuPicker(
            options: options,
            selection: Binding(
                get: {
                    // A stored value off the grid (hand-edited, or a future
                    // finer step) must still show *something*; snap to the
                    // nearest option rather than rendering an empty picker.
                    options.min { abs($0 - binding.wrappedValue) < abs($1 - binding.wrappedValue) } ?? 0
                },
                set: { binding.wrappedValue = $0 }
            ),
            titleForOption: { Self.formatMinute($0) }
        )
    }

    static func formatMinute(_ minute: Int) -> String {
        let normalized = QuietHours.normalizeMinute(minute)
        return String(format: "%02d:%02d", normalized / 60, normalized % 60)
    }
}
