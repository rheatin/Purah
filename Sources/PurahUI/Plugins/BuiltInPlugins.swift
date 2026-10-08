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
        version: "1.0.0",
        description: "Real-time hardware performance, memory, and power monitoring",
        defaultEdge: .left,
        preferredZone: .glance,
        ergonomicWeight: 35.0,
        minLengthRatio: 0.22,
        defaultColorHex: "#00E5A3"
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
        let isDecomp = state.isDecomposed || store.isVitalsDecomposed
        if isDecomp {
            let metrics = !store.vitalsEnabledMetrics.isEmpty ? store.vitalsEnabledMetrics : state.enabledMetrics
            let count = max(metrics.count, 1)
            return CGFloat(count) * 56.0 + CGFloat(count - 1) * 2.5
        }
        return 300.0
    }

    public func hasPinnedChild(store: PurahWorkspaceStore) -> Bool {
        let metrics = !store.vitalsEnabledMetrics.isEmpty ? store.vitalsEnabledMetrics : state.enabledMetrics
        return metrics.contains { store.isItemPinned(id: "vitals-\($0.rawValue)") }
    }

    public func ownsSubItemId(_ itemId: String, store: PurahWorkspaceStore) -> Bool {
        itemId.hasPrefix("vitals-")
    }

    public var isDecomposed: Bool {
        state.isDecomposed
    }

    public func isDecomposed(store: PurahWorkspaceStore) -> Bool {
        state.isDecomposed || store.isVitalsDecomposed
    }

    public var subItemCount: Int {
        state.isDecomposed ? state.enabledMetrics.count : 0
    }

    public var subItemTitles: [String] {
        state.isDecomposed ? state.enabledMetrics.map(\.displayName) : []
    }

    public func subItemCount(store: PurahWorkspaceStore) -> Int {
        let isDecomp = state.isDecomposed || store.isVitalsDecomposed
        guard isDecomp else { return 0 }
        let metrics = !store.vitalsEnabledMetrics.isEmpty ? store.vitalsEnabledMetrics : state.enabledMetrics
        return metrics.count
    }

    public func subItemId(at index: Int, store: PurahWorkspaceStore) -> String? {
        let isDecomp = state.isDecomposed || store.isVitalsDecomposed
        guard isDecomp else { return nil }
        let metrics = !store.vitalsEnabledMetrics.isEmpty ? store.vitalsEnabledMetrics : state.enabledMetrics
        guard metrics.indices.contains(index) else { return nil }
        return "vitals-\(metrics[index].rawValue)"
    }

    public func subItemTitle(at index: Int, store: PurahWorkspaceStore) -> String? {
        let isDecomp = state.isDecomposed || store.isVitalsDecomposed
        guard isDecomp else { return nil }
        let metrics = !store.vitalsEnabledMetrics.isEmpty ? store.vitalsEnabledMetrics : state.enabledMetrics
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
        version: "1.0.0",
        description: "Quick-fire terminal commands and automation runway",
        defaultEdge: .left,
        preferredZone: .quickFlick,
        ergonomicWeight: 30.0,
        minLengthRatio: 0.18,
        defaultColorHex: "#A78BFA"
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
        let isDecomp = state.isDecomposed || store.isScriptsDecomposed
        if isDecomp {
            let actions = !store.scriptsEnabledActionIds.isEmpty ? store.scriptsEnabledActions : state.enabledActions
            let count = max(actions.count, 1)
            return CGFloat(count) * 56.0 + CGFloat(count - 1) * 2.5
        }
        return 160.0
    }

    public func hasPinnedChild(store: PurahWorkspaceStore) -> Bool {
        let actions = !store.scriptsEnabledActionIds.isEmpty ? store.scriptsEnabledActions : state.enabledActions
        return actions.contains { store.isItemPinned(id: "scripts-\($0.id)") }
    }

    public func ownsSubItemId(_ itemId: String, store: PurahWorkspaceStore) -> Bool {
        itemId.hasPrefix("scripts-")
    }

    public var isDecomposed: Bool {
        state.isDecomposed
    }

    public func isDecomposed(store: PurahWorkspaceStore) -> Bool {
        state.isDecomposed || store.isScriptsDecomposed
    }

    public var subItemCount: Int {
        state.isDecomposed ? state.enabledActions.count : 0
    }

    public var subItemTitles: [String] {
        state.isDecomposed ? state.enabledActions.map(\.name) : []
    }

    public func subItemCount(store: PurahWorkspaceStore) -> Int {
        let isDecomp = state.isDecomposed || store.isScriptsDecomposed
        guard isDecomp else { return 0 }
        let actions = !store.scriptsEnabledActionIds.isEmpty ? store.scriptsEnabledActions : state.enabledActions
        return actions.count
    }

    public func subItemId(at index: Int, store: PurahWorkspaceStore) -> String? {
        let isDecomp = state.isDecomposed || store.isScriptsDecomposed
        guard isDecomp else { return nil }
        let actions = !store.scriptsEnabledActionIds.isEmpty ? store.scriptsEnabledActions : state.enabledActions
        guard actions.indices.contains(index) else { return nil }
        return "scripts-\(actions[index].id)"
    }

    public func subItemTitle(at index: Int, store: PurahWorkspaceStore) -> String? {
        let isDecomp = state.isDecomposed || store.isScriptsDecomposed
        guard isDecomp else { return nil }
        let actions = !store.scriptsEnabledActionIds.isEmpty ? store.scriptsEnabledActions : state.enabledActions
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
        version: "1.0.0",
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
}

// MARK: - Drop Shelf Plugin
public struct DropShelfPlugin: PurahPodPlugin {
    public nonisolated let manifest = PurahPluginManifest(
        id: "shelf",
        displayName: "Drop Shelf",
        systemIcon: "tray.and.arrow.down.fill",
        author: "Project Purah",
        version: "1.0.0",
        description: "Transient holding area for dragged files and assets",
        defaultEdge: .left,
        preferredZone: .quickFlick,
        ergonomicWeight: 35.0,
        minLengthRatio: 0.16,
        defaultColorHex: "#BF5AF2"
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

// MARK: - Music Plugin
public struct MusicPlugin: PurahPodPlugin {
    public nonisolated let manifest = PurahPluginManifest(
        id: "music",
        displayName: "Dynamic Audio",
        systemIcon: "music.note",
        author: "Project Purah",
        version: "1.0.0",
        description: "System media control and playback monitor",
        defaultEdge: .right,
        preferredZone: .goldenAction,
        ergonomicWeight: 25.0,
        minLengthRatio: 0.14,
        defaultColorHex: "#FF375F"
    )

    public let state: MusicPluginState

    public init(state: MusicPluginState = MusicPluginState()) {
        self.state = state
    }

    public func makeRailBarView(context: PurahPluginContext) -> AnyView {
        AnyView(
            WaveMeterAmbientView(
                samples: state.waveformSamples,
                isPlaying: state.isPlaying,
                isAnimated: state.isWaveformAnimationEnabled,
                height: context.slotHeight
            )
            .frame(width: context.railWidth, height: context.slotHeight)
        )
    }

    public func makeDrawerView(context: PurahPluginContext) -> AnyView {
        AnyView(MusicDrawerView(state: state, store: context.store))
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
        version: "1.0.0",
        description: "Day and week agenda timeline with upcoming event alerts",
        defaultEdge: .right,
        preferredZone: .goldenAction,
        ergonomicWeight: 45.0,
        minLengthRatio: 0.16,
        defaultColorHex: "#FF9F0A"
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
    }

    public func onUnmount(store: PurahWorkspaceStore) {
        state.unmount(store: store)
    }

    public var supportedDrawerModes: Set<PurahDrawerMode> { [.stepped] }

    public func minimumDrawerHeight(store: PurahWorkspaceStore) -> CGFloat { 150.0 }

    public func hasPinnedChild(store: PurahWorkspaceStore) -> Bool {
        let events = !store.calendarEvents.isEmpty ? store.calendarEvents : state.events
        return events.contains { store.isItemPinned(id: $0.id) }
    }

    public func ownsSubItemId(_ itemId: String, store: PurahWorkspaceStore) -> Bool {
        state.events.contains { $0.id == itemId } || store.calendarEvents.contains { $0.id == itemId }
    }

    public var isDecomposed: Bool {
        true
    }

    public func isDecomposed(store: PurahWorkspaceStore) -> Bool {
        true
    }

    public var subItemCount: Int {
        state.events.count
    }

    public var subItemTitles: [String] {
        state.events.map(\.title)
    }

    public func subItemCount(store: PurahWorkspaceStore) -> Int {
        let events = !store.calendarEvents.isEmpty ? store.calendarEvents : state.events
        return events.count
    }

    public func subItemId(at index: Int, store: PurahWorkspaceStore) -> String? {
        let events = !store.calendarEvents.isEmpty ? store.calendarEvents : state.events
        guard events.indices.contains(index) else { return nil }
        return events[index].id
    }

    public func subItemTitle(at index: Int, store: PurahWorkspaceStore) -> String? {
        let events = !store.calendarEvents.isEmpty ? store.calendarEvents : state.events
        guard events.indices.contains(index) else { return nil }
        return events[index].title
    }

    public func steppedItems(context: PurahPluginContext) -> [PurahPluginSubItem] {
        state.events.map { event in
            let isPast = event.endTime < Date()
            let isOngoing = event.isOngoing
            let isImminent = event.isImminent
            let state: RailItemActivityState = isOngoing ? .ongoing : (isImminent ? .alerting : (isPast ? .inactive : .normal))
            return PurahPluginSubItem(
                id: event.id,
                title: event.title,
                subtitle: event.location,
                systemIcon: "calendar",
                badge: isOngoing ? "NOW" : (isImminent ? "SOON" : nil),
                state: state,
                gaugeRatio: nil,
                gaugeStyle: .none,
                tintColorHex: nil,
                isPinned: context.store.isItemPinned(id: event.id)
            )
        }
    }

    public func makeSteppedDrawerView(subItemId: String, context: PurahPluginContext) -> AnyView? {
        let events = !context.store.calendarEvents.isEmpty ? context.store.calendarEvents : state.events
        guard let event = events.first(where: { $0.id == subItemId }) else { return nil }
        let isPinned = context.store.isItemPinned(id: subItemId)
        let state: ItemDrawerState = (context.isExpanded || isPinned) ? .expandedDrawer : .dockedFlush
        return AnyView(
            CalendarItemDrawerView(
                event: event,
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
        version: "1.0.0",
        description: "System reminders synchronization and quick task tracking",
        defaultEdge: .right,
        preferredZone: .goldenAction,
        ergonomicWeight: 40.0,
        minLengthRatio: 0.15,
        defaultColorHex: "#30D158"
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
    }

    public func onUnmount(store: PurahWorkspaceStore) {
        state.unmount(store: store)
    }

    public var supportedDrawerModes: Set<PurahDrawerMode> { [.stepped] }

    public func minimumDrawerHeight(store: PurahWorkspaceStore) -> CGFloat { 150.0 }

    public func hasPinnedChild(store: PurahWorkspaceStore) -> Bool {
        let items = !store.todos.isEmpty ? store.todos : state.todos
        return items.contains { store.isItemPinned(id: $0.id) }
    }

    public func ownsSubItemId(_ itemId: String, store: PurahWorkspaceStore) -> Bool {
        state.todos.contains { $0.id == itemId } || store.todos.contains { $0.id == itemId }
    }

    public var isDecomposed: Bool {
        true
    }

    public func isDecomposed(store: PurahWorkspaceStore) -> Bool {
        true
    }

    public var subItemCount: Int {
        state.todos.count
    }

    public var subItemTitles: [String] {
        state.todos.map(\.title)
    }

    public func subItemCount(store: PurahWorkspaceStore) -> Int {
        let items = !store.todos.isEmpty ? store.todos : state.todos
        return items.count
    }

    public func subItemId(at index: Int, store: PurahWorkspaceStore) -> String? {
        let items = !store.todos.isEmpty ? store.todos : state.todos
        guard items.indices.contains(index) else { return nil }
        return items[index].id
    }

    public func subItemTitle(at index: Int, store: PurahWorkspaceStore) -> String? {
        let items = !store.todos.isEmpty ? store.todos : state.todos
        guard items.indices.contains(index) else { return nil }
        return items[index].title
    }

    public func steppedItems(context: PurahPluginContext) -> [PurahPluginSubItem] {
        state.todos.map { todo in
            PurahPluginSubItem(
                id: todo.id,
                title: todo.title,
                subtitle: todo.listTitle,
                systemIcon: "checklist",
                badge: nil,
                state: todo.isCompleted ? .inactive : .normal,
                gaugeRatio: nil,
                gaugeStyle: .none,
                tintColorHex: nil,
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
        let todos = !context.store.todos.isEmpty ? context.store.todos : state.todos
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
        VStack(alignment: .leading, spacing: 10) {
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
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Live 120FPS Waveform Animation", isOn: Binding(
                get: { state.isWaveformAnimationEnabled },
                set: {
                    state.isWaveformAnimationEnabled = $0
                    state.save()
                    store.isMusicWaveformAnimationEnabled = $0
                }
            ))
            .font(.subheadline)

            HStack {
                Text("Audio Source: \(state.track.sourceApp)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(state.track.isPlaying ? "Playing" : "Paused")
                    .font(.caption.weight(.medium))
                    .foregroundColor(state.track.isPlaying ? .green : .secondary)
            }
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
                    store.isVitalsDecomposed = $0
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
                                store.vitalsEnabledMetrics = state.enabledMetrics
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
                            store.vitalsThresholds = state.thresholds
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
                                        store.vitalsThresholds.batteryLow = state.thresholds.batteryLow
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
                                        store.vitalsThresholds.networkWarningMB = state.thresholds.networkWarningMB
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
                                        store.vitalsThresholds.networkDangerMB = state.thresholds.networkDangerMB
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
                store.vitalsThresholds[keyPath: keyPath] = state.thresholds[keyPath: keyPath]
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
                    store.isScriptsDecomposed = $0
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
                                        store.scriptsEnabledActionIds = updated
                                        store.savePersistentState()
                                    }
                                } else {
                                    updated.append(action.id)
                                    state.enabledActionIds = updated
                                    state.save()
                                    store.scriptsEnabledActionIds = updated
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
                        store.scriptsEnabledActionIds = state.enabledActionIds
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
                                store.scriptsEnabledActionIds = state.enabledActionIds
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
                                    store.scriptsEnabledActionIds = state.enabledActionIds
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
                    store.shelfFiles.removeAll()
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
                store.quickNote.text = ""
                store.quickNote.lastModified = Date()
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
        version: "1.0.0",
        description: "Persistent background terminal and command shell",
        defaultEdge: .left,
        preferredZone: .goldenAction,
        ergonomicWeight: 35.0,
        minLengthRatio: 0.20,
        defaultColorHex: "#00F5D4",
        defaultDrawerWidth: 520.0
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
        360.0
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
                        store.terminalFontFamily = $0
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
                        store.terminalFontSize = $0
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
