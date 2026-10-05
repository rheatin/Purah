// Sources/PurahUI/Plugins/BuiltInPlugins.swift
import SwiftUI
import AppKit
import PurahCore

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
        ergonomicWeight: 30.0,
        minLengthRatio: 0.10,
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
        minLengthRatio: 0.10,
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
        ergonomicWeight: 35.0,
        minLengthRatio: 0.12,
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
        minLengthRatio: 0.10,
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
        minLengthRatio: 0.10,
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
        VStack(alignment: .leading, spacing: 8) {
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
                .buttonStyle(.plain)
                .font(.caption.weight(.medium))
                .foregroundColor(.accentColor)
            }
            .foregroundColor(.secondary)
        }
    }
}

public struct ScriptsPluginSettingsView: View {
    public let store: PurahWorkspaceStore

    public init(store: PurahWorkspaceStore) {
        self.store = store
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Runway Actions: Flush DNS, Empty Trash, Toggle Dark Mode")
                .font(.caption)
                .foregroundColor(.secondary)
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
