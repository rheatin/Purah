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

    public func makeHeaderAccessoryView(context: PurahPluginContext) -> AnyView? {
        let source = state.track.sourceApp
        guard !source.isEmpty else { return nil }
        return AnyView(
            HStack(spacing: 3.5) {
                Image(systemName: state.track.sourceIconName)
                    .font(.system(size: 8, weight: .bold))
                Text(source)
                    .font(.system(size: 8.5, weight: .semibold, design: .rounded))
            }
            .foregroundColor(context.accentColor)
            .padding(.horizontal, 5)
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

    public init(state: MusicPluginState, store: PurahWorkspaceStore = PurahWorkspaceStore()) {
        self.state = state
        self.store = store
    }

    public init(store: PurahWorkspaceStore) {
        let pluginState = (PluginRegistry.shared.plugin(for: "music") as? MusicPlugin)?.state ?? MusicPluginState()
        self.init(state: pluginState, store: store)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Rail Bar Display Style")
                    .font(.subheadline.weight(.semibold))

                Picker("", selection: Binding(
                    get: { state.railStyle },
                    set: {
                        state.railStyle = $0
                        state.save()
                    }
                )) {
                    Text("Minimalist Pod").tag(MusicRailStyle.minimalist)
                    Text("Smooth Progress").tag(MusicRailStyle.smoothProgress)
                    Text("Dynamic Wave").tag(MusicRailStyle.dynamicWaveform)
                }
                .pickerStyle(.segmented)

                Text(styleDescription(for: state.railStyle))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if state.railStyle == .dynamicWaveform {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Dynamic Effect Scheme")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)

                    Picker("", selection: Binding(
                        get: { state.dynamicSubStyle },
                        set: {
                            state.dynamicSubStyle = $0
                            state.save()
                        }
                    )) {
                        ForEach(DynamicWaveformSubStyle.allCases, id: \.self) { sub in
                            Text(sub.displayName).tag(sub)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(dynamicSubStyleDescription(for: state.dynamicSubStyle))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Beat Timing Alignment")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(state.rhythmOffsetMs <= 0 ? "0 ms (Direct)" : String(format: "+%.0f ms", state.rhythmOffsetMs))
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                    }

                    Slider(value: Binding(
                        get: { max(state.rhythmOffsetMs, 0.0) },
                        set: {
                            state.rhythmOffsetMs = $0
                            state.save()
                            SystemAudioLiveMonitor.shared.latencyOffsetMs = $0
                        }
                    ), in: 0...200, step: 10)

                    HStack {
                        Text("Mac Speakers (0ms)")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("AirPods / Bluetooth (+150ms)")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 2)

                Toggle("Dynamic Rhythm Animation", isOn: Binding(
                    get: { state.isWaveformAnimationEnabled },
                    set: {
                        state.isWaveformAnimationEnabled = $0
                        state.save()
                        store.isMusicWaveformAnimationEnabled = $0
                    }
                ))
                .font(.subheadline)
            }

            HStack {
                let currentSource = !store._musicTrack.sourceApp.isEmpty ? store._musicTrack.sourceApp : state.track.sourceApp
                Text("Audio Source: \(currentSource.isEmpty ? "None" : currentSource)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(store._musicTrack.isPlaying ? "Playing" : "Paused")
                    .font(.caption.weight(.medium))
                    .foregroundColor(store._musicTrack.isPlaying ? .green : .secondary)
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

