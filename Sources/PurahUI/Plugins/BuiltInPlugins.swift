// Sources/PurahUI/Plugins/BuiltInPlugins.swift
import SwiftUI
import AppKit
import PurahCore
import UniformTypeIdentifiers

// MARK: - Hardware Vitals Plugin
public struct HardwareVitalsPlugin: PurahPodPlugin {
    public nonisolated let manifest = PurahPluginManifest(
        id: "vitals",
        displayName: "Hardware Vitals",
        systemIcon: "waveform.path.ecg",
        author: "Project Purah",
        version: "0.1.0",
        description: "Real-time hardware performance, memory, and power monitoring",
        defaultEdge: .left,
        preferredZone: .glance,
        ergonomicWeight: 35.0,
        minLengthRatio: 0.22,
        defaultColorHex: "#00E5A3",
        permissions: [.machTelemetry]
    )

    public let state: VitalsPluginState

    public init(state: VitalsPluginState = VitalsPluginState()) {
        self.state = state
    }

    public func makeRailBarView(context: PurahPluginContext) -> AnyView {
        AnyView(VitalsRailBarPluginView(context: context, state: state))
    }

    public func makeDrawerView(context: PurahPluginContext) -> AnyView {
        AnyView(HardwareVitalsDrawerView(state: state, store: context.store))
    }

    public func makeHeaderAccessoryView(context: PurahPluginContext) -> AnyView? {
        AnyView(
            Text("CPU \(Int(state.metrics.cpuUsage * 100))%")
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                .foregroundColor(context.accentColor)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(context.accentColor.opacity(0.16))
                .cornerRadius(3)
        )
    }

    public func makeSettingsView(store: PurahWorkspaceStore) -> AnyView? {
        AnyView(VitalsPluginSettingsView(state: state, store: store))
    }

    public func onMount(store: PurahWorkspaceStore) {
        state.mount(store: store)
    }

    public func onUnmount(store: PurahWorkspaceStore) {
        state.unmount(store: store)
    }

    public var supportedDrawerModes: Set<PurahDrawerMode> { [.composite, .stepped] }

    public func minimumDrawerHeight(store: PurahWorkspaceStore) -> CGFloat {
        let isDecomp = state.isDecomposed || store._isVitalsDecomposed
        if isDecomp {
            let metrics = !store._vitalsEnabledMetrics.isEmpty ? store._vitalsEnabledMetrics : state.enabledMetrics
            let count = max(metrics.count, 1)
            return CGFloat(count) * 56.0 + CGFloat(count - 1) * 2.5
        }
        return 300.0
    }

    public func hasPinnedChild(store: PurahWorkspaceStore) -> Bool {
        let metrics = !store._vitalsEnabledMetrics.isEmpty ? store._vitalsEnabledMetrics : state.enabledMetrics
        return metrics.contains { store.isItemPinned(id: "vitals-\($0.rawValue)") }
    }

    public func ownsSubItemId(_ itemId: String, store: PurahWorkspaceStore) -> Bool {
        itemId.hasPrefix("vitals-")
    }

    public var isDecomposed: Bool {
        state.isDecomposed
    }

    public func isDecomposed(store: PurahWorkspaceStore) -> Bool {
        state.isDecomposed || store._isVitalsDecomposed
    }

    public var subItemCount: Int {
        state.isDecomposed ? state.enabledMetrics.count : 0
    }

    public var subItemTitles: [String] {
        state.isDecomposed ? state.enabledMetrics.map(\.displayName) : []
    }

    public func subItemCount(store: PurahWorkspaceStore) -> Int {
        let isDecomp = state.isDecomposed || store._isVitalsDecomposed
        guard isDecomp else { return 0 }
        let metrics = !store._vitalsEnabledMetrics.isEmpty ? store._vitalsEnabledMetrics : state.enabledMetrics
        return metrics.count
    }

    public func subItemId(at index: Int, store: PurahWorkspaceStore) -> String? {
        let isDecomp = state.isDecomposed || store._isVitalsDecomposed
        guard isDecomp else { return nil }
        let metrics = !store._vitalsEnabledMetrics.isEmpty ? store._vitalsEnabledMetrics : state.enabledMetrics
        guard metrics.indices.contains(index) else { return nil }
        return "vitals-\(metrics[index].rawValue)"
    }

    public func subItemTitle(at index: Int, store: PurahWorkspaceStore) -> String? {
        let isDecomp = state.isDecomposed || store._isVitalsDecomposed
        guard isDecomp else { return nil }
        let metrics = !store._vitalsEnabledMetrics.isEmpty ? store._vitalsEnabledMetrics : state.enabledMetrics
        guard metrics.indices.contains(index) else { return nil }
        return metrics[index].displayName
    }

    public func dynamicBarColor(context: PurahPluginContext) -> Color? {
        VitalsColorResolver.overallVitalsColor(
            vitals: state.metrics,
            thresholds: state.thresholds,
            palette: context.palette
        )
    }

    public func steppedItems(context: PurahPluginContext) -> [PurahPluginSubItem] {
        let metrics = state.metrics
        return state.enabledMetrics.map { metric in
            let ratio: Double = {
                switch metric {
                case .cpu: return metrics.cpuUsage
                case .gpu: return metrics.gpuUsage
                case .ram: return metrics.memoryUsage
                case .power: return Double(metrics.batteryLevel) / 100.0
                case .network: return min((metrics.networkDownSpeed + metrics.networkUpSpeed) / 10_485_760.0, 1.0)
                case .disk:
                    return metrics.diskTotalGB > 0 ? (metrics.diskTotalGB - metrics.diskFreeGB) / metrics.diskTotalGB : 0.5
                }
            }()
            let color = VitalsColorResolver.color(for: metric, vitals: metrics, thresholds: state.thresholds, palette: context.palette)
            let isAlerting = (metric == .cpu && metrics.cpuUsage > state.thresholds.cpuDanger) ||
                             (metric == .ram && metrics.memoryUsage > state.thresholds.ramDanger)
            return PurahPluginSubItem(
                id: "vitals-\(metric.rawValue)",
                title: metric.displayName,
                systemIcon: metric.systemIcon,
                state: isAlerting ? .alerting : .normal,
                gaugeRatio: ratio,
                gaugeStyle: .solid,
                tintColorHex: color.toHex(),
                isPinned: context.store.isItemPinned(id: "vitals-\(metric.rawValue)")
            )
        }
    }

    public func makeSteppedDrawerView(subItemId: String, context: PurahPluginContext) -> AnyView? {
        let metricKey = subItemId.replacingOccurrences(of: "vitals-", with: "")
        guard let metric = VitalsMetricType(rawValue: metricKey) else { return nil }
        let isPinned = context.store.isItemPinned(id: subItemId)
        let state: ItemDrawerState = (context.isExpanded || isPinned) ? .expandedDrawer : .dockedFlush
        return AnyView(
            VitalsItemDrawerView(
                metric: metric,
                edge: context.edge,
                state: state,
                isPinned: isPinned,
                height: context.slotHeight,
                store: context.store,
                onTogglePin: {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.65)) {
                        context.store.togglePinItem(id: subItemId)
                    }
                }
            )
        )
    }
}

public struct VitalsRailBarPluginView: View {
    public let context: PurahPluginContext
    public let state: VitalsPluginState

    public init(context: PurahPluginContext, state: VitalsPluginState? = nil) {
        self.context = context
        self.state = state ?? (PluginRegistry.shared.plugin(for: "vitals") as? HardwareVitalsPlugin)?.state ?? VitalsPluginState()
    }

    public var body: some View {
        let cpu = state.metrics.cpuUsage
        let isPulsing = cpu > 0.85
        let radius = min(context.railWidth / 2, 4)

        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: radius)
                .fill(context.accentColor.opacity(0.25))
                .frame(width: context.railWidth, height: context.slotHeight)

            RoundedRectangle(cornerRadius: radius)
                .fill(context.accentColor)
                .frame(width: context.railWidth, height: max(context.slotHeight * CGFloat(cpu), 4.0))
                .modifier(OptionalGlow(color: context.accentColor, enabled: isPulsing))
        }
        .frame(width: context.railWidth, height: context.slotHeight)
    }
}

// MARK: - Script Runway Plugin
public struct ScriptRunwayPlugin: PurahPodPlugin {
    public nonisolated let manifest = PurahPluginManifest(
        id: "scripts",
        displayName: "Script Runway",
        systemIcon: "terminal.fill",
        author: "Project Purah",
        version: "0.1.0",
        description: "Quick-fire terminal commands and automation runway",
        defaultEdge: .left,
        preferredZone: .quickFlick,
        ergonomicWeight: 30.0,
        minLengthRatio: 0.18,
        defaultColorHex: "#A78BFA",
        permissions: [.shellExecution]
    )

    public let state: ScriptsPluginState

    public init(state: ScriptsPluginState = ScriptsPluginState()) {
        self.state = state
    }

    public func makeRailBarView(context: PurahPluginContext) -> AnyView {
        AnyView(ScriptsRailBarPluginView(context: context))
    }

    public func makeDrawerView(context: PurahPluginContext) -> AnyView {
        AnyView(ScriptRunwayDrawerView(state: state, store: context.store))
    }

    public func makeHeaderAccessoryView(context: PurahPluginContext) -> AnyView? {
        AnyView(
            Text("\(state.actions.count) ACTIONS")
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                .foregroundColor(context.accentColor)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(context.accentColor.opacity(0.16))
                .cornerRadius(3)
        )
    }

    public func makeSettingsView(store: PurahWorkspaceStore) -> AnyView? {
        AnyView(ScriptsPluginSettingsView(state: state, store: store))
    }

    public func onMount(store: PurahWorkspaceStore) {
        state.mount(store: store)
    }

    public func onUnmount(store: PurahWorkspaceStore) {
        state.unmount(store: store)
    }

    public var supportedDrawerModes: Set<PurahDrawerMode> { [.composite, .stepped] }

    public func minimumDrawerHeight(store: PurahWorkspaceStore) -> CGFloat {
        let isDecomp = state.isDecomposed || store._isScriptsDecomposed
        if isDecomp {
            let actions = !store._scriptsEnabledActionIds.isEmpty ? store.scriptsEnabledActions : state.enabledActions
            let count = max(actions.count, 1)
            return CGFloat(count) * 56.0 + CGFloat(count - 1) * 2.5
        }
        return 160.0
    }

    public func hasPinnedChild(store: PurahWorkspaceStore) -> Bool {
        let actions = !store._scriptsEnabledActionIds.isEmpty ? store.scriptsEnabledActions : state.enabledActions
        return actions.contains { store.isItemPinned(id: "scripts-\($0.id)") }
    }

    public func ownsSubItemId(_ itemId: String, store: PurahWorkspaceStore) -> Bool {
        itemId.hasPrefix("scripts-")
    }

    public var isDecomposed: Bool {
        state.isDecomposed
    }

    public func isDecomposed(store: PurahWorkspaceStore) -> Bool {
        state.isDecomposed || store._isScriptsDecomposed
    }

    public var subItemCount: Int {
        state.isDecomposed ? state.enabledActions.count : 0
    }

    public var subItemTitles: [String] {
        state.isDecomposed ? state.enabledActions.map(\.name) : []
    }

    public func subItemCount(store: PurahWorkspaceStore) -> Int {
        let isDecomp = state.isDecomposed || store._isScriptsDecomposed
        guard isDecomp else { return 0 }
        let actions = !store._scriptsEnabledActionIds.isEmpty ? store.scriptsEnabledActions : state.enabledActions
        return actions.count
    }

    public func subItemId(at index: Int, store: PurahWorkspaceStore) -> String? {
        let isDecomp = state.isDecomposed || store._isScriptsDecomposed
        guard isDecomp else { return nil }
        let actions = !store._scriptsEnabledActionIds.isEmpty ? store.scriptsEnabledActions : state.enabledActions
        guard actions.indices.contains(index) else { return nil }
        return "scripts-\(actions[index].id)"
    }

    public func subItemTitle(at index: Int, store: PurahWorkspaceStore) -> String? {
        let isDecomp = state.isDecomposed || store._isScriptsDecomposed
        guard isDecomp else { return nil }
        let actions = !store._scriptsEnabledActionIds.isEmpty ? store.scriptsEnabledActions : state.enabledActions
        guard actions.indices.contains(index) else { return nil }
        return actions[index].name
    }

    public func steppedItems(context: PurahPluginContext) -> [PurahPluginSubItem] {
        let runway = ScriptRunwayService.shared
        return state.enabledActions.map { action in
            let isRunning = (state.isRunning && state.lastExecutedActionId == action.id) ||
                            (runway.isRunning && runway.lastExecutedActionId == action.id)
            return PurahPluginSubItem(
                id: "scripts-\(action.id)",
                title: action.name,
                subtitle: action.description.isEmpty ? action.scriptContent : action.description,
                systemIcon: action.systemIcon,
                badge: action.commandType.rawValue.uppercased(),
                state: isRunning ? .running : .normal,
                gaugeRatio: nil,
                gaugeStyle: .none,
                tintColorHex: nil,
                isPinned: context.store.isItemPinned(id: "scripts-\(action.id)")
            )
        }
    }

    public func onRailBarTap(subItemId: String?, context: PurahPluginContext) {
        if let subId = subItemId?.replacingOccurrences(of: "scripts-", with: ""),
           let action = state.action(for: subId) ?? ScriptRunwayService.shared.action(for: subId) {
            context.performHaptic(.levelChange)
            Task {
                let res = await state.executeAction(action, store: context.store)
                if action.showNotification {
                    if res.success {
                        context.performHaptic(.alignment)
                        context.showToast("Ran \(action.name)", "checkmark.circle.fill")
                    } else {
                        context.showWarning("Failed: \(res.message)")
                    }
                } else if res.success {
                    context.performHaptic(.alignment)
                }
            }
        } else {
            context.requestExpand()
        }
    }

    public func makeSteppedDrawerView(subItemId: String, context: PurahPluginContext) -> AnyView? {
        let actionId = subItemId.replacingOccurrences(of: "scripts-", with: "")
        guard let action = state.action(for: actionId) ?? ScriptRunwayService.shared.action(for: actionId) else { return nil }
        let isPinned = context.store.isItemPinned(id: subItemId)
        let state: ItemDrawerState = (context.isExpanded || isPinned) ? .expandedDrawer : .dockedFlush
        return AnyView(
            ScriptItemDrawerView(
                action: action,
                edge: context.edge,
                state: state,
                isPinned: isPinned,
                height: context.slotHeight,
                store: context.store,
                onTogglePin: {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.65)) {
                        context.store.togglePinItem(id: subItemId)
                    }
                }
            )
        )
    }
}

public struct ScriptsRailBarPluginView: View {
    public let context: PurahPluginContext

    public init(context: PurahPluginContext) {
        self.context = context
    }

    public var body: some View {
        let radius = min(context.railWidth / 2, 4)
        RoundedRectangle(cornerRadius: radius)
            .fill(context.accentColor.opacity(0.88))
            .frame(width: context.railWidth, height: context.slotHeight)
    }
}

// MARK: - Quick Notes Plugin
public struct QuickNotesPlugin: PurahPodPlugin {
    public nonisolated let manifest = PurahPluginManifest(
        id: "notes",
        displayName: "Quick Notes",
        systemIcon: "note.text",
        author: "Project Purah",
        version: "0.1.0",
        description: "Instant scratchpad for fleeting thoughts and code snippets",
        defaultEdge: .left,
        preferredZone: .quickFlick,
        ergonomicWeight: 30.0,
        minLengthRatio: 0.16,
        defaultColorHex: "#FFD60A"
    )

    public let state: NotesPluginState

    public init(state: NotesPluginState = NotesPluginState()) {
        self.state = state
    }

    public func makeRailBarView(context: PurahPluginContext) -> AnyView {
        AnyView(
            RailBarAmbientView(
                type: .notes,
                hasContent: !state.noteContent.text.isEmpty,
                color: context.accentColor,
                barWidth: context.railWidth
            )
            .frame(width: context.railWidth, height: context.slotHeight)
        )
    }

    public func makeDrawerView(context: PurahPluginContext) -> AnyView {
        AnyView(QuickNoteDrawerView(state: state, store: context.store))
    }

    public func makeHeaderTrailingView(context: PurahPluginContext) -> AnyView? {
        AnyView(
            Text("\(state.noteContent.text.count)c")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(context.accentColor.opacity(0.85))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(context.accentColor.opacity(0.12))
                .cornerRadius(3)
        )
    }

    public func makeSettingsView(store: PurahWorkspaceStore) -> AnyView? {
        AnyView(NotesPluginSettingsView(state: state, store: store))
    }

    public func onMount(store: PurahWorkspaceStore) {
        state.mount(store: store)
    }

    public func onUnmount(store: PurahWorkspaceStore) {
        state.unmount(store: store)
    }

    public func minimumDrawerHeight(store: PurahWorkspaceStore) -> CGFloat { 130.0 }
    public func adaptiveDrawerWidth(store: PurahWorkspaceStore) -> CGFloat? { 320.0 }
}

// MARK: - Drop Shelf Plugin
public struct DropShelfPlugin: PurahPodPlugin {
    public nonisolated let manifest = PurahPluginManifest(
        id: "shelf",
        displayName: "Drop Shelf",
        systemIcon: "tray.and.arrow.down.fill",
        author: "Project Purah",
        version: "0.1.0",
        description: "Transient holding area for dragged files and assets",
        defaultEdge: .left,
        preferredZone: .quickFlick,
        ergonomicWeight: 35.0,
        minLengthRatio: 0.16,
        defaultColorHex: "#BF5AF2",
        permissions: [.fileSystem]
    )

    public let state: ShelfPluginState

    public init(state: ShelfPluginState = ShelfPluginState()) {
        self.state = state
    }

    public func makeRailBarView(context: PurahPluginContext) -> AnyView {
        AnyView(
            RailBarAmbientView(
                type: .shelf,
                hasContent: !state.files.isEmpty,
                color: context.accentColor,
                barWidth: context.railWidth
            )
            .frame(width: context.railWidth, height: context.slotHeight)
        )
    }

    public func makeDrawerView(context: PurahPluginContext) -> AnyView {
        AnyView(DropShelfDrawerView(state: state, store: context.store))
    }

    public func makeSettingsView(store: PurahWorkspaceStore) -> AnyView? {
        AnyView(ShelfPluginSettingsView(state: state, store: store))
    }

    public func onMount(store: PurahWorkspaceStore) {
        state.mount(store: store)
    }

    public func onUnmount(store: PurahWorkspaceStore) {
        state.unmount(store: store)
    }

    public func minimumDrawerHeight(store: PurahWorkspaceStore) -> CGFloat { 130.0 }
    public func adaptiveDrawerWidth(store: PurahWorkspaceStore) -> CGFloat? { 360.0 }

    public var supportedDropTypes: [UTType] { [.fileURL] }

    public func onDrop(providers: [NSItemProvider], context: PurahPluginContext) -> Bool {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url = url {
                    Task { @MainActor in
                        state.addFile(url: url)
                        context.performHaptic(.alignment)
                        context.showToast("Stashed \(url.lastPathComponent)", "tray.and.arrow.down.fill")
                    }
                }
            }
        }
        return true
    }
}

// MARK: - Reactive Live Rail Bar View for Music Plugin
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
        let isPlaying = storeTrack.isPlaying
        let liveTrack = !storeTrack.title.isEmpty ? storeTrack : state.track

        WaveMeterAmbientView(
            style: state.railStyle,
            subStyle: state.dynamicSubStyle,
            track: liveTrack,
            progress: liveTrack.calculatedProgress,
            samples: liveTrack.waveformSamples,
            isPlaying: isPlaying,
            isAnimated: state.isWaveformAnimationEnabled,
            height: slotHeight
        )
        .frame(width: railWidth, height: slotHeight)
        .onAppear {
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
public struct CalendarPlugin: PurahPodPlugin {
    public nonisolated let manifest = PurahPluginManifest(
        id: "calendar",
        displayName: "Calendar Timeline",
        systemIcon: "calendar",
        author: "Project Purah",
        version: "0.1.0",
        description: "Day and week agenda timeline with upcoming event alerts",
        defaultEdge: .right,
        preferredZone: .goldenAction,
        ergonomicWeight: 45.0,
        minLengthRatio: 0.16,
        defaultColorHex: "#FF9F0A",
        permissions: [.calendar]
    )

    public let state: CalendarPluginState

    public init(state: CalendarPluginState = CalendarPluginState()) {
        self.state = state
    }

    public func makeRailBarView(context: PurahPluginContext) -> AnyView {
        AnyView(
            ProgressTimelineAmbientView(
                progress: SystemCalendarSyncService.shared.todayProgress()
            )
            .frame(width: context.railWidth, height: context.slotHeight)
        )
    }

    public func makeDrawerView(context: PurahPluginContext) -> AnyView {
        AnyView(CalendarDrawerView(state: state, store: context.store))
    }

    public func makeSettingsView(store: PurahWorkspaceStore) -> AnyView? {
        AnyView(CalendarPluginSettingsView(state: state, store: store))
    }

    public func onMount(store: PurahWorkspaceStore) {
        state.mount(store: store)
        store.calendarMaxRailEvents = state.maxRailEvents
    }

    public func onUnmount(store: PurahWorkspaceStore) {
        state.unmount(store: store)
    }

    public var supportedDrawerModes: Set<PurahDrawerMode> {
        if state.overflowStrategy == .continuousStream {
            return [.composite]
        }
        return [.stepped]
    }

    public func minimumDrawerHeight(store: PurahWorkspaceStore) -> CGFloat {
        if state.overflowStrategy == .continuousStream {
            return 140.0
        }
        let maxEvents = max(state.maxRailEvents, 1)
        let minChipH: CGFloat = 40.0
        let spacing: CGFloat = 2.5
        let totalSpacing = CGFloat(maxEvents - 1) * spacing
        return CGFloat(maxEvents) * minChipH + totalSpacing
    }

    private func effectiveEvents(store: PurahWorkspaceStore) -> [CalendarEventItem] {
        var combined = state.events
        for e in store._calendarEvents {
            if !combined.contains(where: { $0.id == e.id }) {
                combined.append(e)
            }
        }
        return combined
    }

    public func hasPinnedChild(store: PurahWorkspaceStore) -> Bool {
        if store.isItemPinned(id: "calendar_more_events") { return true }
        return effectiveEvents(store: store).contains { store.isItemPinned(id: $0.id) }
    }

    public func ownsSubItemId(_ itemId: String, store: PurahWorkspaceStore) -> Bool {
        if itemId == "calendar_more_events" { return true }
        return effectiveEvents(store: store).contains { $0.id == itemId }
    }

    public var isDecomposed: Bool {
        state.overflowStrategy != .continuousStream
    }

    public func isDecomposed(store: PurahWorkspaceStore) -> Bool {
        state.overflowStrategy != .continuousStream
    }

    private func resolvedSubItemHeaders(store: PurahWorkspaceStore) -> [(id: String, title: String)] {
        guard state.overflowStrategy != .continuousStream else { return [] }
        let currentTime = CACurrentMediaTime()
        if currentTime - state.cacheTimestamp < 0.25 && !state.cachedSubItemHeaders.isEmpty {
            return state.cachedSubItemHeaders
        }

        let allEvents = effectiveEvents(store: store)
        guard !allEvents.isEmpty else {
            state.cachedSubItemHeaders = []
            state.cacheTimestamp = currentTime
            return []
        }

        let now = Date()
        let sortedEvents = allEvents.sorted { a, b in
            if a.isOngoing != b.isOngoing {
                return a.isOngoing && !b.isOngoing
            }
            if a.isImminent != b.isImminent {
                return a.isImminent && !b.isImminent
            }
            let aPast = a.endTime < now
            let bPast = b.endTime < now
            if aPast != bPast {
                return !aPast && bPast
            }
            return a.startTime < b.startTime
        }

        let maxLimit = (state.overflowStrategy == .smartFold) ? max(state.maxRailEvents, 2) : sortedEvents.count
        var result: [(id: String, title: String)] = []

        if state.overflowStrategy == .smartFold && sortedEvents.count > maxLimit {
            let primaryCount = maxLimit - 1
            result = sortedEvents.prefix(primaryCount).map { ($0.id, $0.title) }
            let remaining = sortedEvents.count - primaryCount
            let moreTitle = String(format: "calendar.overview.moreEvents".localized, remaining)
            result.append(("calendar_more_events", moreTitle))
        } else {
            result = sortedEvents.map { ($0.id, $0.title) }
        }

        state.cachedSubItemHeaders = result
        state.cacheTimestamp = currentTime
        return result
    }

    public var subItemCount: Int {
        resolvedSubItemHeaders(store: PurahWorkspaceStore()).count
    }

    public var subItemTitles: [String] {
        resolvedSubItemHeaders(store: PurahWorkspaceStore()).map(\.title)
    }

    public func subItemCount(store: PurahWorkspaceStore) -> Int {
        resolvedSubItemHeaders(store: store).count
    }

    public func subItemId(at index: Int, store: PurahWorkspaceStore) -> String? {
        let items = resolvedSubItemHeaders(store: store)
        guard items.indices.contains(index) else { return nil }
        return items[index].id
    }

    public func subItemTitle(at index: Int, store: PurahWorkspaceStore) -> String? {
        let items = resolvedSubItemHeaders(store: store)
        guard items.indices.contains(index) else { return nil }
        return items[index].title
    }

    public func steppedItems(context: PurahPluginContext) -> [PurahPluginSubItem] {
        guard state.overflowStrategy != .continuousStream else { return [] }
        let allEvents = effectiveEvents(store: context.store)
        guard !allEvents.isEmpty else { return [] }

        let now = Date()
        let sortedEvents = allEvents.sorted { a, b in
            if a.isOngoing != b.isOngoing {
                return a.isOngoing && !b.isOngoing
            }
            if a.isImminent != b.isImminent {
                return a.isImminent && !b.isImminent
            }
            let aPast = a.endTime < now
            let bPast = b.endTime < now
            if aPast != bPast {
                return !aPast && bPast
            }
            return a.startTime < b.startTime
        }

        let maxLimit = (state.overflowStrategy == .smartFold) ? max(state.maxRailEvents, 2) : sortedEvents.count

        var visibleEvents: [CalendarEventItem]
        var remainingCount: Int = 0

        if state.overflowStrategy == .smartFold && sortedEvents.count > maxLimit {
            let primaryCount = maxLimit - 1
            visibleEvents = Array(sortedEvents.prefix(primaryCount))
            remainingCount = sortedEvents.count - primaryCount
        } else {
            visibleEvents = sortedEvents
        }

        var subItems = visibleEvents.map { event in
            let isPast = event.endTime < now
            let isOngoing = event.isOngoing
            let isImminent = event.isImminent
            let itemState: RailItemActivityState = isOngoing ? .ongoing : (isImminent ? .alerting : (isPast ? .inactive : .normal))
            return PurahPluginSubItem(
                id: event.id,
                title: event.title,
                subtitle: event.location,
                systemIcon: "calendar",
                badge: isOngoing ? "NOW" : (isImminent ? "SOON" : nil),
                state: itemState,
                gaugeRatio: nil,
                gaugeStyle: .none,
                tintColorHex: event.colorHex,
                isPinned: context.store.isItemPinned(id: event.id)
            )
        }

        if remainingCount > 0 {
            let isPinned = context.store.isItemPinned(id: "calendar_more_events")
            let moreTitle = String(format: "calendar.overview.moreEvents".localized, remainingCount)
            subItems.append(
                PurahPluginSubItem(
                    id: "calendar_more_events",
                    title: moreTitle,
                    subtitle: "calendar.overview.title".localized,
                    systemIcon: "ellipsis.circle.fill",
                    badge: "\(remainingCount)",
                    state: .normal,
                    gaugeRatio: nil,
                    gaugeStyle: .none,
                    tintColorHex: "#FF9F0A",
                    isPinned: isPinned
                )
            )
        }

        return subItems
    }

    public func makeSteppedDrawerView(subItemId: String, context: PurahPluginContext) -> AnyView? {
        if subItemId == "calendar_more_events" {
            let isPinned = context.store.isItemPinned(id: subItemId)
            let state: ItemDrawerState = (context.isExpanded || isPinned) ? .expandedDrawer : .dockedFlush
            return AnyView(
                CalendarAgendaOverviewDrawerView(
                    events: effectiveEvents(store: context.store),
                    edge: context.edge,
                    state: state,
                    isPinned: isPinned,
                    slotHeight: context.slotHeight,
                    store: context.store
                )
            )
        }

        let events = effectiveEvents(store: context.store)
        guard let event = events.first(where: { $0.id == subItemId }) else { return nil }
        let isPinned = context.store.isItemPinned(id: subItemId)
        let state: ItemDrawerState = (context.isExpanded || isPinned) ? .expandedDrawer : .dockedFlush
        return AnyView(
            CalendarItemDrawerView(
                event: event,
                allEvents: events,
                edge: context.edge,
                state: state,
                isPinned: isPinned,
                height: context.slotHeight,
                store: context.store,
                onTogglePin: {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.65)) {
                        context.store.togglePinItem(id: subItemId)
                    }
                }
            )
        )
    }
}

// MARK: - Todo Plugin
public struct TodoPlugin: PurahPodPlugin {
    public nonisolated let manifest = PurahPluginManifest(
        id: "todo",
        displayName: "Reminders & Todos",
        systemIcon: "checklist",
        author: "Project Purah",
        version: "0.1.0",
        description: "System reminders synchronization and quick task tracking",
        defaultEdge: .right,
        preferredZone: .goldenAction,
        ergonomicWeight: 40.0,
        minLengthRatio: 0.15,
        defaultColorHex: "#30D158",
        permissions: [.reminders]
    )

    public let state: TodoPluginState

    public init(state: TodoPluginState = TodoPluginState()) {
        self.state = state
    }

    public func makeRailBarView(context: PurahPluginContext) -> AnyView {
        let radius = min(context.railWidth / 2, 4)
        return AnyView(
            RoundedRectangle(cornerRadius: radius)
                .fill(context.accentColor.opacity(0.85))
                .frame(width: context.railWidth, height: context.slotHeight)
        )
    }

    public func makeDrawerView(context: PurahPluginContext) -> AnyView {
        AnyView(TodoDrawerView(state: state, store: context.store))
    }

    public func makeSettingsView(store: PurahWorkspaceStore) -> AnyView? {
        AnyView(TodoPluginSettingsView(state: state, store: store))
    }

    public func onMount(store: PurahWorkspaceStore) {
        state.mount(store: store)
        store.todoMaxRailTasks = state.maxRailTodos
    }

    public func onUnmount(store: PurahWorkspaceStore) {
        state.unmount(store: store)
    }

    public var supportedDrawerModes: Set<PurahDrawerMode> { [.stepped] }

    public func minimumDrawerHeight(store: PurahWorkspaceStore) -> CGFloat {
        let maxTasks = max(state.maxRailTodos, 1)
        let minChipH: CGFloat = 32.0
        let spacing: CGFloat = 2.5
        let totalSpacing = CGFloat(maxTasks - 1) * spacing
        return CGFloat(maxTasks) * minChipH + totalSpacing
    }

    private func effectiveTodos(store: PurahWorkspaceStore) -> [TodoItem] {
        var combined = state.todos
        for t in store._todos {
            if !combined.contains(where: { $0.id == t.id }) {
                combined.append(t)
            }
        }
        return combined
    }

    public func hasPinnedChild(store: PurahWorkspaceStore) -> Bool {
        effectiveTodos(store: store).contains { store.isItemPinned(id: $0.id) }
    }

    public func ownsSubItemId(_ itemId: String, store: PurahWorkspaceStore) -> Bool {
        effectiveTodos(store: store).contains { $0.id == itemId }
    }

    public var isDecomposed: Bool {
        true
    }

    public func isDecomposed(store: PurahWorkspaceStore) -> Bool {
        true
    }

    public var subItemCount: Int {
        let todos = !state.todos.isEmpty ? state.todos : []
        return min(todos.count, state.maxRailTodos)
    }

    public var subItemTitles: [String] {
        let todos = !state.todos.isEmpty ? state.todos : []
        return Array(todos.prefix(state.maxRailTodos)).map(\.title)
    }

    public func subItemCount(store: PurahWorkspaceStore) -> Int {
        min(effectiveTodos(store: store).count, store.todoMaxRailTasks)
    }

    public func subItemId(at index: Int, store: PurahWorkspaceStore) -> String? {
        let todos = effectiveTodos(store: store)
        guard index < store.todoMaxRailTasks, todos.indices.contains(index) else { return nil }
        return todos[index].id
    }

    public func subItemTitle(at index: Int, store: PurahWorkspaceStore) -> String? {
        let todos = effectiveTodos(store: store)
        guard index < store.todoMaxRailTasks, todos.indices.contains(index) else { return nil }
        return todos[index].title
    }

    public func steppedItems(context: PurahPluginContext) -> [PurahPluginSubItem] {
        let items = effectiveTodos(store: context.store)
        let maxTasks = max(context.store.todoMaxRailTasks, 1)
        let displayItems = items.prefix(maxTasks)
        return displayItems.map { todo in
            PurahPluginSubItem(
                id: todo.id,
                title: todo.title,
                subtitle: todo.listTitle,
                systemIcon: "checklist",
                badge: nil,
                state: todo.isCompleted ? .inactive : .normal,
                gaugeRatio: nil,
                gaugeStyle: .none,
                tintColorHex: todo.listColorHex,
                isPinned: context.store.isItemPinned(id: todo.id)
            )
        }
    }

    public func onRailBarTap(subItemId: String?, context: PurahPluginContext) {
        if let id = subItemId {
            context.performHaptic(.levelChange)
            Task {
                await state.toggleCompletion(id: id, store: context.store)
            }
        } else {
            context.requestExpand()
        }
    }

    public func makeSteppedDrawerView(subItemId: String, context: PurahPluginContext) -> AnyView? {
        let todos = effectiveTodos(store: context.store)
        guard let todo = todos.first(where: { $0.id == subItemId }) else { return nil }
        let isPinned = context.store.isItemPinned(id: subItemId)
        let state: ItemDrawerState = (context.isExpanded || isPinned) ? .expandedDrawer : .dockedFlush
        return AnyView(
            TodoItemDrawerView(
                todo: todo,
                edge: context.edge,
                state: state,
                isPinned: isPinned,
                height: context.slotHeight,
                store: context.store,
                onTogglePin: {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.65)) {
                        context.store.togglePinItem(id: subItemId)
                    }
                }
            )
        )
    }
}

// MARK: - Plugin Settings Views

public struct CalendarPluginSettingsView: View {
    public let state: CalendarPluginState
    public let store: PurahWorkspaceStore

    public init(state: CalendarPluginState, store: PurahWorkspaceStore = PurahWorkspaceStore()) {
        self.state = state
        self.store = store
    }

    public init(store: PurahWorkspaceStore) {
        let pluginState = (PluginRegistry.shared.plugin(for: "calendar") as? CalendarPlugin)?.state ?? CalendarPluginState()
        self.init(state: pluginState, store: store)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 0. Sample Calendar Notice (if not connected)
            if !state.isUsingRealCalendar || PermissionManager.shared.calendarStatus != .authorized {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.subheadline)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Currently Displaying Sample Calendar")
                            .font(.system(size: 11, weight: .bold))
                        Text("Connect Apple Calendar for live events")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Connect") {
                        Task {
                            let granted = await PermissionManager.shared.requestCalendarAccess()
                            if granted {
                                state.syncEvents(into: store)
                                SystemCalendarSyncService.shared.syncEvents(into: store)
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(8)
                .background(Color.orange.opacity(0.12))
                .cornerRadius(8)
            }

            // 1. Calendar Scope
            VStack(alignment: .leading, spacing: 4) {
                Text("Calendar Scope")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Picker("", selection: Binding(
                    get: { state.scope },
                    set: { newScope in
                        state.scope = newScope
                        state.save()
                        store.calendarScope = newScope
                        state.syncEvents(into: store)
                    }
                )) {
                    ForEach(CalendarTimeScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
            }

            Divider()
                .background(Color.primary.opacity(0.08))

            // 2. Overflow & Rail Density Strategy
            VStack(alignment: .leading, spacing: 6) {
                Text("Overflow Strategy & Density")
                    .font(.caption)
                    .foregroundColor(.secondary)

                PurahThemedSegmentedPicker(
                    options: CalendarOverflowStrategy.allCases,
                    selection: Binding(
                        get: { state.overflowStrategy },
                        set: { newStrategy in
                            withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                                state.overflowStrategy = newStrategy
                                state.save()
                            }
                        }
                    ),
                    titleForOption: { $0.displayName }
                )

                Text(state.overflowStrategy.subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if state.overflowStrategy == .smartFold {
                    PurahThemedSliderRow(
                        title: "Max Rail Events",
                        subtitle: "Primary events shown on bezel before folding into +N More capsule",
                        value: Binding(
                            get: { Double(state.maxRailEvents) },
                            set: {
                                state.maxRailEvents = Int($0)
                                state.save()
                                store.calendarMaxRailEvents = Int($0)
                                store.autoLayoutAll()
                            }
                        ),
                        range: 2...6,
                        step: 1,
                        valueBadgeText: "\(state.maxRailEvents) items"
                    )
                }
            }

            Divider()
                .background(Color.primary.opacity(0.08))

            // 3. Attention Alert Dynamics
            VStack(alignment: .leading, spacing: 6) {
                Text("Attention Alert Dynamic")
                    .font(.caption)
                    .foregroundColor(.secondary)

                PurahThemedSegmentedPicker(
                    options: PluginAlertStyle.allCases,
                    selection: Binding(
                        get: { state.alertStyle },
                        set: {
                            state.alertStyle = $0
                            state.isEventGlowAlertEnabled = ($0 != .off)
                            state.save()
                            store.alertStyle = $0
                            store.isEventGlowAlertEnabled = ($0 != .off)
                            store.savePersistentState()
                        }
                    ),
                    titleForOption: { $0.displayName }
                )

                Toggle("Dismiss dynamic animation on mouse hover", isOn: Binding(
                    get: { state.dismissAlertOnHover },
                    set: {
                        state.dismissAlertOnHover = $0
                        state.save()
                        store.dismissAlertOnHover = $0
                        store.savePersistentState()
                    }
                ))
                .font(.caption)

                Toggle("Show Toast notification when events start", isOn: Binding(
                    get: { state.isEventToastAlertEnabled },
                    set: {
                        state.isEventToastAlertEnabled = $0
                        state.save()
                        store.isEventToastAlertEnabled = $0
                        store.savePersistentState()
                    }
                ))
                .font(.caption)
            }
        }
    }
}

public struct TodoPluginSettingsView: View {
    public let state: TodoPluginState
    public let store: PurahWorkspaceStore

    public init(state: TodoPluginState, store: PurahWorkspaceStore = PurahWorkspaceStore()) {
        self.state = state
        self.store = store
    }

    public init(store: PurahWorkspaceStore) {
        let pluginState = (PluginRegistry.shared.plugin(for: "todo") as? TodoPlugin)?.state ?? TodoPluginState()
        self.init(state: pluginState, store: store)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Reminders Scope")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Picker("", selection: Binding(
                    get: { state.scope },
                    set: { newScope in
                        state.scope = newScope
                        state.save()
                        store.remindersScope = newScope
                        Task {
                            await state.syncReminders(into: store)
                        }
                    }
                )) {
                    ForEach(RemindersScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
            }

            PurahThemedSliderRow(
                title: "Max Visible Tasks on Rail",
                subtitle: "Primary tasks shown on bezel before folding into remainder",
                value: Binding(
                    get: { Double(state.maxRailTodos) },
                    set: {
                        state.maxRailTodos = Int($0)
                        state.save()
                        store.todoMaxRailTasks = Int($0)
                        store.autoLayoutAll()
                    }
                ),
                range: 2...10,
                step: 1,
                valueBadgeText: "\(state.maxRailTodos) tasks"
            )

            HStack {
                Text("Pending Tasks: \(state.todos.filter { !$0.isCompleted }.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Sync Reminders") {
                    Task {
                        await state.syncReminders(into: store)
                    }
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.medium))
                .foregroundColor(.accentColor)
            }
        }
    }
}

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

public struct VitalsPluginSettingsView: View {
    public let state: VitalsPluginState
    public let store: PurahWorkspaceStore

    public init(state: VitalsPluginState, store: PurahWorkspaceStore = PurahWorkspaceStore()) {
        self.state = state
        self.store = store
    }

    public init(store: PurahWorkspaceStore) {
        let pluginState = (PluginRegistry.shared.plugin(for: "vitals") as? HardwareVitalsPlugin)?.state ?? VitalsPluginState()
        self.init(state: pluginState, store: store)
    }

    public var body: some View {
        let vitals = state.metrics
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Decompose into Stepped Metric Rail Chips", isOn: Binding(
                get: { state.isDecomposed },
                set: {
                    state.isDecomposed = $0
                    state.save()
                    store._isVitalsDecomposed = $0
                    store.savePersistentState()
                }
            ))
            .font(.subheadline.weight(.semibold))

            Text("Splits hardware monitoring into individual rail chips (CPU, GPU, RAM, Power, Network, Disk) like Calendar and Todo.")
                .font(.caption)
                .foregroundColor(.secondary)

            if state.isDecomposed {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Visible Sub-Metrics")
                        .font(.caption.weight(.bold))

                    ForEach(VitalsMetricType.allCases) { metric in
                        let isIncluded = state.enabledMetrics.contains(metric)
                        Button {
                            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                                if isIncluded {
                                    if state.enabledMetrics.count > 1 {
                                        state.enabledMetrics.removeAll { $0 == metric }
                                    }
                                } else {
                                    state.enabledMetrics.append(metric)
                                }
                                state.save()
                                store._vitalsEnabledMetrics = state.enabledMetrics
                                store.savePersistentState()
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: isIncluded ? "checkmark.square.fill" : "square")
                                    .foregroundColor(isIncluded ? .accentColor : .secondary)
                                Image(systemName: metric.systemIcon)
                                    .font(.caption)
                                    .frame(width: 16)
                                Text(metric.displayName)
                                    .font(.caption)
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(8)
            }

            Divider()

            // Dynamic Usage Color Thresholds Customization Section
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Dynamic Usage Color Thresholds")
                        .font(.caption.weight(.bold))
                    Spacer()
                    Button("Reset Thresholds to Defaults") {
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                            state.resetThresholds()
                            store._vitalsThresholds = state.thresholds
                            store.savePersistentState()
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                // Visual 3-color legend/preview bar
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Color Progression (CPU Baseline)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("0% → \(Int(state.thresholds.cpuWarning * 100))% → \(Int(state.thresholds.cpuDanger * 100))% → 100%")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    GeometryReader { geo in
                        let totalWidth = geo.size.width
                        let warnRatio = max(min(CGFloat(state.thresholds.cpuWarning), 1.0), 0.0)
                        let dangerRatio = max(min(CGFloat(state.thresholds.cpuDanger), 1.0), warnRatio)
                        let wGreen = warnRatio * totalWidth
                        let wAmber = max((dangerRatio - warnRatio) * totalWidth, 0)
                        let wRed = max(totalWidth - wGreen - wAmber, 0)

                        HStack(spacing: 0) {
                            Rectangle()
                                .fill(VitalsColorResolver.healthyGreen)
                                .frame(width: wGreen)
                            Rectangle()
                                .fill(VitalsColorResolver.warningYellow)
                                .frame(width: wAmber)
                            Rectangle()
                                .fill(VitalsColorResolver.dangerRed)
                                .frame(width: wRed)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .frame(height: 10)

                    HStack {
                        HStack(spacing: 4) {
                            Circle().fill(VitalsColorResolver.healthyGreen).frame(width: 8, height: 8)
                            Text("Green (< \(Int(state.thresholds.cpuWarning * 100))%)")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        HStack(spacing: 4) {
                            Circle().fill(VitalsColorResolver.warningYellow).frame(width: 8, height: 8)
                            Text("Amber (\(Int(state.thresholds.cpuWarning * 100))% ~ \(Int(state.thresholds.cpuDanger * 100))%)")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        HStack(spacing: 4) {
                            Circle().fill(VitalsColorResolver.dangerRed).frame(width: 8, height: 8)
                            Text("Red (> \(Int(state.thresholds.cpuDanger * 100))%)")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(8)
                .background(Color.primary.opacity(0.03))
                .cornerRadius(6)

                // Sliders
                VStack(spacing: 8) {
                    // CPU Warning % (10% ~ 90%) & Danger % (50% ~ 99%)
                    thresholdRow(
                        title: "CPU Load",
                        warningLabel: "\(Int(state.thresholds.cpuWarning * 100))%",
                        warningValue: percentageBinding(for: \.cpuWarning, cappedBy: \.cpuDanger, isWarning: true),
                        warningRange: 10...90,
                        dangerLabel: "\(Int(state.thresholds.cpuDanger * 100))%",
                        dangerValue: percentageBinding(for: \.cpuDanger, cappedBy: \.cpuWarning, isWarning: false),
                        dangerRange: 50...99
                    )

                    // GPU Warning % (10% ~ 90%) & Danger % (50% ~ 99%)
                    thresholdRow(
                        title: "GPU Activity",
                        warningLabel: "\(Int(state.thresholds.gpuWarning * 100))%",
                        warningValue: percentageBinding(for: \.gpuWarning, cappedBy: \.gpuDanger, isWarning: true),
                        warningRange: 10...90,
                        dangerLabel: "\(Int(state.thresholds.gpuDanger * 100))%",
                        dangerValue: percentageBinding(for: \.gpuDanger, cappedBy: \.gpuWarning, isWarning: false),
                        dangerRange: 50...99
                    )

                    // RAM Warning % (20% ~ 90%) & Danger % (60% ~ 99%)
                    thresholdRow(
                        title: "Memory (RAM)",
                        warningLabel: "\(Int(state.thresholds.ramWarning * 100))%",
                        warningValue: percentageBinding(for: \.ramWarning, cappedBy: \.ramDanger, isWarning: true),
                        warningRange: 20...90,
                        dangerLabel: "\(Int(state.thresholds.ramDanger * 100))%",
                        dangerValue: percentageBinding(for: \.ramDanger, cappedBy: \.ramWarning, isWarning: false),
                        dangerRange: 60...99
                    )

                    // Battery Low Warning % (5% ~ 50%)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Battery Low Warning")
                                .font(.caption.weight(.medium))
                            Spacer()
                            Text("\(Int(state.thresholds.batteryLow * 100))%")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(VitalsColorResolver.warningYellow)
                        }

                        HStack(spacing: 8) {
                            Text("Level")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .frame(width: 32, alignment: .leading)
                            Slider(
                                value: Binding(
                                    get: { state.thresholds.batteryLow * 100.0 },
                                    set: {
                                        state.thresholds.batteryLow = $0 / 100.0
                                        state.save()
                                        store._vitalsThresholds.batteryLow = state.thresholds.batteryLow
                                        store.savePersistentState()
                                    }
                                ),
                                in: 5...50,
                                step: 1
                            )
                        }
                    }

                    // Network Warning MB/s (1 ~ 100 MB/s)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Network Throughput")
                                .font(.caption.weight(.medium))
                            Spacer()
                            Text("Warn: \(Int(state.thresholds.networkWarningMB)) MB/s")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(VitalsColorResolver.warningYellow)
                            Text("•")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Text("Danger: \(Int(state.thresholds.networkDangerMB)) MB/s")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(VitalsColorResolver.dangerRed)
                        }

                        HStack(spacing: 8) {
                            Text("Warn")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .frame(width: 32, alignment: .leading)
                            Slider(
                                value: Binding(
                                    get: { state.thresholds.networkWarningMB },
                                    set: {
                                        state.thresholds.networkWarningMB = min($0, state.thresholds.networkDangerMB - 1.0)
                                        state.save()
                                        store._vitalsThresholds.networkWarningMB = state.thresholds.networkWarningMB
                                        store.savePersistentState()
                                    }
                                ),
                                in: 1...100,
                                step: 1
                            )

                            Text("Danger")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .frame(width: 42, alignment: .leading)
                            Slider(
                                value: Binding(
                                    get: { state.thresholds.networkDangerMB },
                                    set: {
                                        state.thresholds.networkDangerMB = max($0, state.thresholds.networkWarningMB + 1.0)
                                        state.save()
                                        store._vitalsThresholds.networkDangerMB = state.thresholds.networkDangerMB
                                        store.savePersistentState()
                                    }
                                ),
                                in: 10...200,
                                step: 1
                            )
                        }
                    }
                }
                .padding(10)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(8)
            }

            Divider()

            HStack(spacing: 12) {
                Text("CPU: \(Int(vitals.cpuUsage * 100))%")
                    .font(.caption.monospaced())
                Text("RAM: \(Int(vitals.memoryUsage * 100))%")
                    .font(.caption.monospaced())
                Text("Disk: \(Int(vitals.diskFreeGB))GB Free")
                    .font(.caption.monospaced())
                Spacer()
                Button("Refresh") {
                    state.refreshMetrics(includeProcesses: true)
                }
                .buttonStyle(.tactile)
                .font(.caption.weight(.medium))
                .foregroundColor(.accentColor)
            }
            .foregroundColor(.secondary)
        }
    }

    private func percentageBinding(
        for keyPath: WritableKeyPath<VitalsColorThresholds, Double>,
        cappedBy limitKeyPath: KeyPath<VitalsColorThresholds, Double>,
        isWarning: Bool
    ) -> Binding<Double> {
        Binding(
            get: { state.thresholds[keyPath: keyPath] * 100.0 },
            set: { newVal in
                let val = newVal / 100.0
                let limit = state.thresholds[keyPath: limitKeyPath]
                state.thresholds[keyPath: keyPath] = isWarning ? min(val, limit - 0.05) : max(val, limit + 0.05)
                state.save()
                store._vitalsThresholds[keyPath: keyPath] = state.thresholds[keyPath: keyPath]
                store.savePersistentState()
            }
        )
    }

    @ViewBuilder
    private func thresholdRow(
        title: String,
        warningLabel: String,
        warningValue: Binding<Double>,
        warningRange: ClosedRange<Double>,
        dangerLabel: String,
        dangerValue: Binding<Double>,
        dangerRange: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption.weight(.medium))
                Spacer()
                Text("Warn: \(warningLabel)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(VitalsColorResolver.warningYellow)
                Text("•")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text("Danger: \(dangerLabel)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(VitalsColorResolver.dangerRed)
            }

            HStack(spacing: 8) {
                Text("Warn")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .frame(width: 32, alignment: .leading)
                Slider(value: warningValue, in: warningRange, step: 1)

                Text("Danger")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .frame(width: 42, alignment: .leading)
                Slider(value: dangerValue, in: dangerRange, step: 1)
            }
        }
    }
}

public struct ScriptsPluginSettingsView: View {
    public let state: ScriptsPluginState
    public let store: PurahWorkspaceStore
    private var runway: ScriptRunwayService { ScriptRunwayService.shared }

    @State private var newActionName: String = ""
    @State private var newCommandType: ScriptCommandType = .shortcut
    @State private var newScriptContent: String = ""
    @State private var newSystemIcon: String = "bolt.fill"
    @State private var newDescription: String = ""
    @State private var newShowNotification: Bool = true
    @State private var isAddingAction: Bool = false

    @State private var editingActionId: String? = nil
    @State private var editActionName: String = ""
    @State private var editCommandType: ScriptCommandType = .shortcut
    @State private var editScriptContent: String = ""
    @State private var editSystemIcon: String = "bolt.fill"
    @State private var editDescription: String = ""
    @State private var editShowNotification: Bool = true

    public init(state: ScriptsPluginState, store: PurahWorkspaceStore = PurahWorkspaceStore()) {
        self.state = state
        self.store = store
    }

    public init(store: PurahWorkspaceStore) {
        let pluginState = (PluginRegistry.shared.plugin(for: "scripts") as? ScriptRunwayPlugin)?.state ?? ScriptsPluginState()
        self.init(state: pluginState, store: store)
    }

    private var effectiveEnabledActionIds: [String] {
        if state.enabledActionIds.isEmpty {
            return state.actions.map(\.id)
        }
        return state.enabledActionIds
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Decompose into Stepped Script Rail Chips", isOn: Binding(
                get: { state.isDecomposed },
                set: {
                    state.isDecomposed = $0
                    state.save()
                    store._isScriptsDecomposed = $0
                    store.savePersistentState()
                }
            ))
            .font(.subheadline.weight(.semibold))

            Text("Splits script runway into individual interactive rail chips for rapid one-click execution.")
                .font(.caption)
                .foregroundColor(.secondary)

            if state.isDecomposed {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Visible Stepped Action Chips")
                        .font(.caption.weight(.bold))

                    let currentEnabled = effectiveEnabledActionIds

                    ForEach(state.actions) { action in
                        let isIncluded = currentEnabled.contains(action.id)
                        Button {
                            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                                var updated = currentEnabled
                                if isIncluded {
                                    if updated.count > 1 {
                                        updated.removeAll { $0 == action.id }
                                        state.enabledActionIds = updated
                                        state.save()
                                        store._scriptsEnabledActionIds = updated
                                        store.savePersistentState()
                                    }
                                } else {
                                    updated.append(action.id)
                                    state.enabledActionIds = updated
                                    state.save()
                                    store._scriptsEnabledActionIds = updated
                                    store.savePersistentState()
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: isIncluded ? "checkmark.square.fill" : "square")
                                    .foregroundColor(isIncluded ? .accentColor : .secondary)
                                Image(systemName: action.systemIcon)
                                    .font(.caption)
                                    .frame(width: 16)
                                Text(action.name)
                                    .font(.caption)
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(8)
            }

            Divider()

            HStack {
                Text("Actions & Shortcuts (\(state.actions.count))")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.8)) {
                        isAddingAction.toggle()
                        if isAddingAction {
                            editingActionId = nil
                        }
                    }
                } label: {
                    Label(isAddingAction ? "Cancel" : "Add Action", systemImage: isAddingAction ? "xmark" : "plus")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.tactile)

                Button("Reset Defaults") {
                    withAnimation {
                        state.resetToDefaults()
                        editingActionId = nil
                        store._scriptsEnabledActionIds = state.enabledActionIds
                        store.savePersistentState()
                    }
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundColor(.secondary)
            }

            if isAddingAction {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Add New Action or Shortcut")
                        .font(.caption.weight(.bold))

                    HStack(spacing: 8) {
                        TextField("Action Name (e.g. Meeting Mode)", text: $newActionName)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)

                        Picker("Type", selection: $newCommandType) {
                            Text("Shortcuts").tag(ScriptCommandType.shortcut)
                            Text("Shell (Zsh)").tag(ScriptCommandType.shell)
                            Text("AppleScript").tag(ScriptCommandType.appleScript)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 220)
                    }

                    TextField(newCommandType == .shortcut ? "macOS Shortcut Name (e.g. Do Not Disturb)" : "Command or Script", text: $newScriptContent)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption.monospaced())

                    HStack(spacing: 8) {
                        TextField("SF Symbol (e.g. bolt.fill, terminal.fill)", text: $newSystemIcon)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                            .frame(width: 200)

                        TextField("Short Description", text: $newDescription)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)

                        Toggle("Toast", isOn: $newShowNotification)
                            .font(.caption)
                            .help("Show HUD Toast notification upon script completion")

                        Spacer()

                        Button("Save") {
                            guard !newActionName.trimmingCharacters(in: .whitespaces).isEmpty,
                                  !newScriptContent.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                            let item = ScriptActionItem(
                                id: UUID().uuidString,
                                name: newActionName.trimmingCharacters(in: .whitespaces),
                                systemIcon: newSystemIcon.trimmingCharacters(in: .whitespaces).isEmpty ? "bolt.fill" : newSystemIcon.trimmingCharacters(in: .whitespaces),
                                commandType: newCommandType,
                                scriptContent: newScriptContent.trimmingCharacters(in: .whitespaces),
                                description: newDescription.trimmingCharacters(in: .whitespaces),
                                showNotification: newShowNotification
                            )
                            withAnimation {
                                state.addAction(item)
                                store._scriptsEnabledActionIds = state.enabledActionIds
                                store.savePersistentState()
                                newActionName = ""
                                newScriptContent = ""
                                newDescription = ""
                                newShowNotification = true
                                isAddingAction = false
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .font(.caption)
                        .disabled(newActionName.trimmingCharacters(in: .whitespaces).isEmpty || newScriptContent.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .padding(10)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(8)
            }

            VStack(spacing: 6) {
                ForEach(state.actions) { action in
                    VStack(spacing: 0) {
                        HStack(spacing: 8) {
                            Image(systemName: action.systemIcon)
                                .font(.caption)
                                .foregroundColor(.accentColor)
                                .frame(width: 16)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(action.name)
                                    .font(.caption.weight(.semibold))
                                Text(action.scriptContent)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Text(typeBadge(action.commandType))
                                .font(.system(size: 8, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.primary.opacity(0.08))
                                .cornerRadius(4)

                            Image(systemName: action.showNotification ? "bell.fill" : "bell.slash")
                                .font(.system(size: 9))
                                .foregroundColor(action.showNotification ? .secondary : .secondary.opacity(0.35))
                                .help(action.showNotification ? "Toast notification enabled" : "Silent execution (Toast disabled)")

                            Button {
                                withAnimation(.spring(response: 0.24, dampingFraction: 0.8)) {
                                    if editingActionId == action.id {
                                        editingActionId = nil
                                    } else {
                                        editingActionId = action.id
                                        editActionName = action.name
                                        editCommandType = action.commandType
                                        editScriptContent = action.scriptContent
                                        editSystemIcon = action.systemIcon
                                        editDescription = action.description
                                        editShowNotification = action.showNotification
                                        isAddingAction = false
                                    }
                                }
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.caption2)
                                    .foregroundColor(editingActionId == action.id ? .accentColor : .secondary)
                            }
                            .buttonStyle(.plain)

                            Button {
                                withAnimation {
                                    if editingActionId == action.id {
                                        editingActionId = nil
                                    }
                                    state.removeAction(id: action.id)
                                    store._scriptsEnabledActionIds = state.enabledActionIds
                                    store.savePersistentState()
                                }
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(8)

                        if editingActionId == action.id {
                            Divider()
                                .padding(.horizontal, 8)

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Edit Action")
                                    .font(.caption.weight(.bold))

                                HStack(spacing: 8) {
                                    TextField("Action Name", text: $editActionName)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.caption)

                                    Picker("Type", selection: $editCommandType) {
                                        Text("Shortcuts").tag(ScriptCommandType.shortcut)
                                        Text("Shell (Zsh)").tag(ScriptCommandType.shell)
                                        Text("AppleScript").tag(ScriptCommandType.appleScript)
                                    }
                                    .pickerStyle(.segmented)
                                    .frame(width: 220)
                                }

                                TextField(editCommandType == .shortcut ? "macOS Shortcut Name (e.g. Do Not Disturb)" : "Command or Script", text: $editScriptContent)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.caption.monospaced())

                                HStack(spacing: 8) {
                                    TextField("SF Symbol (e.g. bolt.fill)", text: $editSystemIcon)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.caption)
                                        .frame(width: 160)

                                    TextField("Description", text: $editDescription)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.caption)

                                    Toggle("Toast", isOn: $editShowNotification)
                                        .font(.caption)
                                        .help("Show HUD Toast notification upon script completion")
                                }

                                HStack {
                                    Spacer()

                                    Button("Cancel") {
                                        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                                            editingActionId = nil
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                    Button("Save Changes") {
                                        let trimmedName = editActionName.trimmingCharacters(in: .whitespaces)
                                        let trimmedContent = editScriptContent.trimmingCharacters(in: .whitespaces)
                                        guard !trimmedName.isEmpty, !trimmedContent.isEmpty else { return }

                                        let updated = ScriptActionItem(
                                            id: action.id,
                                            name: trimmedName,
                                            systemIcon: editSystemIcon.trimmingCharacters(in: .whitespaces).isEmpty ? "bolt.fill" : editSystemIcon.trimmingCharacters(in: .whitespaces),
                                            commandType: editCommandType,
                                            scriptContent: trimmedContent,
                                            description: editDescription.trimmingCharacters(in: .whitespaces),
                                            showNotification: editShowNotification
                                        )
                                        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                                            state.updateAction(updated)
                                            editingActionId = nil
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .font(.caption)
                                    .disabled(editActionName.trimmingCharacters(in: .whitespaces).isEmpty || editScriptContent.trimmingCharacters(in: .whitespaces).isEmpty)
                                }
                            }
                            .padding(10)
                            .background(Color.primary.opacity(0.02))
                        }
                    }
                    .background(Color.primary.opacity(0.03))
                    .cornerRadius(6)
                }
            }
        }
    }

    private func typeBadge(_ type: ScriptCommandType) -> String {
        switch type {
        case .shortcut: return "SHORTCUT"
        case .shell: return "SHELL"
        case .appleScript: return "APPLESCRIPT"
        }
    }
}

public struct ShelfPluginSettingsView: View {
    public let state: ShelfPluginState
    public let store: PurahWorkspaceStore

    public init(state: ShelfPluginState, store: PurahWorkspaceStore = PurahWorkspaceStore()) {
        self.state = state
        self.store = store
    }

    public init(store: PurahWorkspaceStore) {
        let pluginState = (PluginRegistry.shared.plugin(for: "shelf") as? DropShelfPlugin)?.state ?? ShelfPluginState()
        self.init(state: pluginState, store: store)
    }

    public var body: some View {
        HStack {
            Text("Stashed Files: \(state.files.count) item(s)")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            if !state.files.isEmpty {
                Button("Clear Shelf") {
                    state.clear()
                    store._shelfFiles.removeAll()
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.medium))
                .foregroundColor(.red)
            }
        }
    }
}

public struct NotesPluginSettingsView: View {
    public let state: NotesPluginState
    public let store: PurahWorkspaceStore

    public init(state: NotesPluginState, store: PurahWorkspaceStore = PurahWorkspaceStore()) {
        self.state = state
        self.store = store
    }

    public init(store: PurahWorkspaceStore) {
        let pluginState = (PluginRegistry.shared.plugin(for: "notes") as? QuickNotesPlugin)?.state ?? NotesPluginState()
        self.init(state: pluginState, store: store)
    }

    public var body: some View {
        HStack {
            Text("Scratchpad length: \(state.noteContent.text.count) character(s)")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Button("Clear Notes") {
                state.clear()
                store._quickNote.text = ""
                store._quickNote.lastModified = Date()
                store.savePersistentState()
            }
            .buttonStyle(.plain)
            .font(.caption.weight(.medium))
            .foregroundColor(.secondary)
        }
    }
}

// MARK: - Persistent Terminal Plugin
public struct TerminalPlugin: PurahPodPlugin {
    public nonisolated let manifest = PurahPluginManifest(
        id: "terminal",
        displayName: "Terminal",
        systemIcon: "apple.terminal.fill",
        author: "Project Purah",
        version: "0.1.0",
        description: "Persistent background terminal and command shell",
        defaultEdge: .left,
        preferredZone: .goldenAction,
        ergonomicWeight: 35.0,
        minLengthRatio: 0.20,
        defaultColorHex: "#00F5D4",
        defaultDrawerWidth: 520.0,
        permissions: [.shellExecution]
    )

    public let state: TerminalPluginState

    public init(state: TerminalPluginState = TerminalPluginState()) {
        self.state = state
    }

    public func makeRailBarView(context: PurahPluginContext) -> AnyView {
        AnyView(TerminalRailBarPluginView(context: context, state: state))
    }

    public func makeDrawerView(context: PurahPluginContext) -> AnyView {
        AnyView(PersistentTerminalDrawerView(state: state, store: context.store))
    }

    public func makeHeaderAccessoryView(context: PurahPluginContext) -> AnyView? {
        AnyView(TerminalHeaderAccessoryView(state: state, color: context.accentColor))
    }

    public func makeHeaderTrailingView(context: PurahPluginContext) -> AnyView? {
        AnyView(TerminalHeaderTrailingToolbarView(state: state))
    }

    public func makeSettingsView(store: PurahWorkspaceStore) -> AnyView? {
        AnyView(TerminalPluginSettingsView(state: state, store: store))
    }

    public func onMount(store: PurahWorkspaceStore) {
        state.mount(store: store)
    }

    public func onUnmount(store: PurahWorkspaceStore) {
        state.unmount(store: store)
    }

    public func minimumDrawerHeight(store: PurahWorkspaceStore) -> CGFloat {
        60.0
    }

    public func adaptiveDrawerWidth(store: PurahWorkspaceStore) -> CGFloat? {
        520.0
    }

    public func onRailBarTap(subItemId: String?, context: PurahPluginContext) {
        context.performHaptic(.alignment)
        context.requestExpand()
    }
}

public struct TerminalRailBarPluginView: View {
    public let context: PurahPluginContext
    public let state: TerminalPluginState
    private var manager: TerminalManager {
        TerminalManager.shared
    }

    public init(context: PurahPluginContext, state: TerminalPluginState? = nil) {
        self.context = context
        self.state = state ?? (PluginRegistry.shared.plugin(for: "terminal") as? TerminalPlugin)?.state ?? TerminalPluginState()
    }

    public var body: some View {
        let radius = min(context.railWidth / 2, 4)
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: radius)
                .fill(context.accentColor.opacity(0.85))
                .frame(width: context.railWidth, height: context.slotHeight)

            if state.isProcessRunning {
                Circle()
                    .fill(Color.green)
                    .frame(width: min(context.railWidth - 2, 4), height: min(context.railWidth - 2, 4))
                    .padding(.bottom, 4)
            }
        }
        .frame(width: context.railWidth, height: context.slotHeight)
    }
}

public struct TerminalPluginSettingsView: View {
    public let state: TerminalPluginState
    public let store: PurahWorkspaceStore
    private var manager: TerminalManager {
        TerminalManager.shared
    }

    private var availableFonts: [String] {
        TerminalFontManager.availableFamilies()
    }

    public init(state: TerminalPluginState, store: PurahWorkspaceStore = PurahWorkspaceStore()) {
        self.state = state
        self.store = store
    }

    public init(store: PurahWorkspaceStore) {
        let pluginState = (PluginRegistry.shared.plugin(for: "terminal") as? TerminalPlugin)?.state ?? TerminalPluginState()
        self.init(state: pluginState, store: store)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Persistent Terminal Settings")
                .font(.headline)

            // Font Settings Group
            VStack(alignment: .leading, spacing: 8) {
                Text("Font Family & Starship Nerd Font")
                    .font(.caption.weight(.bold))

                Picker("Font", selection: Binding(
                    get: { state.fontFamily },
                    set: {
                        state.fontFamily = $0
                        state.save()
                        store._terminalFontFamily = $0
                        store.savePersistentState()
                    }
                )) {
                    ForEach(availableFonts, id: \.self) { fontName in
                        Text(fontName).tag(fontName)
                    }
                }
                .pickerStyle(.menu)

                Text("Starship icons automatically cascade to Symbols Nerd Font / Maple Mono NF.")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)

                HStack {
                    Text("Font Size: \(String(format: "%.1f", state.fontSize))pt")
                        .font(.caption)
                    Spacer()
                }

                Slider(value: Binding(
                    get: { state.fontSize },
                    set: {
                        state.fontSize = $0
                        state.save()
                        store._terminalFontSize = $0
                        store.savePersistentState()
                    }
                ), in: 9.0...20.0, step: 0.5)
            }
            .padding(10)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(8)

            // Shell & Session State Group
            VStack(alignment: .leading, spacing: 6) {
                Text("Shell Binary")
                    .font(.caption.weight(.bold))
                Text(state.shellName.uppercased())
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)

                HStack(spacing: 6) {
                    Circle()
                        .fill(state.isProcessRunning ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(state.isProcessRunning ? "Active & Running in Background (Metal GPU Rendered)" : "Exited")
                        .font(.caption)
                }
            }
            .padding(10)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(8)

            HStack(spacing: 10) {
                Button("Restart Shell") {
                    state.restartShell(palette: ThemePalette.palette(for: .native))
                }
                .buttonStyle(.bordered)

                Button("Clear Output Buffer") {
                    state.clearScreen()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
    }
}

// MARK: - Clipboard Sidecar Plugin
public struct ClipboardPlugin: PurahPodPlugin {
    public nonisolated let manifest = PurahPluginManifest(
        id: "clipboard",
        displayName: "Clipboard",
        systemIcon: "doc.on.clipboard.fill",
        author: "Project Purah",
        version: "0.1.0",
        description: "Zero-memory transient clipboard history, color specialist & disk cache",
        defaultEdge: .left,
        preferredZone: .goldenAction,
        ergonomicWeight: 30.0,
        minLengthRatio: 0.16,
        defaultColorHex: "#FF9F0A",
        defaultDrawerWidth: 260.0,
        category: .lightweight,
        permissions: [.pasteboard, .fileSystem]
    )

    public let state: ClipboardPluginState

    public init(state: ClipboardPluginState = ClipboardPluginState()) {
        self.state = state
    }

    public func onMount(store: PurahWorkspaceStore) {
        state.mount(store: store)
    }

    public func onUnmount(store: PurahWorkspaceStore) {
        state.unmount(store: store)
    }

    public func dynamicBarColor(context: PurahPluginContext) -> Color? {
        if let latestColor = state.items.first?.type.colorHex {
            return Color(hex: latestColor)
        }
        return nil
    }

    // 1. In-rail view: Pure physical geometric pill shape without any distracting icons
    public func makeRailBarView(context: PurahPluginContext) -> AnyView {
        let activeColor = dynamicBarColor(context: context) ?? context.accentColor
        return AnyView(
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
                .frame(width: context.railWidth, height: context.slotHeight)
                .contentShape(Rectangle())
        )
    }

    // 2. Capability Provider: Decomposed Mode
    public var podId: String { "clipboard" }
    public var supportedDrawerModes: Set<PurahDrawerMode> { [.composite, .stepped] }
    public var isDecomposed: Bool { state.isDecomposed }
    public func isDecomposed(store: PurahWorkspaceStore) -> Bool { state.isDecomposed }
    public func subItemCount(store: PurahWorkspaceStore) -> Int { max(min(state.items.count, store.clipboardMaxRailItems), 1) }
    public func subItemId(at index: Int, store: PurahWorkspaceStore) -> String? {
        if state.items.isEmpty { return "clipboard-empty" }
        guard index >= 0 && index < state.items.count else { return nil }
        return "clipboard-\(state.items[index].id)"
    }
    public func subItemTitle(at index: Int, store: PurahWorkspaceStore) -> String? {
        if state.items.isEmpty { return "Clipboard Empty" }
        guard index >= 0 && index < state.items.count else { return nil }
        return state.items[index].type.summary
    }
    public func ownsSubItemId(_ itemId: String, store: PurahWorkspaceStore) -> Bool {
        itemId.hasPrefix("clipboard-") || itemId == "clipboard"
    }
    public func minimumDrawerHeight(store: PurahWorkspaceStore) -> CGFloat {
        if isDecomposed(store: store) {
            let count = max(min(state.items.count, store.clipboardMaxRailItems), 1)
            return CGFloat(count) * 42.0 + CGFloat(count - 1) * 2.5
        } else {
            return 160.0
        }
    }
    public func adaptiveDrawerWidth(store: PurahWorkspaceStore) -> CGFloat? { 380.0 }
    public func hasPinnedChild(store: PurahWorkspaceStore) -> Bool {
        store.pinnedDrawerItemIds.contains { $0.hasPrefix("clipboard-") }
    }

    // 3. Header Accessory & Trailing Tools (Directly integrated into Card Header Row 1)
    public func makeHeaderAccessoryView(context: PurahPluginContext) -> AnyView? {
        AnyView(
            Text("\(state.items.count)")
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .foregroundColor(Color(hex: "#FF9F0A"))
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(Color(hex: "#FF9F0A").opacity(0.18))
                .cornerRadius(4)
        )
    }

    public func makeHeaderTrailingView(context: PurahPluginContext) -> AnyView? {
        if !state.items.isEmpty {
            return AnyView(
                Button(role: .destructive) {
                    state.clearAll()
                    context.performHaptic(.alignment)
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "trash")
                            .font(.system(size: 9.5))
                        Text("Clear")
                            .font(.system(size: 9.5, weight: .medium))
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.tactile)
                .help("Clear Clipboard History")
            )
        }
        return nil
    }

    // 4. Stepped Items for SteppedRailContainerView
    public func steppedItems(context: PurahPluginContext) -> [PurahPluginSubItem] {
        let maxItems = context.store.clipboardMaxRailItems
        if state.items.isEmpty {
            return [
                PurahPluginSubItem(
                    id: "clipboard-empty",
                    title: "Clipboard Empty",
                    systemIcon: "doc.on.clipboard",
                    state: .normal,
                    gaugeRatio: nil,
                    gaugeStyle: .solid,
                    tintColorHex: nil,
                    isPinned: context.store.isItemPinned(id: "clipboard-empty")
                )
            ]
        }
        return state.items.prefix(maxItems).map { item in
            let subId = "clipboard-\(item.id)"
            let icon: String = {
                switch item.type {
                case .color: return "paintpalette.fill"
                case .image: return "photo.fill"
                case .text: return "doc.text.fill"
                }
            }()
            let colorHex: String? = {
                if case .color(let hex, _, _, _, _) = item.type {
                    return hex
                }
                return nil
            }()
            return PurahPluginSubItem(
                id: subId,
                title: item.type.summary,
                systemIcon: icon,
                state: .normal,
                gaugeRatio: nil,
                gaugeStyle: .solid,
                tintColorHex: colorHex,
                isPinned: context.store.isItemPinned(id: subId)
            )
        }
    }

    // 5. Stepped Drawer View (Single item popout with co-planar rail indicator and physical divider)
    public func makeSteppedDrawerView(subItemId: String, context: PurahPluginContext) -> AnyView? {
        let cleanId = subItemId.replacingOccurrences(of: "clipboard-", with: "")
        let item = state.items.first(where: { $0.id == cleanId || $0.id == subItemId })
        let isPinned = context.store.isItemPinned(id: subItemId)
        let drawerState: ItemDrawerState = (context.isExpanded || isPinned) ? .expandedDrawer : .dockedFlush

        return AnyView(
            ClipboardItemDrawerView(
                item: item,
                subItemId: subItemId,
                edge: context.edge,
                state: drawerState,
                isPinned: isPinned,
                height: context.slotHeight,
                pluginState: self.state,
                store: context.store,
                onTogglePin: {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.65)) {
                        context.store.togglePinItem(id: subItemId)
                    }
                }
            )
        )
    }

    // 6. Full Drawer View (Composite)
    public func makeDrawerView(context: PurahPluginContext) -> AnyView {
        AnyView(
            ClipboardFullDrawerView(state: state, context: context)
        )
    }

    // 7. Settings View
    public func makeSettingsView(store: PurahWorkspaceStore) -> AnyView? {
        AnyView(
            ClipboardPluginSettingsView(state: state, store: store)
        )
    }
}

// MARK: - Clipboard Stepped Item Drawer View
public struct ClipboardItemDrawerView: View {
    public let item: ClipboardItem?
    public let subItemId: String
    public let edge: MountEdge
    public let state: ItemDrawerState
    public let isPinned: Bool
    public let height: CGFloat
    public let pluginState: ClipboardPluginState
    public let store: PurahWorkspaceStore
    public let onTogglePin: () -> Void

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    private var drawerShape: UnevenRoundedRectangle {
        if edge == .right {
            return UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 10, bottomTrailingRadius: 0, topTrailingRadius: 0, style: .continuous)
        } else {
            return UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: 10, topTrailingRadius: 10, style: .continuous)
        }
    }

    private var itemDrawerTransition: AnyTransition {
        let edgeDirection: Edge = (edge == .right) ? .trailing : .leading
        return .asymmetric(
            insertion: .move(edge: edgeDirection),
            removal: .move(edge: edgeDirection)
        )
    }

    public var body: some View {
        let isExpanded = (state == .expandedDrawer)
        let cardH = max(height, 44.0)
        let itemColor: Color = {
            if let item = item, case .color(let hex, _, _, _, _) = item.type {
                return Color(hex: hex)
            }
            return Color(hex: "#FF9F0A")
        }()
        let barW = CGFloat(store.railBarWidth)

        ZStack(alignment: edge == .right ? .topTrailing : .topLeading) {
            // Pure physical in-rail capsule (co-planar, NO icons)
            Capsule()
                .fill(itemColor.opacity(isExpanded ? 0.95 : 0.70))
                .frame(width: barW, height: isExpanded ? cardH : height)

            if isExpanded {
                steppedCard(cardH: cardH, itemColor: itemColor)
                    .transition(itemDrawerTransition)
            }
        }
        .frame(height: isExpanded ? cardH : height)
        .animation(.spring(response: 0.30, dampingFraction: 0.80), value: state)
    }

    @ViewBuilder
    private func steppedCard(cardH: CGFloat, itemColor: Color) -> some View {
        HStack(spacing: 10) {
            if let item = item {
                switch item.type {
                case .color(let hex, _, _, _, _):
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(hex: hex))
                        .frame(width: 32, height: 32)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.white.opacity(0.25), lineWidth: 1)
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hex.uppercased())
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(palette.style == .native ? .primary : .white)
                        Text("Click to copy Hex • Drag into editor")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }

                case .image(let path, let thumbPath, let w, let h, _):
                    if let nsImg = NSImage(contentsOfFile: thumbPath) ?? NSImage(contentsOfFile: path) {
                        let _ = { nsImg.cacheMode = .never }()
                        Image(nsImage: nsImg)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 32, height: 32)
                            .cornerRadius(6)
                            .clipped()
                    } else {
                        Image(systemName: "photo")
                            .font(.system(size: 14))
                            .frame(width: 32, height: 32)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(6)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Image (\(w)×\(h))")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(palette.style == .native ? .primary : .white)
                        Text("Click to copy • Drag file out")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }

                case .text(let text):
                    VStack(alignment: .leading, spacing: 2) {
                        Text(text.prefix(70))
                            .font(.system(size: 11, design: .monospaced))
                            .lineLimit(2)
                            .foregroundColor(palette.style == .native ? .primary : .white)
                        Text("\(text.count) characters • Click to copy")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                Text("Clipboard is Empty")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if let item = item {
                Button {
                    pluginState.copyItem(item)
                    NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
                    withAnimation(.spring(response: 0.20, dampingFraction: 0.92)) {
                        store.activeDrawerItemId = nil
                    }
                } label: {
                    Image(systemName: "doc.on.doc.fill")
                        .font(.system(size: 11))
                        .foregroundColor(palette.style == .native ? .primary : .white)
                }
                .buttonStyle(.tactile)
                .help("Copy to Clipboard")
            }

            PurahPinButton(isPinned: isPinned, tintColor: itemColor) {
                onTogglePin()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(width: 290, height: max(cardH, 44.0))
        .liquidDrawerBackground(
            shape: drawerShape,
            accentColor: itemColor
        )
        .onDrag {
            if let item = item {
                return makeDragProvider(for: item)
            }
            return NSItemProvider()
        }
        .onTapGesture {
            if let item = item {
                pluginState.copyItem(item)
                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
                withAnimation(.spring(response: 0.20, dampingFraction: 0.92)) {
                    store.activeDrawerItemId = nil
                }
            }
        }
        .onHover { isHovering in
            if let item = item {
                if isHovering {
                    ClipboardHoverPreviewController.shared.show(
                        item: item,
                        edge: edge,
                        palette: palette,
                        drawerWidth: 290.0
                    )
                } else {
                    ClipboardHoverPreviewController.shared.hide()
                }
            }
        }
        .onDisappear {
            ClipboardHoverPreviewController.shared.hide()
        }
    }

    private func makeDragProvider(for item: ClipboardItem) -> NSItemProvider {
        switch item.type {
        case .text(let text):
            return NSItemProvider(object: text as NSString)
        case .color(let hex, _, _, _, _):
            return NSItemProvider(object: hex as NSString)
        case .image(let path, _, _, _, _):
            return NSItemProvider(contentsOf: URL(fileURLWithPath: path)) ?? NSItemProvider()
        }
    }
}

// MARK: - Clipboard Full Drawer View (Polished Apple Design)
public struct ClipboardFullDrawerView: View {
    public let state: ClipboardPluginState
    public let context: PurahPluginContext
    @State private var hoveredItemId: String? = nil

    private var palette: ThemePalette {
        context.palette
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if state.items.isEmpty {
                VStack(spacing: 10) {
                    Spacer()

                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 32, weight: .regular))
                        .foregroundColor(Color(hex: "#FF9F0A"))

                    Text("No clipping yet")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(palette.style == .native ? Color.primary : .white)

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 8) {
                        ForEach(state.items) { item in
                            clipboardCard(item: item)
                        }
                    }
                    .padding(.vertical, 2)
                    .padding(.trailing, 2)
                }
                .onDisappear {
                    ClipboardHoverPreviewController.shared.hide()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func clipboardCard(item: ClipboardItem) -> some View {
        let isHovered = (hoveredItemId == item.id)

        VStack(alignment: .leading, spacing: 8) {
            switch item.type {
            case .color(let hex, let r, let g, let b, let a):
                HStack(spacing: 12) {
                    // Tactile glass swatch
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(hex: hex))
                        .frame(width: 42, height: 42)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(0.35), lineWidth: 1)
                        )
                        .shadow(color: Color(hex: hex).opacity(0.35), radius: 3, x: 0, y: 1.5)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(hex.uppercased())
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundColor(palette.style == .native ? .primary : .white)

                            Text("COLOR")
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color(hex: hex).opacity(0.2))
                                .foregroundColor(Color(hex: hex))
                                .cornerRadius(3)
                        }

                        Text("RGB(\(Int(r * 255)), \(Int(g * 255)), \(Int(b * 255)))" + (a < 0.999 ? " • \(Int(a * 100))%" : ""))
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // Quick Action Buttons
                    HStack(spacing: 6) {
                        Button {
                            state.copyItem(item)
                            context.performHaptic(.levelChange)
                            context.showToast("Copied Hex", nil)
                            context.requestDismiss()
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "number")
                                    .font(.system(size: 8.5))
                                Text("Hex")
                                    .font(.system(size: 9.5, weight: .semibold))
                            }
                        }
                        .buttonStyle(.tactile)

                        if let snippet = item.swiftUIColorSnippet {
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(snippet, forType: .string)
                                context.performHaptic(.levelChange)
                                context.showToast("Copied SwiftUI Code", nil)
                                context.requestDismiss()
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: "swift")
                                        .font(.system(size: 8.5))
                                    Text("SwiftUI")
                                        .font(.system(size: 9.5, weight: .semibold))
                                }
                            }
                            .buttonStyle(.tactile)
                            .help("Copy as \(snippet)")
                        }
                    }
                }

            case .image(let path, let thumbPath, let w, let h, let bytes):
                HStack(spacing: 12) {
                    if let nsImg = NSImage(contentsOfFile: thumbPath) ?? NSImage(contentsOfFile: path) {
                        let _ = { nsImg.cacheMode = .never }()
                        Image(nsImage: nsImg)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 46, height: 46)
                            .cornerRadius(8)
                            .clipped()
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                    } else {
                        Image(systemName: "photo")
                            .font(.title3)
                            .frame(width: 46, height: 46)
                            .background(Color.secondary.opacity(0.12))
                            .cornerRadius(8)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("Image Clip")
                                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                                .foregroundColor(palette.style == .native ? .primary : .white)

                            Text("PNG")
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.blue.opacity(0.15))
                                .foregroundColor(.blue)
                                .cornerRadius(3)
                        }

                        Text("\(w) × \(h) px • \(max(bytes / 1024, 1)) KB")
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundColor(.secondary)

                        Text("Hover for detached Quick Look • Drag to export")
                            .font(.system(size: 8.5))
                            .foregroundColor(isHovered ? palette.primaryAccent : .secondary.opacity(0.8))
                    }

                    Spacer()

                    Image(systemName: isHovered ? "eye.fill" : "arrow.up.and.down.and.arrow.left.and.right")
                        .font(.system(size: 11))
                        .foregroundColor(isHovered ? palette.primaryAccent : .secondary.opacity(0.6))
                }

            case .text(let text):
                VStack(alignment: .leading, spacing: 5) {
                    Text(text)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(3)
                        .lineSpacing(2)
                        .foregroundColor(palette.style == .native ? .primary : .white)

                    HStack {
                        Text("\(text.count) chars")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)

                        let lines = text.split(separator: "\n").count
                        if lines > 1 {
                            Text("• \(lines) lines")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Text(isHovered ? "Hover for full text • Tap to copy" : "Click to copy • Drag snippet")
                            .font(.system(size: 8.5))
                            .foregroundColor(isHovered ? palette.primaryAccent : .secondary.opacity(0.7))
                    }
                }
            }
        }
        .padding(10)
        .background(isHovered ? Color.secondary.opacity(0.14) : Color.secondary.opacity(0.08))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isHovered ? palette.primaryAccent.opacity(0.5) : palette.borderColor.opacity(0.25), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { isHovering in
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                if isHovering {
                    hoveredItemId = item.id
                    ClipboardHoverPreviewController.shared.show(
                        item: item,
                        edge: context.edge,
                        palette: palette,
                        drawerWidth: context.drawerWidth
                    )
                } else if hoveredItemId == item.id {
                    hoveredItemId = nil
                    ClipboardHoverPreviewController.shared.hide()
                }
            }
        }
        .onDrag {
            makeDragProvider(for: item)
        }
        .onTapGesture {
            state.copyItem(item)
            context.performHaptic(.levelChange)
            context.showToast("Copied to Clipboard", nil)
            context.requestDismiss()
        }
        .contextMenu {
            Button("Copy to Clipboard") {
                state.copyItem(item)
                context.showToast("Copied to Clipboard", nil)
            }
            if let snippet = item.swiftUIColorSnippet {
                Button("Copy as SwiftUI Code (\(snippet))") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(snippet, forType: .string)
                    context.showToast("Copied SwiftUI Code", nil)
                }
            }
            Divider()
            Button(role: .destructive) {
                state.deleteItem(id: item.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func makeDragProvider(for item: ClipboardItem) -> NSItemProvider {
        switch item.type {
        case .text(let text):
            return NSItemProvider(object: text as NSString)
        case .color(let hex, _, _, _, _):
            return NSItemProvider(object: hex as NSString)
        case .image(let path, _, _, _, _):
            return NSItemProvider(contentsOf: URL(fileURLWithPath: path)) ?? NSItemProvider()
        }
    }
}

// MARK: - Clipboard Plugin Settings View (100% English)
public struct ClipboardPluginSettingsView: View {
    public let state: ClipboardPluginState
    public let store: PurahWorkspaceStore

    public init(state: ClipboardPluginState, store: PurahWorkspaceStore = PurahWorkspaceStore()) {
        self.state = state
        self.store = store
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Clipboard Sidecar Settings")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Decomposed Rail Chips", isOn: Binding(
                    get: { state.isDecomposed },
                    set: {
                        state.isDecomposed = $0
                        state.save()
                    }
                ))
                .toggleStyle(.switch)
                Text("When enabled, recent items are displayed as discrete physical chips along the rail edge for zero-drawer switching.")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Divider()
                    .opacity(0.3)
                    .padding(.vertical, 2)

                HStack {
                    Text("Max In-Rail Items")
                        .font(.subheadline)
                    Spacer()
                    Text("\(store.clipboardMaxRailItems) Chips")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: "#FF9F0A"))
                }

                Slider(value: Binding(
                    get: { Double(store.clipboardMaxRailItems) },
                    set: {
                        store.clipboardMaxRailItems = Int($0)
                        store.savePersistentState()
                    }
                ), in: 2...8, step: 1)

                Text("Controls the maximum number of recent copied items decomposed into tactile chips along the screen edge.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(10)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(8)

            VStack(alignment: .leading, spacing: 8) {
                Text("Permanent Disk Storage")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("Clipboard history is persistently preserved in Application Support with 100px tiny downsampled thumbnails. In-memory footprint is strictly bounded to the active in-rail items.")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                HStack {
                    Text("Disk Usage:")
                        .font(.caption)
                    Text(SystemClipboardSyncService.shared.diskUsageFormatted)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: "#FF9F0A"))
                    Spacer()
                    Button("Open in Finder") {
                        SystemClipboardSyncService.shared.openStorageInFinder()
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)

                    Button("Clear All", role: .destructive) {
                        state.clearAll()
                        SystemClipboardSyncService.shared.clearDiskStorage()
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)
                }
                .padding(.top, 4)
            }
            .padding(10)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(8)
        }
        .padding()
    }
}
