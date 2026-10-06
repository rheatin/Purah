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

                // 1. Appearance & Motion Card
                settingsCard(title: "Appearance & Motion", icon: "paintpalette.fill") {
                    VStack(spacing: 12) {
                        HStack {
                            Text("Theme Style")
                                .font(.subheadline.weight(.medium))
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
                            .frame(width: 260)
                        }

                        Divider()
                            .background(palette.borderColor.opacity(0.3))

                        HStack {
                            Text("Motion Dynamics")
                                .font(.subheadline.weight(.medium))
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
                            .frame(width: 260)
                        }
                    }
                }

                // 2. Rail & Drawer Geometry Card
                settingsCard(title: "Rail & Drawer Geometry", icon: "ruler.fill") {
                    VStack(spacing: 14) {
                        // Rail bar width
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Edge Rail Width")
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                Text("\(Int(store.railBarWidth)) px")
                                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                                    .foregroundColor(palette.primaryAccent)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(palette.primaryAccent.opacity(0.12))
                                    .cornerRadius(6)
                            }
                            Slider(value: Binding(
                                get: { store.railBarWidth },
                                set: { store.railBarWidth = $0 }
                            ), in: 4.0...16.0, step: 1.0)
                        }

                        Divider()
                            .background(palette.borderColor.opacity(0.3))

                        // Drawer extrusion width mode
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Drawer Extrusion Width")
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                Picker("", selection: Binding(
                                    get: { store.drawerWidthMode },
                                    set: { store.drawerWidthMode = $0 }
                                )) {
                                    ForEach(DrawerWidthMode.allCases, id: \.self) { mode in
                                        Text(mode.displayName).tag(mode)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 180)
                            }

                            if store.drawerWidthMode == .fixed {
                                HStack {
                                    Text("Fixed Length")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Slider(value: Binding(
                                        get: { store.fixedDrawerWidth },
                                        set: { store.fixedDrawerWidth = $0 }
                                    ), in: 220.0...330.0, step: 5.0)
                                    Text("\(Int(store.fixedDrawerWidth)) px")
                                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                                        .foregroundColor(palette.primaryAccent)
                                        .frame(width: 50)
                                }
                            } else {
                                Text("Automatically sizes drawer width based on content (230px ~ 330px)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
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
