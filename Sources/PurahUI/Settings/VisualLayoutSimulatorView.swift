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
            VStack(spacing: 20) {
                // Top Header
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Image(systemName: "slider.horizontal.2.square")
                                .foregroundColor(palette.primaryAccent)
                                .font(.title2)
                            Text("simulator.title".localized)
                                .font(.title3.weight(.bold))
                                .foregroundColor(palette.style == .native ? Color.primary : .white)
                        }
                        Text("simulator.subtitle".localized)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button {
                        withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
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
                    .buttonStyle(.tactile)
                }
                .padding(.horizontal, 4)

                // Capacity Overload Warning Banner
                if store.isRailOverloaded(edge: .left) || store.isRailOverloaded(edge: .right) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title3)
                            .foregroundColor(.orange)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Rail Capacity Overload Warning")
                                .font(.subheadline.weight(.bold))
                                .foregroundColor(.orange)

                            if store.isRailOverloaded(edge: .left) {
                                let req = Int(store.totalRequiredHeight(for: .left))
                                let avail = Int(store.availableScreenHeight(for: .left))
                                let pct = Int(store.capacityRatio(for: .left) * 100)
                                Text("• Left Rail requires \(req)pt (available: \(avail)pt · \(pct)% used). Bottom chips may be crowded. Consider reducing decomposed sub-items or assigning modules to the right rail.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            if store.isRailOverloaded(edge: .right) {
                                let req = Int(store.totalRequiredHeight(for: .right))
                                let avail = Int(store.availableScreenHeight(for: .right))
                                let pct = Int(store.capacityRatio(for: .right) * 100)
                                Text("• Right Rail requires \(req)pt (available: \(avail)pt · \(pct)% used). Bottom chips may be crowded. Consider reducing decomposed sub-items or assigning modules to the left rail.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.orange.opacity(0.12))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.orange.opacity(0.4), lineWidth: 1)
                    )
                }

                // 1. Rail & Drawer Geometry Card
                settingsCard(title: "Rail & Drawer Geometry", icon: "ruler.fill") {
                    VStack(spacing: 16) {
                        // Rail bar width
                        PurahThemedSliderRow(
                            title: "Edge Rail Width",
                            subtitle: "Physical trigger bezel thickness (4px ~ 16px)",
                            value: Binding(
                                get: { store.railBarWidth },
                                set: { store.railBarWidth = $0 }
                            ),
                            range: 4.0...16.0,
                            step: 1.0,
                            valueBadgeText: "\(Int(store.railBarWidth)) px"
                        )

                        Divider()
                            .background(palette.borderColor.opacity(0.3))

                        // Drawer extrusion width mode
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Drawer Extrusion Width")
                                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                                        .foregroundColor(palette.style == .native ? Color.primary : .white)
                                    Text("Fixed width or content-driven adaptive sizing")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                PurahThemedSegmentedPicker(
                                    options: DrawerWidthMode.allCases,
                                    selection: Binding(
                                        get: { store.drawerWidthMode },
                                        set: { store.drawerWidthMode = $0 }
                                    ),
                                    titleForOption: { $0.displayName }
                                )
                                .frame(width: 170)
                            }

                            if store.drawerWidthMode == .fixed {
                                PurahThemedSliderRow(
                                    title: "Fixed Drawer Length",
                                    value: Binding(
                                        get: { store.fixedDrawerWidth },
                                        set: { store.fixedDrawerWidth = $0 }
                                    ),
                                    range: 220.0...330.0,
                                    step: 5.0,
                                    valueBadgeText: "\(Int(store.fixedDrawerWidth)) px"
                                )
                            } else {
                                Text("Automatically sizes drawer width based on content length (230px ~ 330px)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Divider()
                            .background(palette.borderColor.opacity(0.3))

                        // Multi-Display Target Mode
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Multi-Display Target")
                                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                                    .foregroundColor(palette.style == .native ? Color.primary : .white)
                                Text("Choose which display hosts edge rails in multi-monitor setups")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            PurahThemedMenuPicker(
                                options: DisplayTargetMode.allCases,
                                selection: Binding(
                                    get: { store.displayTargetMode },
                                    set: {
                                        store.displayTargetMode = $0
                                        store.savePersistentState()
                                    }
                                ),
                                titleForOption: { $0.displayName }
                            )
                            .frame(width: 250)
                        }

                        Divider()
                            .background(palette.borderColor.opacity(0.3))

                        // Edge Trigger Intentionality Sensitivity & Calibration Instrument
                        VStack(alignment: .leading, spacing: 12) {
                            // Mutually Exclusive Trigger Mode Selection (Hover Dwell vs Push Force)
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

                            // Detailed Calibration Gauge
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

                        Divider()
                            .background(palette.borderColor.opacity(0.3))

                        // Dynamic Attention Alert System
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
                }

                // 3. Hotkeys & Freeze Mode Card
                settingsCard(title: "Hotkeys & Freeze Mode", icon: "keyboard.fill") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Toggle to hide and freeze all rails instantly for clean screenshots or edge-docked buttons.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        KeyboardShortcutRecorderView(store: store)
                    }
                }

                // 4. Module Assembly Card
                settingsCard(title: "Rail Module Assembly", icon: "square.grid.2x2.fill") {
                    VStack(spacing: 10) {
                        HStack {
                            Text("Toggle modules to mount or unmount on rails. Configure each in the Plugins tab.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(store.pods.filter { $0.isEnabled }.count) of \(store.pods.count) active")
                                .font(.system(.caption, design: .monospaced).weight(.semibold))
                                .foregroundColor(palette.primaryAccent)
                        }

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(store.pods) { pod in
                                Button {
                                    withAnimation(.spring(response: 0.24, dampingFraction: 0.80)) {
                                        store.togglePodEnabled(id: pod.id)
                                    }
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: pod.isEnabled ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(pod.isEnabled ? palette.primaryAccent : .gray)
                                            .font(.subheadline)

                                        Image(systemName: pod.systemIcon)
                                            .font(.caption)
                                            .foregroundColor(pod.isEnabled ? palette.podColor(for: pod.id, store: store) : .gray)

                                        Text(pod.name)
                                            .font(.subheadline)
                                            .foregroundColor(pod.isEnabled ? (palette.style == .native ? Color.primary : .white) : .secondary)
                                            .lineLimit(1)

                                        Spacer()

                                        Text(pod.edge == .left ? "Left" : "Right")
                                            .font(.system(size: 9, weight: .bold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(pod.isEnabled ? palette.primaryAccent.opacity(0.12) : Color.gray.opacity(0.15))
                                            .foregroundColor(pod.isEnabled ? palette.primaryAccent : .gray)
                                            .cornerRadius(4)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(pod.isEnabled ? Color(nsColor: .controlBackgroundColor) : Color.clear)
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(pod.isEnabled ? palette.primaryAccent.opacity(0.3) : palette.borderColor.opacity(0.3), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.tactile)
                            }
                        }
                    }
                }

                // 5. Mini Screen Simulation
                ScreenSimulationCanvas(store: store)

                // 6. Presets Card
                settingsCard(title: "Ergonomic Presets", icon: "sparkle") {
                    HStack(spacing: 12) {
                        ForEach(PodPreset.allCases) { preset in
                            Button {
                                withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                                    store.applyPreset(preset)
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(preset.defaultTitle)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(store.currentPreset == preset ? palette.primaryAccent : (palette.style == .native ? Color.primary : .white))
                                    Text(preset.defaultDescription)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(3)
                                        .multilineTextAlignment(.leading)
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, minHeight: 75, alignment: .topLeading)
                                .background(store.currentPreset == preset ? palette.surfaceBackground : Color(nsColor: .controlBackgroundColor).opacity(0.4))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(store.currentPreset == preset ? palette.primaryAccent : palette.borderColor.opacity(0.2), lineWidth: 1.5)
                                )
                            }
                            .buttonStyle(.tactile)
                        }
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
