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
        description: "Real-time hardware performance, memory, and thermal monitoring",
        defaultEdge: .left,
        preferredZone: .glance,
        ergonomicWeight: 35.0,
        minLengthRatio: 0.22,
        defaultColorHex: "#00E5A3"
    )

    public init() {}

    public func makeRailBarView(context: PurahPluginContext) -> AnyView {
        AnyView(VitalsRailBarPluginView(context: context))
    }

    public func makeDrawerView(context: PurahPluginContext) -> AnyView {
        AnyView(HardwareVitalsDrawerView(store: context.store))
    }

    public func makeSettingsView(store: PurahWorkspaceStore) -> AnyView? {
        AnyView(VitalsPluginSettingsView(store: store))
    }

    public var supportedDrawerModes: Set<PurahDrawerMode> { [.composite, .stepped] }

    public func dynamicBarColor(context: PurahPluginContext) -> Color? {
        VitalsColorResolver.overallVitalsColor(
            vitals: HardwareVitalsService.shared.metrics,
            thresholds: context.store.vitalsThresholds,
            palette: context.palette
        )
    }

    public func steppedItems(context: PurahPluginContext) -> [PurahPluginSubItem] {
        let metrics = HardwareVitalsService.shared.metrics
        return context.store.vitalsEnabledMetrics.map { metric in
            let ratio: Double = {
                switch metric {
                case .cpu: return metrics.cpuUsage
                case .gpu: return metrics.gpuUsage
                case .ram: return metrics.memoryUsage
                case .thermal: return metrics.isUnderThermalPressure ? 0.90 : 0.30
                case .power: return Double(metrics.batteryLevel) / 100.0
                case .network: return min((metrics.networkDownSpeed + metrics.networkUpSpeed) / 10_485_760.0, 1.0)
                case .disk:
                    return metrics.diskTotalGB > 0 ? (metrics.diskTotalGB - metrics.diskFreeGB) / metrics.diskTotalGB : 0.5
                }
            }()
            let color = VitalsColorResolver.color(for: metric, vitals: metrics, thresholds: context.store.vitalsThresholds, palette: context.palette)
            let isAlerting = (metric == .thermal && metrics.isUnderThermalPressure) ||
                             (metric == .cpu && metrics.cpuUsage > context.store.vitalsThresholds.cpuDanger)
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
}

public struct VitalsRailBarPluginView: View {
    public let context: PurahPluginContext
    private var vitals: HardwareVitalsService { HardwareVitalsService.shared }

    public init(context: PurahPluginContext) {
        self.context = context
    }

    public var body: some View {
        let cpu = vitals.metrics.cpuUsage
        let isPulsing = vitals.metrics.isUnderThermalPressure
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

    public init() {}

    public func makeRailBarView(context: PurahPluginContext) -> AnyView {
        AnyView(ScriptsRailBarPluginView(context: context))
    }

    public func makeDrawerView(context: PurahPluginContext) -> AnyView {
        AnyView(ScriptRunwayDrawerView(store: context.store))
    }

    public func makeSettingsView(store: PurahWorkspaceStore) -> AnyView? {
        AnyView(ScriptsPluginSettingsView(store: store))
    }

    public var supportedDrawerModes: Set<PurahDrawerMode> { [.composite, .stepped] }

    public func steppedItems(context: PurahPluginContext) -> [PurahPluginSubItem] {
        let runway = ScriptRunwayService.shared
        return context.store.scriptsEnabledActions.map { action in
            let isRunning = runway.isRunning && runway.lastExecutedActionId == action.id
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
           let action = ScriptRunwayService.shared.action(for: subId) {
            context.performHaptic(.levelChange)
            Task {
                let res = await ScriptRunwayService.shared.executeAction(action)
                if res.success {
                    context.performHaptic(.alignment)
                    context.showToast("Ran \(action.name)", "checkmark.circle.fill")
                } else {
                    context.showWarning("Failed: \(res.message)")
                }
            }
        } else {
            context.requestExpand()
        }
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

    public init() {}

    public func makeRailBarView(context: PurahPluginContext) -> AnyView {
        AnyView(
            RailBarAmbientView(
                type: .notes,
                hasContent: !context.store.quickNote.text.isEmpty,
                color: context.accentColor,
                barWidth: context.railWidth
            )
            .frame(width: context.railWidth, height: context.slotHeight)
        )
    }

    public func makeDrawerView(context: PurahPluginContext) -> AnyView {
        AnyView(QuickNoteDrawerView(store: context.store))
    }

    public func makeSettingsView(store: PurahWorkspaceStore) -> AnyView? {
        AnyView(NotesPluginSettingsView(store: store))
    }
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

    public init() {}

    public func makeRailBarView(context: PurahPluginContext) -> AnyView {
        AnyView(
            RailBarAmbientView(
                type: .shelf,
                hasContent: !context.store.shelfFiles.isEmpty,
                color: context.accentColor,
                barWidth: context.railWidth
            )
            .frame(width: context.railWidth, height: context.slotHeight)
        )
    }

    public func makeDrawerView(context: PurahPluginContext) -> AnyView {
        AnyView(DropShelfDrawerView(store: context.store))
    }

    public func makeSettingsView(store: PurahWorkspaceStore) -> AnyView? {
        AnyView(ShelfPluginSettingsView(store: store))
    }

    public var supportedDropTypes: [UTType] { [.fileURL] }

    public func onDrop(providers: [NSItemProvider], context: PurahPluginContext) -> Bool {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url = url {
                    Task { @MainActor in
                        let name = url.lastPathComponent
                        let ext = url.pathExtension
                        let attr = try? FileManager.default.attributesOfItem(atPath: url.path)
                        let size = (attr?[.size] as? Int64) ?? 0
                        let sizeDesc = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
                        context.store.shelfFiles.append(ShelfFileItem(
                            name: name,
                            sizeDescription: sizeDesc,
                            fileExtension: ext,
                            filePath: url.path
                        ))
                        context.performHaptic(.alignment)
                        context.showToast("Stashed \(name)", "tray.and.arrow.down.fill")
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

    public init() {}

    public func makeRailBarView(context: PurahPluginContext) -> AnyView {
        AnyView(
            WaveMeterAmbientView(
                samples: context.store.musicTrack.waveformSamples,
                isPlaying: context.store.musicTrack.isPlaying,
                isAnimated: context.store.isMusicWaveformAnimationEnabled,
                height: context.slotHeight
            )
            .frame(width: context.railWidth, height: context.slotHeight)
        )
    }

    public func makeDrawerView(context: PurahPluginContext) -> AnyView {
        AnyView(MusicDrawerView(store: context.store))
    }

    public func makeSettingsView(store: PurahWorkspaceStore) -> AnyView? {
        AnyView(MusicPluginSettingsView(store: store))
    }

    public func onRailBarTap(subItemId: String?, context: PurahPluginContext) {
        context.performHaptic(.alignment)
        SystemMusicSyncService.shared.togglePlayPause(store: context.store)
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

    public init() {}

    public func makeRailBarView(context: PurahPluginContext) -> AnyView {
        AnyView(
            ProgressTimelineAmbientView(
                progress: SystemCalendarSyncService.shared.todayProgress()
            )
            .frame(width: context.railWidth, height: context.slotHeight)
        )
    }

    public func makeDrawerView(context: PurahPluginContext) -> AnyView {
        AnyView(CalendarDrawerView(store: context.store))
    }

    public func makeSettingsView(store: PurahWorkspaceStore) -> AnyView? {
        AnyView(CalendarPluginSettingsView(store: store))
    }

    public var supportedDrawerModes: Set<PurahDrawerMode> { [.stepped] }

    public func steppedItems(context: PurahPluginContext) -> [PurahPluginSubItem] {
        context.store.calendarEvents.map { event in
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

    public init() {}

    public func makeRailBarView(context: PurahPluginContext) -> AnyView {
        let radius = min(context.railWidth / 2, 4)
        return AnyView(
            RoundedRectangle(cornerRadius: radius)
                .fill(context.accentColor.opacity(0.85))
                .frame(width: context.railWidth, height: context.slotHeight)
        )
    }

    public func makeDrawerView(context: PurahPluginContext) -> AnyView {
        AnyView(TodoDrawerView(store: context.store))
    }

    public func makeSettingsView(store: PurahWorkspaceStore) -> AnyView? {
        AnyView(TodoPluginSettingsView(store: store))
    }

    public var supportedDrawerModes: Set<PurahDrawerMode> { [.stepped] }

    public func steppedItems(context: PurahPluginContext) -> [PurahPluginSubItem] {
        context.store.todos.map { todo in
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
                await SystemRemindersSyncService.shared.toggleCompletion(id: id, into: context.store)
            }
        } else {
            context.requestExpand()
        }
    }
}

// MARK: - Plugin Settings Views

public struct CalendarPluginSettingsView: View {
    public let store: PurahWorkspaceStore

    public init(store: PurahWorkspaceStore) {
        self.store = store
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Calendar Scope")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Picker("", selection: Binding(
                    get: { store.calendarScope },
                    set: { newScope in
                        store.calendarScope = newScope
                        SystemCalendarSyncService.shared.syncEvents(into: store, scope: newScope)
                    }
                )) {
                    ForEach(CalendarTimeScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
            }

            Toggle("Pulsing Glow for Imminent Events", isOn: Binding(
                get: { store.isEventGlowAlertEnabled },
                set: { store.isEventGlowAlertEnabled = $0 }
            ))
            .font(.subheadline)
        }
    }
}

public struct TodoPluginSettingsView: View {
    public let store: PurahWorkspaceStore

    public init(store: PurahWorkspaceStore) {
        self.store = store
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Reminders Scope")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Picker("", selection: Binding(
                    get: { store.remindersScope },
                    set: { newScope in
                        store.remindersScope = newScope
                        Task {
                            await SystemRemindersSyncService.shared.syncReminders(into: store, scope: newScope)
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
                Text("Pending Tasks: \(store.todos.filter { !$0.isCompleted }.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Sync Reminders") {
                    Task {
                        await SystemRemindersSyncService.shared.syncReminders(into: store)
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
    public let store: PurahWorkspaceStore

    public init(store: PurahWorkspaceStore) {
        self.store = store
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Live 120FPS Waveform Animation", isOn: Binding(
                get: { store.isMusicWaveformAnimationEnabled },
                set: { store.isMusicWaveformAnimationEnabled = $0 }
            ))
            .font(.subheadline)

            HStack {
                Text("Audio Source: \(store.musicTrack.sourceApp)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(store.musicTrack.isPlaying ? "Playing" : "Paused")
                    .font(.caption.weight(.medium))
                    .foregroundColor(store.musicTrack.isPlaying ? .green : .secondary)
            }
        }
    }
}

public struct VitalsPluginSettingsView: View {
    public let store: PurahWorkspaceStore

    public init(store: PurahWorkspaceStore) {
        self.store = store
    }

    public var body: some View {
        let vitals = HardwareVitalsService.shared.metrics
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Decompose into Stepped Metric Rail Chips", isOn: Binding(
                get: { store.isVitalsDecomposed },
                set: {
                    store.isVitalsDecomposed = $0
                    store.savePersistentState()
                }
            ))
            .font(.subheadline.weight(.semibold))

            Text("Splits hardware monitoring into individual rail chips (CPU, GPU, RAM, Thermal, Power, Network, Disk) like Calendar and Todo.")
                .font(.caption)
                .foregroundColor(.secondary)

            if store.isVitalsDecomposed {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Visible Sub-Metrics")
                        .font(.caption.weight(.bold))

                    ForEach(VitalsMetricType.allCases) { metric in
                        let isIncluded = store.vitalsEnabledMetrics.contains(metric)
                        Button {
                            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                                if isIncluded {
                                    if store.vitalsEnabledMetrics.count > 1 {
                                        store.vitalsEnabledMetrics.removeAll { $0 == metric }
                                    }
                                } else {
                                    store.vitalsEnabledMetrics.append(metric)
                                }
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
                            store.vitalsThresholds = VitalsColorThresholds()
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
                        Text("0% → \(Int(store.vitalsThresholds.cpuWarning * 100))% → \(Int(store.vitalsThresholds.cpuDanger * 100))% → 100%")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    GeometryReader { geo in
                        let totalWidth = geo.size.width
                        let warnRatio = max(min(CGFloat(store.vitalsThresholds.cpuWarning), 1.0), 0.0)
                        let dangerRatio = max(min(CGFloat(store.vitalsThresholds.cpuDanger), 1.0), warnRatio)
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
                            Text("Green (< \(Int(store.vitalsThresholds.cpuWarning * 100))%)")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        HStack(spacing: 4) {
                            Circle().fill(VitalsColorResolver.warningYellow).frame(width: 8, height: 8)
                            Text("Amber (\(Int(store.vitalsThresholds.cpuWarning * 100))% ~ \(Int(store.vitalsThresholds.cpuDanger * 100))%)")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        HStack(spacing: 4) {
                            Circle().fill(VitalsColorResolver.dangerRed).frame(width: 8, height: 8)
                            Text("Red (> \(Int(store.vitalsThresholds.cpuDanger * 100))%)")
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
                        warningLabel: "\(Int(store.vitalsThresholds.cpuWarning * 100))%",
                        warningValue: percentageBinding(for: \.cpuWarning, cappedBy: \.cpuDanger, isWarning: true),
                        warningRange: 10...90,
                        dangerLabel: "\(Int(store.vitalsThresholds.cpuDanger * 100))%",
                        dangerValue: percentageBinding(for: \.cpuDanger, cappedBy: \.cpuWarning, isWarning: false),
                        dangerRange: 50...99
                    )

                    // GPU Warning % (10% ~ 90%) & Danger % (50% ~ 99%)
                    thresholdRow(
                        title: "GPU Activity",
                        warningLabel: "\(Int(store.vitalsThresholds.gpuWarning * 100))%",
                        warningValue: percentageBinding(for: \.gpuWarning, cappedBy: \.gpuDanger, isWarning: true),
                        warningRange: 10...90,
                        dangerLabel: "\(Int(store.vitalsThresholds.gpuDanger * 100))%",
                        dangerValue: percentageBinding(for: \.gpuDanger, cappedBy: \.gpuWarning, isWarning: false),
                        dangerRange: 50...99
                    )

                    // RAM Warning % (20% ~ 90%) & Danger % (60% ~ 99%)
                    thresholdRow(
                        title: "Memory (RAM)",
                        warningLabel: "\(Int(store.vitalsThresholds.ramWarning * 100))%",
                        warningValue: percentageBinding(for: \.ramWarning, cappedBy: \.ramDanger, isWarning: true),
                        warningRange: 20...90,
                        dangerLabel: "\(Int(store.vitalsThresholds.ramDanger * 100))%",
                        dangerValue: percentageBinding(for: \.ramDanger, cappedBy: \.ramWarning, isWarning: false),
                        dangerRange: 60...99
                    )

                    // Battery Low Warning % (5% ~ 50%)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Battery Low Warning")
                                .font(.caption.weight(.medium))
                            Spacer()
                            Text("\(Int(store.vitalsThresholds.batteryLow * 100))%")
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
                                    get: { store.vitalsThresholds.batteryLow * 100.0 },
                                    set: {
                                        store.vitalsThresholds.batteryLow = $0 / 100.0
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
                            Text("Warn: \(Int(store.vitalsThresholds.networkWarningMB)) MB/s")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(VitalsColorResolver.warningYellow)
                            Text("•")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Text("Danger: \(Int(store.vitalsThresholds.networkDangerMB)) MB/s")
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
                                    get: { store.vitalsThresholds.networkWarningMB },
                                    set: {
                                        store.vitalsThresholds.networkWarningMB = min($0, store.vitalsThresholds.networkDangerMB - 1.0)
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
                                    get: { store.vitalsThresholds.networkDangerMB },
                                    set: {
                                        store.vitalsThresholds.networkDangerMB = max($0, store.vitalsThresholds.networkWarningMB + 1.0)
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
                    HardwareVitalsService.shared.refreshMetrics(includeProcesses: true)
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
            get: { store.vitalsThresholds[keyPath: keyPath] * 100.0 },
            set: { newVal in
                let val = newVal / 100.0
                let limit = store.vitalsThresholds[keyPath: limitKeyPath]
                store.vitalsThresholds[keyPath: keyPath] = isWarning ? min(val, limit - 0.05) : max(val, limit + 0.05)
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
    public let store: PurahWorkspaceStore
    private var runway: ScriptRunwayService { ScriptRunwayService.shared }

    @State private var newActionName: String = ""
    @State private var newCommandType: ScriptCommandType = .shortcut
    @State private var newScriptContent: String = ""
    @State private var newSystemIcon: String = "bolt.fill"
    @State private var newDescription: String = ""
    @State private var isAddingAction: Bool = false

    @State private var editingActionId: String? = nil
    @State private var editActionName: String = ""
    @State private var editCommandType: ScriptCommandType = .shortcut
    @State private var editScriptContent: String = ""
    @State private var editSystemIcon: String = "bolt.fill"
    @State private var editDescription: String = ""

    public init(store: PurahWorkspaceStore) {
        self.store = store
    }

    private var effectiveEnabledActionIds: [String] {
        if store.scriptsEnabledActionIds.isEmpty {
            return runway.actions.map(\.id)
        }
        return store.scriptsEnabledActionIds
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Decompose into Stepped Script Rail Chips", isOn: Binding(
                get: { store.isScriptsDecomposed },
                set: {
                    store.isScriptsDecomposed = $0
                    store.savePersistentState()
                }
            ))
            .font(.subheadline.weight(.semibold))

            Text("Splits script runway into individual interactive rail chips for rapid one-click execution.")
                .font(.caption)
                .foregroundColor(.secondary)

            if store.isScriptsDecomposed {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Visible Stepped Action Chips")
                        .font(.caption.weight(.bold))

                    let currentEnabled = effectiveEnabledActionIds

                    ForEach(runway.actions) { action in
                        let isIncluded = currentEnabled.contains(action.id)
                        Button {
                            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                                var updated = currentEnabled
                                if isIncluded {
                                    if updated.count > 1 {
                                        updated.removeAll { $0 == action.id }
                                        store.scriptsEnabledActionIds = updated
                                        store.savePersistentState()
                                    }
                                } else {
                                    updated.append(action.id)
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
                Text("Actions & Shortcuts (\(runway.actions.count))")
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
                        runway.resetToDefaults()
                        editingActionId = nil
                        store.scriptsEnabledActionIds = runway.actions.map(\.id)
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
                                description: newDescription.trimmingCharacters(in: .whitespaces)
                            )
                            withAnimation {
                                runway.addAction(item)
                                if !store.scriptsEnabledActionIds.isEmpty {
                                    store.scriptsEnabledActionIds.append(item.id)
                                    store.savePersistentState()
                                }
                                newActionName = ""
                                newScriptContent = ""
                                newDescription = ""
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
                ForEach(runway.actions) { action in
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
                                    runway.removeAction(id: action.id)
                                    if store.scriptsEnabledActionIds.contains(action.id) {
                                        store.scriptsEnabledActionIds.removeAll { $0 == action.id }
                                        store.savePersistentState()
                                    }
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
                                            description: editDescription.trimmingCharacters(in: .whitespaces)
                                        )
                                        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                                            ScriptRunwayService.shared.updateAction(updated)
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
    public let store: PurahWorkspaceStore

    public init(store: PurahWorkspaceStore) {
        self.store = store
    }

    public var body: some View {
        HStack {
            Text("Stashed Files: \(store.shelfFiles.count) item(s)")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            if !store.shelfFiles.isEmpty {
                Button("Clear Shelf") {
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
    public let store: PurahWorkspaceStore

    public init(store: PurahWorkspaceStore) {
        self.store = store
    }

    public var body: some View {
        HStack {
            Text("Scratchpad length: \(store.quickNote.text.count) character(s)")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Button("Clear Notes") {
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
