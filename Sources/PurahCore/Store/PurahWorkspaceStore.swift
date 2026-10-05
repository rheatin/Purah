// Sources/PurahCore/Store/PurahWorkspaceStore.swift
import Foundation
import Observation

public enum DrawerWidthMode: String, Codable, CaseIterable, Sendable {
    case fixed = "fixed"
    case adaptive = "adaptive"
    
    public var displayName: String {
        switch self {
        case .fixed: return "Fixed"
        case .adaptive: return "Adaptive"
        }
    }
}

@Observable
public final class PurahWorkspaceStore: @unchecked Sendable {
    public var pods: [SlotPod] = []
    public var activeDrawerPodId: String? = nil
    public var activeDrawerItemId: String? = nil
    public var hoveredPodId: String? = nil
    public var isDrawerPinned: Bool = false
    public var pinnedDrawerItemIds: Set<String> = []
    public var currentPreset: PodPreset = .balanced
    public var animationStyle: AnimationStyle = .magneticCascade

    public func togglePinItem(id: String) {
        if pinnedDrawerItemIds.contains(id) {
            pinnedDrawerItemIds.remove(id)
        } else {
            pinnedDrawerItemIds.insert(id)
        }
    }

    public func isItemPinned(id: String) -> Bool {
        pinnedDrawerItemIds.contains(id)
    }

    public func activateDrawer(podId: String, itemId: String? = nil) {
        activeDrawerPodId = podId
        activeDrawerItemId = itemId ?? podId
        hoveredPodId = podId
    }

    public func dismissActiveDrawer() {
        activeDrawerPodId = nil
        activeDrawerItemId = nil
        hoveredPodId = nil
    }

    public func hasPinnedItem(on edge: MountEdge) -> Bool {
        if isDrawerPinned { return true }
        for pod in pods where pod.edge == edge && pod.isEnabled {
            if isItemPinned(id: pod.id) { return true }
            if pod.id == "todo" && todos.contains(where: { isItemPinned(id: $0.id) }) { return true }
            if pod.id == "calendar" && calendarEvents.contains(where: { isItemPinned(id: $0.id) }) { return true }
        }
        return false
    }

    public func pod(forItemId id: String) -> SlotPod? {
        if let p = pods.first(where: { $0.id == id }) {
            return p
        }
        if todos.contains(where: { $0.id == id }) {
            return pods.first(where: { $0.id == "todo" })
        }
        if calendarEvents.contains(where: { $0.id == id }) {
            return pods.first(where: { $0.id == "calendar" })
        }
        return nil
    }

    public var activePod: SlotPod? {
        if let podId = activeDrawerPodId, let p = pods.first(where: { $0.id == podId }) {
            return p
        }
        if let itemId = activeDrawerItemId {
            if todos.contains(where: { $0.id == itemId }) {
                return pods.first(where: { $0.id == "todo" })
            }
            if calendarEvents.contains(where: { $0.id == itemId }) {
                return pods.first(where: { $0.id == "calendar" })
            }
            if let p = pods.first(where: { $0.id == itemId }) {
                return p
            }
        }
        return nil
    }

    // Real-time synchronization flags and scopes
    public var isUsingRealCalendar: Bool = false
    public var isUsingRealReminders: Bool = false
    public var calendarScope: CalendarTimeScope = .today
    public var remindersScope: RemindersScope = .allIncomplete
    public var isEventGlowAlertEnabled: Bool = true
    public var isMusicWaveformAnimationEnabled: Bool = true

    // User-configurable rail width (4px ~ 16px) and drawer extrusion settings
    public var railBarWidth: Double = 8.0
    public var drawerWidthMode: DrawerWidthMode = .fixed
    public var fixedDrawerWidth: Double = 290.0 // Bounds: 220px ~ 330px
    public var customPodColors: [String: String] = [:]

    public func effectiveDrawerWidth(for text: String = "", baseWidth: Double = 290.0) -> CGFloat {
        switch drawerWidthMode {
        case .fixed:
            return CGFloat(min(max(fixedDrawerWidth, 220.0), 330.0))
        case .adaptive:
            let charCount = text.count
            let textBonus = Double(charCount) * 5.0
            let extraOffset = max(baseWidth - 280.0, 0.0)
            let calculated = 230.0 + textBonus + extraOffset
            let clamped = min(max(calculated, 230.0 + extraOffset), 330.0)
            return CGFloat(clamped)
        }
    }

    public func minimumDrawerHeight(for podId: String) -> CGFloat {
        switch podId {
        case "vitals": return 320.0
        case "scripts": return 220.0
        case "shelf": return 180.0
        case "notes": return 200.0
        case "music": return 140.0
        case "calendar": return 160.0
        case "todo": return 160.0
        default: return 140.0
        }
    }

    public func defaultColorHex(for podId: String) -> String {
        switch podId {
        case "calendar": return "#FF5A60" // Coral Red
        case "todo": return "#FF9E0A"     // Amber Gold
        case "music": return "#FF2D55"    // Neon Magenta
        case "vitals": return "#00E5A3"   // Emerald Green
        case "shelf": return "#2ED573"    // Mint Green
        case "notes": return "#FFD166"    // Warm Gold
        case "scripts": return "#6C5CE7"  // Obsidian Purple
        default: return "#00F5D4"
        }
    }

    public func podColorHex(for podId: String) -> String {
        customPodColors[podId] ?? defaultColorHex(for: podId)
    }

    public func setPodColorHex(podId: String, hex: String) {
        customPodColors[podId] = hex
        savePersistentState()
    }

    // Built-in Pod Business Data
    public var calendarEvents: [CalendarEventItem] = []
    public var todos: [TodoItem] = []
    public var musicTrack: MusicTrackInfo = .init()
    public var shelfFiles: [ShelfFileItem] = []
    public var quickNote: NoteContent = .init()

    public init() {
        self.pods = Self.defaultPods()
        self.calendarEvents = Self.defaultEvents()
        self.todos = Self.defaultTodos()
        self.shelfFiles = Self.defaultShelfFiles()
        loadPersistentState()
        autoLayoutAll()
    }

    // MARK: - Local Persistence
    public func loadPersistentState() {
        let defaults = UserDefaults.standard

        if let savedText = defaults.string(forKey: "purah.quickNote.text") {
            let lastMod = (defaults.object(forKey: "purah.quickNote.lastModified") as? Date) ?? Date()
            self.quickNote = NoteContent(text: savedText, lastModified: lastMod)
        }

        if let colors = defaults.dictionary(forKey: "purah.customPodColors") as? [String: String] {
            self.customPodColors = colors
        }

        if let modeStr = defaults.string(forKey: "purah.drawerWidthMode"),
           let mode = DrawerWidthMode(rawValue: modeStr) {
            self.drawerWidthMode = mode
        }

        let savedFixedW = defaults.double(forKey: "purah.fixedDrawerWidth")
        if savedFixedW >= 220.0 {
            self.fixedDrawerWidth = savedFixedW
        }

        let savedRailW = defaults.double(forKey: "purah.railBarWidth")
        if savedRailW >= 4.0 {
            self.railBarWidth = savedRailW
        }

        if let presetStr = defaults.string(forKey: "purah.currentPreset"),
           let preset = PodPreset(rawValue: presetStr) {
            self.currentPreset = preset
        }
    }

    public func savePersistentState() {
        let defaults = UserDefaults.standard
        defaults.set(quickNote.text, forKey: "purah.quickNote.text")
        defaults.set(quickNote.lastModified, forKey: "purah.quickNote.lastModified")
        defaults.set(customPodColors, forKey: "purah.customPodColors")
        defaults.set(drawerWidthMode.rawValue, forKey: "purah.drawerWidthMode")
        defaults.set(fixedDrawerWidth, forKey: "purah.fixedDrawerWidth")
        defaults.set(railBarWidth, forKey: "purah.railBarWidth")
        defaults.set(currentPreset.rawValue, forKey: "purah.currentPreset")
    }

    public func autoLayoutAll() {
        let left = ErgonomicAutoLayoutEngine.layout(pods: pods, on: .left)
        let right = ErgonomicAutoLayoutEngine.layout(pods: pods, on: .right)
        let resolved = left + right
        let map = Dictionary(uniqueKeysWithValues: resolved.map { ($0.id, $0) })
        for i in 0..<pods.count {
            if let updated = map[pods[i].id] {
                pods[i] = updated
            }
        }
    }

    public func togglePodEnabled(id: String) {
        guard let index = pods.firstIndex(where: { $0.id == id }) else { return }
        pods[index].isEnabled.toggle()
        autoLayoutAll()
    }

    public func fillRail(podId: String) {
        guard pods.contains(where: { $0.id == podId }) else { return }
        // 让当前 Pod 占满整条轨道的有效安全区间 (0.05 ~ 0.95)
        let safeSpan = 0.90
        let newRange = NormalizedRange(start: 0.05, length: safeSpan)
        updatePodRange(id: podId, newRange: newRange)
    }

    public func applyPreset(_ preset: PodPreset) {
        currentPreset = preset
        switch preset {
        case .balanced:
            setPod(id: "shelf", edge: .left, zone: .goldenAction, weight: 35)
            setPod(id: "notes", edge: .left, zone: .quickFlick, weight: 25)
            setPod(id: "calendar", edge: .right, zone: .goldenAction, weight: 40)
            setPod(id: "todo", edge: .right, zone: .goldenAction, weight: 35)
            setPod(id: "music", edge: .right, zone: .quickFlick, weight: 25)
        case .sprintProductivity:
            setPod(id: "shelf", edge: .left, zone: .goldenAction, weight: 50)
            setPod(id: "notes", edge: .left, zone: .goldenAction, weight: 35)
            setPod(id: "calendar", edge: .right, zone: .goldenAction, weight: 45)
            setPod(id: "todo", edge: .right, zone: .goldenAction, weight: 45)
            setPod(id: "music", edge: .right, zone: .quickFlick, weight: 15)
        case .immersiveMultimedia:
            setPod(id: "music", edge: .left, zone: .goldenAction, weight: 50)
            setPod(id: "notes", edge: .left, zone: .quickFlick, weight: 30)
            setPod(id: "shelf", edge: .left, zone: .quickFlick, weight: 20)
            setPod(id: "calendar", edge: .right, zone: .glance, weight: 60)
            setPod(id: "todo", edge: .right, zone: .quickFlick, weight: 30)
        }
        autoLayoutAll()
    }

    public func updatePodRange(id: String, newRange: NormalizedRange) {
        guard let pod = pods.first(where: { $0.id == id }) else { return }
        pods = SpringConstraintSolver.resolve(
            draggedPodId: id,
            newRange: newRange,
            allPods: pods,
            on: pod.edge
        )
    }

    public func movePod(id: String, to edge: MountEdge) {
        guard let index = pods.firstIndex(where: { $0.id == id }) else { return }
        pods[index].edge = edge
        autoLayoutAll()
    }

    private func setPod(id: String, edge: MountEdge, zone: ZoneType, weight: Double) {
        if let idx = pods.firstIndex(where: { $0.id == id }) {
            pods[idx].edge = edge
            pods[idx].preferredZone = zone
            pods[idx].ergonomicWeight = weight
            pods[idx].isEnabled = true
        }
    }

    public static func defaultPods() -> [SlotPod] {
        [
            SlotPod(id: "calendar", name: "Calendar Timeline", systemIcon: "calendar", edge: .right, range: .init(start: 0.15, length: 0.35), ambientStyle: .progressTimeline, preferredZone: .goldenAction, ergonomicWeight: 40, minLength: 0.12),
            SlotPod(id: "todo", name: "Todo Checklist", systemIcon: "checklist", edge: .right, range: .init(start: 0.52, length: 0.25), ambientStyle: .segmentGauge, preferredZone: .goldenAction, ergonomicWeight: 35, minLength: 0.12),
            SlotPod(id: "music", name: "Music Waveform", systemIcon: "waveform", edge: .right, range: .init(start: 0.79, length: 0.12), ambientStyle: .waveLevelMeter, preferredZone: .quickFlick, ergonomicWeight: 25, minLength: 0.08),
            SlotPod(id: "vitals", name: "Hardware Vitals", systemIcon: "waveform.path.ecg", edge: .left, range: .init(start: 0.10, length: 0.16), ambientStyle: .progressTimeline, preferredZone: .glance, ergonomicWeight: 30, minLength: 0.10),
            SlotPod(id: "shelf", name: "Temporary Shelf", systemIcon: "tray.fill", edge: .left, range: .init(start: 0.28, length: 0.30), ambientStyle: .ghostDot, preferredZone: .goldenAction, ergonomicWeight: 40, minLength: 0.12),
            SlotPod(id: "notes", name: "Quick Notes", systemIcon: "note.text", edge: .left, range: .init(start: 0.60, length: 0.18), ambientStyle: .ghostDot, preferredZone: .goldenAction, ergonomicWeight: 30, minLength: 0.10),
            SlotPod(id: "scripts", name: "Script Runway", systemIcon: "terminal.fill", edge: .left, range: .init(start: 0.80, length: 0.14), ambientStyle: .ghostDot, preferredZone: .quickFlick, ergonomicWeight: 25, minLength: 0.08)
        ]
    }

    private static func defaultEvents() -> [CalendarEventItem] {
        let cal = Calendar.current
        let today = Date()
        let d1 = cal.date(bySettingHour: 10, minute: 0, second: 0, of: today) ?? today
        let d2 = cal.date(bySettingHour: 11, minute: 30, second: 0, of: today) ?? today
        let d3 = cal.date(bySettingHour: 14, minute: 0, second: 0, of: today) ?? today
        let d4 = cal.date(bySettingHour: 15, minute: 0, second: 0, of: today) ?? today
        return [
            CalendarEventItem(title: "Architecture Review", location: "Central Workshop", startTime: d1, endTime: d2),
            CalendarEventItem(title: "Environmental Monitoring", location: "Observation Station", startTime: d3, endTime: d4)
        ]
    }

    private static func defaultTodos() -> [TodoItem] {
        [
            TodoItem(title: "Calibrate left tactile edge sensor", isCompleted: true),
            TodoItem(title: "Update energy waveform telemetry", isCompleted: false),
            TodoItem(title: "Verify multi-display adaptive layout", isCompleted: false),
            TodoItem(title: "Tune Fitts Law flick threshold filtering", isCompleted: false)
        ]
    }

    private static func defaultShelfFiles() -> [ShelfFileItem] {
        [
            ShelfFileItem(name: "Zonai_Battery_Spec.pdf", sizeDescription: "2.4 MB", fileExtension: "pdf"),
            ShelfFileItem(name: "Hyrule_Survey_Map.png", sizeDescription: "14.8 MB", fileExtension: "png")
        ]
    }
}
