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
                            Text("interaction.title".localized)
                                .font(.title3.weight(.bold))
                                .foregroundColor(palette.style == .native ? Color.primary : .white)
                                .lineLimit(1)
                        }
                        Text("interaction.subtitle".localized)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .padding(.horizontal, 4)

                // 1. Language & Regional Card
                settingsCard(title: "interaction.language.card".localized, icon: "globe") {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("interaction.language.title".localized)
                                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                                .foregroundColor(palette.style == .native ? Color.primary : .white)
                            Text("interaction.language.subtitle".localized)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        PurahThemedMenuPicker(
                            options: AppLanguage.allCases,
                            selection: Binding(
                                get: { LocalizationManager.shared.currentLanguage },
                                set: { LocalizationManager.shared.currentLanguage = $0 }
                            ),
                            titleForOption: { $0.displayName }
                        )
                        .frame(width: 200)
                    }
                }

                // 2. Edge Trigger & Motion Physics Card
                settingsCard(title: "interaction.trigger.card".localized, icon: "cursorarrow.motionlines") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Initial Trigger Mode")
                                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                                    .foregroundColor(palette.style == .native ? Color.primary : .white)
                                Text(store.edgeTriggerMode.subtitle)
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
                                        store.savePersistentState()
                                    }
                                ),
                                titleForOption: { $0.displayName }
                            )
                            .frame(width: 210)
                        }

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Sensitivity Preset")
                                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                                    .foregroundColor(palette.style == .native ? Color.primary : .white)
                                Text("Governs dwell intent, push-force threshold, and overshoot corridor")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            PurahThemedMenuPicker(
                                options: EdgeTriggerSensitivity.allCases,
                                selection: Binding(
                                    get: { store.edgeTriggerSensitivity },
                                    set: { store.applySensitivityPreset($0) }
                                ),
                                titleForOption: { $0.displayName }
                            )
                            .frame(width: 280)
                        }

                        VStack(spacing: 8) {
                            if store.edgeTriggerMode == .hoverDwell {
                                PurahThemedSliderRow(
                                    title: "Initial Hover Dwell",
                                    subtitle: "Duration required to rest on bar before drawer opens (up to 1000ms)",
                                    value: Binding(
                                        get: { store.customInitialDwellMs },
                                        set: {
                                            store.customInitialDwellMs = $0
                                            store.edgeTriggerSensitivity = .custom
                                            store.savePersistentState()
                                        }
                                    ),
                                    range: 0...1000,
                                    step: 25,
                                    valueBadgeText: "\(Int(store.customInitialDwellMs)) ms"
                                )
                            } else {
                                PurahThemedSliderRow(
                                    title: "Push Resistance Barrier",
                                    subtitle: "Physical push force required at bezel before drawer breaks through (20px ~ 120px)",
                                    value: Binding(
                                        get: { store.customPushResistanceBarrier },
                                        set: {
                                            store.customPushResistanceBarrier = $0
                                            store.edgeTriggerSensitivity = .custom
                                            store.savePersistentState()
                                        }
                                    ),
                                    range: 20...120,
                                    step: 5,
                                    valueBadgeText: "\(Int(store.customPushResistanceBarrier)) px"
                                )
                            }

                            PurahThemedSliderRow(
                                title: "Exit Grace Window",
                                subtitle: "Hysteresis window before unpinned drawer retracts",
                                value: Binding(
                                    get: { store.customExitGraceMs },
                                    set: {
                                        store.customExitGraceMs = $0
                                        store.edgeTriggerSensitivity = .custom
                                        store.savePersistentState()
                                    }
                                ),
                                range: 100...600,
                                step: 20,
                                valueBadgeText: "\(Int(store.customExitGraceMs)) ms"
                            )

                            PurahThemedSliderRow(
                                title: "Catch Corridor Buffer",
                                subtitle: "Floating edge invisible hit-test padding to prevent mouse drop",
                                value: Binding(
                                    get: { store.customCatchCorridorPt },
                                    set: {
                                        store.customCatchCorridorPt = $0
                                        store.edgeTriggerSensitivity = .custom
                                        store.savePersistentState()
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

                // 3. Dynamic Attention Alerts Card
                settingsCard(title: "interaction.alerts.card".localized, icon: "bell.badge.waveform.fill") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Attention Alert Dynamic")
                                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                                    .foregroundColor(palette.style == .native ? Color.primary : .white)
                                Text(store.alertStyle.subtitle)
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
                                titleForOption: { $0.displayName }
                            )
                            .frame(width: 220)
                        }

                        if store.alertStyle != .off {
                            Toggle("Dismiss dynamic alert animation on mouse hover", isOn: Binding(
                                get: { store.dismissAlertOnHover },
                                set: {
                                    store.dismissAlertOnHover = $0
                                    store.savePersistentState()
                                }
                            ))
                            .font(.caption)
                        }
                    }
                }

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
                                    .frame(width: 180)

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
                                    .help("Preview selected sound")
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

                // 5. Global Hotkeys & Freeze Mode Card
                settingsCard(title: "interaction.hotkeys.card".localized, icon: "keyboard.fill") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Toggle to hide and freeze all rails instantly for clean screenshots or edge-docked buttons.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        KeyboardShortcutRecorderView(store: store)
                    }
                }
            }
            .padding(24)
            .frame(width: 680)
        }
        .frame(minHeight: 560)
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
        .background(palette.surfaceBackground)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(palette.borderColor.opacity(0.35), lineWidth: 1)
        )
    }
}
