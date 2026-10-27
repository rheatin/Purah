import SwiftUI
import AppKit
import PurahCore
import UniformTypeIdentifiers

public struct MusicRailBarContainerView: View {
    public let state: MusicPluginState
    public let store: PurahWorkspaceStore
    public let slotHeight: CGFloat
    public let railWidth: CGFloat

    public init(state: MusicPluginState, store: PurahWorkspaceStore, slotHeight: CGFloat, railWidth: CGFloat) {
        self.state = state
        self.store = store
        self.slotHeight = slotHeight
        self.railWidth = railWidth
    }

    public var body: some View {
        let storeTrack = store._musicTrack
        let isPlaying = storeTrack.isPlaying || state.isPlaying || (SystemAudioLiveMonitor.shared.currentLevel > 0.008)
        let liveTrack = storeTrack.isPlaying ? storeTrack : (!storeTrack.title.isEmpty ? storeTrack : state.track)

        WaveMeterAmbientView(
            style: state.railStyle,
            subStyle: state.dynamicSubStyle,
            track: liveTrack,
            progress: liveTrack.calculatedProgress,
            samples: liveTrack.waveformSamples,
            isPlaying: isPlaying,
            isAnimated: state.isWaveformAnimationEnabled,
            height: slotHeight,
            barWidth: railWidth
        )
        .frame(width: railWidth, height: slotHeight)
        .onAppear {
            SystemAudioLiveMonitor.shared.start()
            SystemAudioLiveMonitor.shared.latencyOffsetMs = state.rhythmOffsetMs
        }
    }
}

// MARK: - Music Plugin
public struct MusicPlugin: PurahPodPlugin {
    public nonisolated let manifest = PurahPluginManifest(
        id: "music",
        displayName: "Dynamic Audio",
        systemIcon: "music.note",
        author: "Project Purah",
        version: "0.1.0",
        description: "System media control and playback monitor",
        defaultEdge: .right,
        preferredZone: .goldenAction,
        ergonomicWeight: 25.0,
        minLengthRatio: 0.14,
        defaultColorHex: "#FF375F",
        permissions: [.appleMusic]
    )

    public let state: MusicPluginState

    public init(state: MusicPluginState = MusicPluginState()) {
        self.state = state
    }

    public func makeRailBarView(context: PurahPluginContext) -> AnyView {
        AnyView(
            MusicRailBarContainerView(
                state: state,
                store: context.store,
                slotHeight: context.slotHeight,
                railWidth: context.railWidth
            )
        )
    }

    public func makeDrawerView(context: PurahPluginContext) -> AnyView {
        AnyView(MusicDrawerView(state: state, store: context.store))
    }

    public static func normalizedSourceDisplayName(sourceApp: String, bundleId: String = "") -> String {
        let lower = sourceApp.lowercased()
        if lower == "music" || lower == "apple music" || bundleId == "com.apple.Music" {
            return "Apple Music"
        }
        if lower.contains("spotify") || bundleId == "com.spotify.client" {
            return "Spotify"
        }
        if lower.contains("chrome") {
            return "Chrome"
        }
        if lower.contains("safari") {
            return "Safari"
        }
        return sourceApp
    }

    public func makeHeaderAccessoryView(context: PurahPluginContext) -> AnyView? {
        let source = state.track.sourceApp
        let bundleId = state.track.sourceBundleId
        let displaySource = Self.normalizedSourceDisplayName(sourceApp: source, bundleId: bundleId)
        guard !displaySource.isEmpty else { return nil }
        return AnyView(
            Text(displaySource)
                .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                .foregroundColor(context.accentColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 1.5)
                .background(context.accentColor.opacity(0.12))
                .cornerRadius(4)
        )
    }

    public func makeHeaderTrailingView(context: PurahPluginContext) -> AnyView? {
        AnyView(AudioOutputDevicePickerView(accentColor: context.accentColor))
    }

    public func makeSettingsView(store: PurahWorkspaceStore) -> AnyView? {
        AnyView(MusicPluginSettingsView(state: state, store: store))
    }

    public func onMount(store: PurahWorkspaceStore) {
        state.mount(store: store)
    }

    public func onUnmount(store: PurahWorkspaceStore) {
        state.unmount(store: store)
    }

    public func minimumDrawerHeight(store: PurahWorkspaceStore) -> CGFloat { 110.0 }
    public func preferredDrawerHeight(store: PurahWorkspaceStore) -> CGFloat { 295.0 }
    public func adaptiveDrawerWidth(store: PurahWorkspaceStore) -> CGFloat? { 360.0 }

    public func onRailBarTap(subItemId: String?, context: PurahPluginContext) {
        context.performHaptic(.alignment)
        state.togglePlayPause(store: context.store)
    }
}

// MARK: - Calendar Plugin

public struct MusicPluginSettingsView: View {
    public let state: MusicPluginState
    public let store: PurahWorkspaceStore

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    public init(state: MusicPluginState, store: PurahWorkspaceStore = PurahWorkspaceStore()) {
        self.state = state
        self.store = store
    }

    public init(store: PurahWorkspaceStore) {
        let pluginState = (PluginRegistry.shared.plugin(for: "music") as? MusicPlugin)?.state ?? MusicPluginState()
        self.init(state: pluginState, store: store)
    }

    @ViewBuilder
    private func styleTile(title: String, icon: String, style: MusicRailStyle) -> some View {
        let isSelected = state.railStyle == style
        Button {
            withAnimation(PurahMotionPolicy.micro) {
                state.railStyle = style
                state.save()
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isSelected ? palette.primaryAccent : .secondary)

                Text(title)
                    .font(.system(size: 10, weight: isSelected ? .bold : .medium, design: .rounded))
                    .foregroundColor(isSelected ? palette.primaryAccent : .primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? palette.primaryAccent.opacity(0.12) : Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? palette.primaryAccent : palette.borderColor.opacity(0.2), lineWidth: isSelected ? 1.4 : 0.8)
            )
        }
        .buttonStyle(.plain)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Card 1: Rail Bar Visualizer Style
            PurahPluginSettingsCard(
                title: "Rail Bar Visualizer Style",
                subtitle: "Choose bezel visualization and rendering style",
                icon: "waveform",
                iconColor: palette.primaryAccent
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        styleTile(title: "Minimalist Pod", icon: "capsule.portrait.fill", style: .minimalist)
                        styleTile(title: "Smooth Progress", icon: "chart.bar.fill", style: .smoothProgress)
                        styleTile(title: "Dynamic Wave", icon: "waveform.path.ecg", style: .dynamicWaveform)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 10))
                            .foregroundColor(palette.primaryAccent)
                        Text(styleDescription(for: state.railStyle))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.025))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(palette.borderColor.opacity(0.15), lineWidth: 0.8)
                    )
                }
            }

            // Card 2: Dynamic Rhythm & Latency Calibration (only when dynamicWaveform)
            if state.railStyle == .dynamicWaveform {
                PurahPluginSettingsCard(
                    title: "Dynamic Rhythm & Latency Calibration",
                    subtitle: "Fine-tune audio wave responsiveness and visualizer scheme",
                    icon: "sparkles",
                    iconColor: Color(hex: "#BF5AF2")
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("music.effectScheme".localized)
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                Spacer()
                                Text(state.dynamicSubStyle.displayName)
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(palette.primaryAccent)
                            }

                            HStack(spacing: 6) {
                                ForEach(DynamicWaveformSubStyle.allCases, id: \.self) { sub in
                                    let isSelected = state.dynamicSubStyle == sub
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            state.dynamicSubStyle = sub
                                            state.save()
                                        }
                                    } label: {
                                        Text(sub.displayName)
                                            .font(.system(size: 10, weight: isSelected ? .bold : .medium, design: .rounded))
                                            .foregroundColor(isSelected ? palette.primaryAccent : .primary)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(
                                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                    .fill(isSelected ? palette.primaryAccent.opacity(0.14) : Color.primary.opacity(0.04))
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                    .stroke(isSelected ? palette.primaryAccent : palette.borderColor.opacity(0.2), lineWidth: isSelected ? 1.2 : 0.6)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }

                            Text(dynamicSubStyleDescription(for: state.dynamicSubStyle))
                                .font(.system(size: 9.5))
                                .foregroundColor(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text("music.beatAlignment".localized)
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                Spacer()
                                Text(state.rhythmOffsetMs <= 0 ? "0 ms (Direct)" : String(format: "+%.0f ms", state.rhythmOffsetMs))
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(palette.primaryAccent)
                            }

                            Slider(value: Binding(
                                get: { max(state.rhythmOffsetMs, 0.0) },
                                set: {
                                    state.rhythmOffsetMs = $0
                                    state.save()
                                    SystemAudioLiveMonitor.shared.latencyOffsetMs = $0
                                }
                            ), in: 0...200, step: 10)
                            .accessibilityLabel("music.beatAlignment".localized)

                            HStack {
                                Text("music.outputSpeakers".localized)
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("music.outputAirPods".localized)
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(9)
                        .background(Color.primary.opacity(0.025))
                        .cornerRadius(7)
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(palette.borderColor.opacity(0.15), lineWidth: 0.8)
                        )

                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("music.rhythmAnimation".localized)
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundColor(.primary)
                                Text("music.rhythmAnimation.desc".localized)
                                    .font(.system(size: 9.5))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { state.isWaveformAnimationEnabled },
                                set: {
                                    state.isWaveformAnimationEnabled = $0
                                    state.save()
                                    store.isMusicWaveformAnimationEnabled = $0
                                }
                            ))
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .labelsHidden()
                            .purahRowAccessibility("music.rhythmAnimation".localized, detail: "music.rhythmAnimation.desc".localized)
                        }
                        .padding(9)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.primary.opacity(0.03))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(palette.borderColor.opacity(0.2), lineWidth: 0.8)
                        )
                    }
                }
            }

            // Card 3: Live Audio Source
            PurahPluginSettingsCard(
                title: "Live Audio Source",
                subtitle: "Currently detected system media player",
                icon: "speaker.wave.2.fill",
                iconColor: Color(hex: "#34C759")
            ) {
                HStack(spacing: 8) {
                    let currentSource = !store._musicTrack.sourceApp.isEmpty ? store._musicTrack.sourceApp : state.track.sourceApp
                    HStack(spacing: 6) {
                        Image(systemName: "music.note")
                            .font(.system(size: 11))
                            .foregroundColor(palette.primaryAccent)
                        Text("Player: \(currentSource.isEmpty ? "None" : currentSource)")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(.primary)
                    }

                    Spacer()

                    let isPlaying = store._musicTrack.isPlaying
                    HStack(spacing: 4) {
                        Circle()
                            .fill(isPlaying ? Color.green : Color.secondary)
                            .frame(width: 7, height: 7)
                        Text(isPlaying ? "Playing" : "Paused")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(isPlaying ? .green : .secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(isPlaying ? Color.green.opacity(0.1) : Color.primary.opacity(0.05))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isPlaying ? Color.green.opacity(0.25) : palette.borderColor.opacity(0.2), lineWidth: 0.8)
                    )
                }
            }
        }
    }

    private func styleDescription(for style: MusicRailStyle) -> String {
        switch style {
        case .minimalist:
            return "Clean, static ambient capsule with zero animation and zero CPU usage."
        case .smoothProgress:
            return "Silky 60 FPS live-gliding progress bar driven by time-anchor calculation."
        case .dynamicWaveform:
            return "Metal GPU continuous fluid audio wave undulating to the rhythm of playback."
        }
    }

    private func dynamicSubStyleDescription(for sub: DynamicWaveformSubStyle) -> String {
        switch sub {
        case .neonVUTower:
            return "Cyberpunk 12-block multi-color spectrum tower bouncing to live bass kicks and beats."
        case .auroraWave:
            return "Seamless aurora borealis undulating gradient ribbon with organic acoustic breathing."
        }
    }
}

