// Sources/PurahUI/Plugins/PurahPodPlugin.swift
import SwiftUI
import UniformTypeIdentifiers
import PurahCore

@MainActor
public enum PurahRailBarDescriptor {
    /// Standard solid or subtle-gradient ambient rail bar owned by the host.
    /// - `color`: optional override color (defaults to `dynamicBarColor(context:) ?? context.accentColor`).
    /// - `hasContent`: when `false`, dims opacity to `0.40`; when `true`, renders at full ambient opacity.
    /// - `isGradient`: when `true`, renders a vertical top-to-bottom opacity gradient.
    case solid(color: Color? = nil, hasContent: Bool = true, isGradient: Bool = false)

    /// Single-segment or multi-segment vertical gauge bar (`PurahSegmentGaugeBarView`).
    case gauge(
        segments: [PurahGaugeSegment],
        trackColor: Color? = nil,
        minimumVisibleFill: CGFloat = 4,
        accessibilityValueLabel: String? = nil
    )

    /// Audio waveform / progress meter (`WaveMeterAmbientView`).
    case audioWave(
        style: MusicRailStyle,
        subStyle: DynamicWaveformSubStyle,
        track: MusicTrackInfo,
        progress: Double,
        samples: [Double],
        isPlaying: Bool,
        isAnimated: Bool,
        rhythmOffsetMs: Double = 0
    )
}

public struct PurahHostRailBarView: View {
    public let descriptor: PurahRailBarDescriptor
    public let context: PurahPluginContext

    public init(descriptor: PurahRailBarDescriptor, context: PurahPluginContext) {
        self.descriptor = descriptor
        self.context = context
    }

    public var body: some View {
        let barW = context.railWidth
        let barH = context.slotHeight
        let radius = min(barW / 2, 4)

        switch descriptor {
        case .solid(let customColor, let hasContent, let isGradient):
            let activeColor = customColor ?? context.accentColor
            if isGradient {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                activeColor.opacity(context.isExpanded ? 0.95 : 0.75),
                                activeColor.opacity(context.isExpanded ? 0.80 : 0.55)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: barW, height: barH)
            } else {
                RoundedRectangle(cornerRadius: radius)
                    .fill(activeColor.opacity(hasContent ? 0.88 : 0.40))
                    .frame(width: barW, height: barH)
            }

        case .gauge(let segments, let trackColor, let minimumVisibleFill, let accessibilityValueLabel):
            let baseView = PurahSegmentGaugeBarView(
                segments: segments,
                barWidth: barW,
                height: barH,
                trackColor: trackColor ?? context.accentColor.opacity(0.25),
                minimumVisibleFill: minimumVisibleFill
            )
            if let accessibilityValueLabel {
                baseView.accessibilityLabel(accessibilityValueLabel)
            } else {
                baseView
            }

        case .audioWave(let style, let subStyle, let track, let progress, let samples, let isPlaying, let isAnimated, let rhythmOffsetMs):
            WaveMeterAmbientView(
                style: style,
                subStyle: subStyle,
                track: track,
                progress: progress,
                samples: samples,
                isPlaying: isPlaying,
                isAnimated: isAnimated,
                height: barH,
                barWidth: barW
            )
            .frame(width: barW, height: barH)
            .onAppear {
                SystemAudioLiveMonitor.shared.latencyOffsetMs = rhythmOffsetMs
            }
        }
    }
}

@MainActor
public protocol PurahPodPlugin: PurahPodCapabilityProvider, Identifiable, Sendable {
    nonisolated var manifest: PurahPluginManifest { get }
    func alertStyle(store: PurahWorkspaceStore) -> PluginAlertStyle?

    /// Declarative descriptor for the pod's composite rail bar. The host owns
    /// all edge rail rendering (`PurahHostRailBarView`); plugins only declare
    /// which pod style and data they want on the rail.
    func railBarDescriptor(context: PurahPluginContext) -> PurahRailBarDescriptor

    @ViewBuilder func makeRailBarView(context: PurahPluginContext) -> AnyView
    @ViewBuilder func makeDrawerView(context: PurahPluginContext) -> AnyView
    @ViewBuilder func makeSettingsView(store: PurahWorkspaceStore) -> AnyView?
    @ViewBuilder func makeSteppedDrawerView(subItemId: String, context: PurahPluginContext) -> AnyView?
    /// Body for a stepped chip's expanded drawer. The host supplies the card
    /// (rail bar, background, the one row with settings/pin, on-screen clamp);
    /// the plugin supplies only what goes below that row, sized to
    /// `context.slotHeight` — zero on a minimum-size chip. Returning nil keeps
    /// `makeSteppedDrawerView`.
    @ViewBuilder func makeSteppedDrawerContent(subItemId: String, context: PurahPluginContext) -> AnyView?
    /// How much body this chip needs before it is worth drawing. A chip whose
    /// row already says everything (a vitals badge) stays a clean row until the
    /// pod is tall enough for its body to render properly, instead of squeezing
    /// a graph into a 20pt sliver.
    func steppedDrawerMinimumBodyHeight(subItemId: String) -> CGFloat
    /// One action at the end of the chip's row, just before settings/pin — a
    /// calendar's Join button. The row is the whole card, so this is the only
    /// place a per-chip action fits; the trailing column itself belongs to the
    /// host (a plugin button there would collide with the gear and the pin).
    @ViewBuilder func makeSteppedRowAccessory(subItemId: String, context: PurahPluginContext) -> AnyView?
    // Requirement (not just an extension default) so existential calls
    // dynamically dispatch to the plugin's override.
    @ViewBuilder func makeOverviewDrawerContent(context: PurahPluginContext) -> AnyView?

    func onMount(store: PurahWorkspaceStore)
    func onUnmount(store: PurahWorkspaceStore)

    // 1. Dynamic Bar Color (e.g. telemetry color, alerting tint)
    func dynamicBarColor(context: PurahPluginContext) -> Color?

    // Dynamic Accent Color (e.g. telemetry load color)
    func dynamicAccentColor(store: PurahWorkspaceStore?) -> Color?

    // 2. Supported Drawer Modes (Composite vs Stepped)
    var supportedDrawerModes: Set<PurahDrawerMode> { get }

    // 3. Stepped sub-items for decomposed rail chips
    func steppedItems(context: PurahPluginContext) -> [PurahPluginSubItem]

    // 4. One-Tap Rail Bar Fire
    func onRailBarTap(subItemId: String?, context: PurahPluginContext)

    // 5. Native Drag & Drop Ingestion
    var supportedDropTypes: [UTType] { get }
    func onDrop(providers: [NSItemProvider], context: PurahPluginContext) -> Bool

    // 6. Central Managed Polling Hook
    var preferredPollingInterval: TimeInterval? { get }
    func onPollingTick(store: PurahWorkspaceStore) async

    // 7. Native Context Menu Actions
    func contextMenuActions(subItemId: String?, context: PurahPluginContext) -> [PurahMenuAction]

    // 8. Custom Header Slots (accessories next to title & trailing tools before settings/pin)
    func headerAccessory(context: PurahPluginContext) -> PurahHeaderAccessoryDescriptor?
    func headerTrailingItems(context: PurahPluginContext) -> [PurahHeaderTrailingItem]
    func onHeaderAction(actionId: String, context: PurahPluginContext)
    @ViewBuilder func makeHeaderAccessoryView(context: PurahPluginContext) -> AnyView?
    @ViewBuilder func makeHeaderTrailingView(context: PurahPluginContext) -> AnyView?

    // 9. Adaptive Telemetry Color
    var usesAdaptiveTelemetryColor: Bool { get }

    // 10. Alert Management
    func acknowledgeAllAlerts(context: PurahPluginContext)

    // 11. Declarative Settings Schema
    func settingsSections(store: PurahWorkspaceStore) -> [PurahPluginSettingSection]
    func onSettingChanged(key: String, value: String, store: PurahWorkspaceStore)
}

public extension PurahPodPlugin {
    nonisolated var id: String { manifest.id }
    var podId: String { manifest.id }
    func alertStyle(store: PurahWorkspaceStore) -> PluginAlertStyle? { manifest.alertStyle }

    func railBarDescriptor(context: PurahPluginContext) -> PurahRailBarDescriptor {
        .solid(color: dynamicBarColor(context: context) ?? context.accentColor, hasContent: true)
    }

    func makeRailBarView(context: PurahPluginContext) -> AnyView {
        AnyView(PurahHostRailBarView(descriptor: railBarDescriptor(context: context), context: context))
    }

    /// Whether the pod starts in stepped (chips) mode. A plugin that wants
    /// that must say so explicitly — declaring `supportedDrawerModes` only
    /// states that the mode exists, not that it is the default. The base
    /// fallback is composite, so a plugin never lands in a presentation it
    /// did not ask for.
    var isDecomposed: Bool { false }
    var decomposedPolicy: PurahDecomposedPolicy {
        supportedDrawerModes.contains(.stepped) ? .calendarDefault : .standardComposite
    }

    func isDecomposed(store: PurahWorkspaceStore) -> Bool { isDecomposed }
    func decomposedPolicy(store: PurahWorkspaceStore) -> PurahDecomposedPolicy { decomposedPolicy }
    func minimumDrawerHeight(store: PurahWorkspaceStore) -> CGFloat {
        if isDecomposed(store: store) {
            return decomposedPolicy(store: store).calculateMinimumHeight(activeCount: subItemCount(store: store))
        }
        return 120.0
    }
    func hasPinnedChild(store: PurahWorkspaceStore) -> Bool { false }
    func ownsSubItemId(_ itemId: String, store: PurahWorkspaceStore) -> Bool { itemId.hasPrefix("\(manifest.id)-") }

    func onMount(store: PurahWorkspaceStore) {}
    func onUnmount(store: PurahWorkspaceStore) {}
    func settingsSections(store: PurahWorkspaceStore) -> [PurahPluginSettingSection] { [] }
    func onSettingChanged(key: String, value: String, store: PurahWorkspaceStore) {}

    func makeSettingsView(store: PurahWorkspaceStore) -> AnyView? {
        let sections = settingsSections(store: store)
        guard !sections.isEmpty else { return nil }
        return AnyView(PurahDeclarativeSettingsView(
            store: store,
            sectionsProvider: { [weak store] in
                guard let store else { return [] }
                return self.settingsSections(store: store)
            },
            onSettingChanged: { [weak store] key, val in
                guard let store else { return }
                self.onSettingChanged(key: key, value: val, store: store)
            }
        ))
    }
    func makeSteppedDrawerView(subItemId: String, context: PurahPluginContext) -> AnyView? { nil }
    func makeSteppedDrawerContent(subItemId: String, context: PurahPluginContext) -> AnyView? { nil }
    func makeSteppedRowAccessory(subItemId: String, context: PurahPluginContext) -> AnyView? { nil }
    func steppedDrawerMinimumBodyHeight(subItemId: String) -> CGFloat { 48.0 }
    func headerAccessory(context: PurahPluginContext) -> PurahHeaderAccessoryDescriptor? { nil }
    func headerTrailingItems(context: PurahPluginContext) -> [PurahHeaderTrailingItem] { [] }
    func onHeaderAction(actionId: String, context: PurahPluginContext) {}

    func makeHeaderAccessoryView(context: PurahPluginContext) -> AnyView? {
        if let descriptor = headerAccessory(context: context) {
            return AnyView(PurahHostHeaderAccessoryView(descriptor: descriptor, context: context) { actionId in
                self.onHeaderAction(actionId: actionId, context: context)
            })
        }
        return nil
    }

    func makeHeaderTrailingView(context: PurahPluginContext) -> AnyView? {
        let items = headerTrailingItems(context: context)
        if !items.isEmpty {
            return AnyView(PurahHostHeaderTrailingView(items: items, context: context) { actionId in
                self.onHeaderAction(actionId: actionId, context: context)
            })
        }
        return nil
    }

    /// Content-only view for the pod's "+N more" overview drawer. The stepped
    /// container supplies the shared shell (rail bar, drawer-grade solid card,
    /// edge-flush shape, slide-in transition) so every overview looks and
    /// animates identically. Return nil if the pod has no overview drawer.
    func makeOverviewDrawerContent(context: PurahPluginContext) -> AnyView? { nil }


    var usesAdaptiveTelemetryColor: Bool { false }
    func acknowledgeAllAlerts(context: PurahPluginContext) {}

    func dynamicBarColor(context: PurahPluginContext) -> Color? { nil }
    func dynamicAccentColor(store: PurahWorkspaceStore?) -> Color? { nil }
    var supportedDrawerModes: Set<PurahDrawerMode> { [.composite] }
    func steppedItems(context: PurahPluginContext) -> [PurahPluginSubItem] { [] }
    func onRailBarTap(subItemId: String?, context: PurahPluginContext) {
        context.requestExpand()
    }

    var supportedDropTypes: [UTType] { [] }
    func onDrop(providers: [NSItemProvider], context: PurahPluginContext) -> Bool { false }

    var preferredPollingInterval: TimeInterval? { nil }
    func onPollingTick(store: PurahWorkspaceStore) async {}

    func contextMenuActions(subItemId: String?, context: PurahPluginContext) -> [PurahMenuAction] {
        let isPinned = context.isPinned
        return [
            PurahMenuAction(
                title: isPinned ? "Unpin Drawer" : "Pin Drawer",
                systemImage: isPinned ? "pin.slash.fill" : "pin.fill",
                action: { context.togglePin() }
            )
        ]
    }
}
