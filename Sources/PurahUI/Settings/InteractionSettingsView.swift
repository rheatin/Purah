// Sources/PurahUI/Settings/InteractionSettingsView.swift
import SwiftUI
import PurahCore

private struct AlertingPodEntry: Identifiable {
    let pod: SlotPod
    let plugin: any PurahPodPlugin

    var id: String { pod.id }
}

private struct AlertStyleChoice: Hashable {
    let style: PluginAlertStyle?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.style?.rawValue == rhs.style?.rawValue
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(style?.rawValue)
    }
}

public struct InteractionSettingsView: View {
    public let store: PurahWorkspaceStore
    @State private var expandedAlertPodId: String?

    private var theme: ThemeManager {
        ThemeManager.shared
    }

    public init(store: PurahWorkspaceStore) {
        self.store = store
    }

    private var alertingPods: [AlertingPodEntry] {
        store.pods.compactMap { pod in
            guard pod.isEnabled,
                  let plugin = PluginRegistry.shared.plugin(for: pod.id),
                  plugin.manifest.supportsAlerts else { return nil }
            return AlertingPodEntry(pod: pod, plugin: plugin)
        }
    }

    private var alertStyleChoices: [AlertStyleChoice] {
        [AlertStyleChoice(style: nil)]
            + PluginAlertStyle.allCases
                .filter { $0 != .off }
                .map { AlertStyleChoice(style: $0) }
    }

    private func setGlobalAlertChannel(_ channel: AlertChannel, enabled: Bool) {
        if enabled {
            store.alertChannels.insert(channel)
        } else {
            store.alertChannels.remove(channel)
        }
        store.scheduleSavePersistentState()
    }

    private func channelTitle(_ channel: AlertChannel) -> String {
        switch channel {
        case .railEffect:
            "interaction.alerts.channel.railEffect".localized
        case .toast:
            "interaction.alerts.channel.toast".localized
        case .sound:
            "interaction.alerts.channel.sound".localized
        }
    }

    private func alertStyleTitle(_ choice: AlertStyleChoice) -> String {
        choice.style?.localizedDisplayName ?? "interaction.alerts.followEachPod".localized
    }

    /// The per-pod picker's empty choice is "follow the default", not "follow
    /// each pod": a pod has exactly one default to follow.
    private func podAlertStyleTitle(_ choice: AlertStyleChoice) -> String {
        choice.style?.localizedDisplayName ?? "interaction.alerts.style.followDefault".localized
    }

    private func podAlertDetail(_ entry: AlertingPodEntry) -> String {
        let style = store.resolvedAlertStyle(
            declared: entry.plugin.alertStyle(store: store),
            podId: entry.pod.id
        )
        let allowed = store.allowedChannels(forPodId: entry.pod.id)
        guard allowed != Set(AlertChannel.allCases) else {
            return style.localizedDisplayName
        }

        let channels: String
        if allowed.isEmpty {
            channels = "interaction.alerts.pods.detail.silent".localized
        } else if allowed == [.railEffect] {
            channels = "interaction.alerts.pods.detail.edgeOnly".localized
        } else {
            channels = AlertChannel.allCases
                .filter(allowed.contains)
                .map(channelTitle)
                .joined(separator: " · ")
        }
        return "\(style.localizedDisplayName) · \(channels)"
    }

    @ViewBuilder
    private func podChannelToggle(_ channel: AlertChannel, podId: String) -> some View {
        Toggle(channelTitle(channel), isOn: Binding(
            get: { store.allowedChannels(forPodId: podId).contains(channel) },
            set: { store.setAlertChannel(channel, isEnabled: $0, forPodId: podId) }
        ))
        .toggleStyle(.checkbox)
        .controlSize(.small)
        .font(.system(size: 10, weight: .regular, design: .rounded))
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
                PurahSettingsCard(title: "interaction.trigger.card".localized, icon: "cursorarrow.motionlines") {
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
                PurahSettingsCard(title: "interaction.alerts.card".localized, icon: "bell.badge.waveform.fill") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Text("interaction.alerts.master.title".localized)
                                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                                .foregroundColor(palette.style == .native ? Color.primary : .white)

                            Spacer()

                            Toggle("interaction.alerts.master.title".localized, isOn: Binding(
                                get: { store.isAlertMasterEnabled },
                                set: {
                                    store.isAlertMasterEnabled = $0
                                    store.scheduleSavePersistentState()
                                }
                            ))
                            .toggleStyle(.switch)
                            .labelsHidden()
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            if !store.isAlertMasterEnabled {
                                Text("interaction.alerts.pods.caption".localized)
                                    .font(.system(size: 9.5))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }

                            Divider()
                                .opacity(0.45)

                            HStack(spacing: 12) {
                                Text("interaction.alerts.ways.title".localized)
                                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                                    .foregroundColor(palette.style == .native ? Color.primary : .white)

                                Toggle(channelTitle(.railEffect), isOn: Binding(
                                    get: { store.isAlertChannelEnabled(.railEffect) },
                                    set: { setGlobalAlertChannel(.railEffect, enabled: $0) }
                                ))
                                .toggleStyle(.checkbox)
                                .controlSize(.small)

                                PurahThemedMenuPicker(
                                    options: alertStyleChoices,
                                    selection: Binding(
                                        get: { AlertStyleChoice(style: store.alertStyleOverride) },
                                        set: {
                                            store.alertStyleOverride = $0.style
                                            store.scheduleSavePersistentState()
                                        }
                                    ),
                                    titleForOption: alertStyleTitle
                                )
                                .frame(width: 142)

                                Toggle(channelTitle(.toast), isOn: Binding(
                                    get: { store.isAlertChannelEnabled(.toast) },
                                    set: { setGlobalAlertChannel(.toast, enabled: $0) }
                                ))
                                .toggleStyle(.checkbox)
                                .controlSize(.small)

                                Toggle(channelTitle(.sound), isOn: Binding(
                                    get: { store.isAlertChannelEnabled(.sound) },
                                    set: { setGlobalAlertChannel(.sound, enabled: $0) }
                                ))
                                .toggleStyle(.checkbox)
                                .controlSize(.small)

                                Spacer(minLength: 0)
                            }
                            .font(.system(size: 10, weight: .regular, design: .rounded))
                            .frame(height: 26)

                            if store.isAlertMasterEnabled && store.alertChannels.isEmpty {
                                Text("interaction.alerts.channels.none.caption".localized)
                                    .font(.system(size: 9.5))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }

                            Divider()
                                .opacity(0.45)

                            VStack(spacing: 0) {
                                ForEach(alertingPods) { entry in
                                    let isExpanded = expandedAlertPodId == entry.pod.id

                                    VStack(spacing: 0) {
                                        HStack(spacing: 7) {
                                            // The whole label side opens the row. A
                                            // 14pt chevron is a target you have to
                                            // hunt for; the row is the control.
                                            HStack(spacing: 7) {
                                                Image(systemName: entry.plugin.manifest.systemIcon)
                                                    .font(.system(size: 11, weight: .medium))
                                                    .foregroundColor(palette.podColor(for: entry.pod.id, store: store))
                                                    .frame(width: 16)

                                                Text(entry.plugin.manifest.displayName)
                                                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                                                    .foregroundColor(palette.style == .native ? Color.primary : .white)
                                                    .lineLimit(1)

                                                Text(podAlertDetail(entry))
                                                    .font(.system(size: 9))
                                                    .foregroundColor(.secondary)
                                                    .lineLimit(1)
                                                    .truncationMode(.tail)

                                                Spacer(minLength: 4)

                                                Image(systemName: "chevron.right")
                                                    .font(.system(size: 8, weight: .bold))
                                                    .foregroundColor(.secondary)
                                                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                                                    .frame(width: 14, height: 18)
                                            }
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                withAnimation(PurahMotionPolicy.surface) {
                                                    expandedAlertPodId = isExpanded ? nil : entry.pod.id
                                                }
                                            }
                                            .accessibilityElement(children: .combine)
                                            .accessibilityAddTraits(.isButton)

                                            Toggle(entry.plugin.manifest.displayName, isOn: Binding(
                                                get: { !store.disabledAlertPodIds.contains(entry.pod.id) },
                                                set: { store.setAlertEnabled($0, forPodId: entry.pod.id) }
                                            ))
                                            .toggleStyle(.switch)
                                            .controlSize(.mini)
                                            .labelsHidden()
                                        }
                                        .frame(height: 26)

                                        if isExpanded {
                                            VStack(spacing: 0) {
                                                HStack(spacing: 12) {
                                                    Text("interaction.alerts.pods.style".localized)
                                                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                                                        .foregroundColor(palette.style == .native ? Color.primary : .white)

                                                    PurahThemedMenuPicker(
                                                        options: alertStyleChoices,
                                                        selection: Binding(
                                                            get: { AlertStyleChoice(style: store.podAlertStyles[entry.pod.id]) },
                                                            set: { store.setAlertStyle($0.style, forPodId: entry.pod.id) }
                                                        ),
                                                        titleForOption: podAlertStyleTitle
                                                    )
                                                    .frame(width: 142)

                                                    Spacer(minLength: 0)
                                                }
                                                .padding(.leading, 23)
                                                .frame(height: 26)

                                                HStack(spacing: 12) {
                                                    podChannelToggle(.railEffect, podId: entry.pod.id)
                                                    podChannelToggle(.toast, podId: entry.pod.id)
                                                    podChannelToggle(.sound, podId: entry.pod.id)
                                                    Spacer(minLength: 0)
                                                }
                                                .padding(.leading, 23)
                                                .frame(height: 26)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .opacity(store.isAlertMasterEnabled ? 1 : 0.5)
                        .disabled(!store.isAlertMasterEnabled)
                    }
                }

                // 3. Quiet Hours Card
                quietHoursCard(store: store, palette: palette)

                // 4. Sensory Feedback Card
                PurahSettingsCard(title: "interaction.sensory.card".localized, icon: "hand.tap.fill") {
                    VStack(alignment: .leading, spacing: 12) {
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

                            Divider()
                                .background(palette.borderColor.opacity(0.2))
                        }

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

    // MARK: - Quiet Hours    /// A daily window that holds back alerts and toasts.
    ///
    /// The two ends are minute pickers rather than `DatePicker`s: this is a
    /// recurring wall-clock window, not a date, and a date picker would imply
    /// the day matters. Times are stored as minutes-since-midnight, so the
    /// picker round-trips without an arbitrary reference date.
    @ViewBuilder
    private func quietHoursCard(store: PurahWorkspaceStore, palette: ThemePalette) -> some View {
        PurahSettingsCard(title: "interaction.quiet.card".localized, icon: "moon.zzz.fill") {
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
