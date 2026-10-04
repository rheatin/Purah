// Sources/PurahCore/Store/PurahWorkspaceStore.swift
import Foundation
import Observation

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

    // 真实系统应用同步标志与细粒度时间/分类范围
    public var isUsingRealCalendar: Bool = false
    public var isUsingRealReminders: Bool = false
    public var calendarScope: CalendarTimeScope = .today
    public var remindersScope: RemindersScope = .allIncomplete
    public var isEventGlowAlertEnabled: Bool = true
    public var isMusicWaveformAnimationEnabled: Bool = true

    // 用户自定义导轨宽度 (4px ~ 16px) 与功能区色彩
    public var railBarWidth: Double = 8.0
    public var customPodColors: [String: String] = [:]

    public func defaultColorHex(for podId: String) -> String {
        switch podId {
        case "calendar": return "#FF5A60" // 珊瑚红橙
        case "todo": return "#FF9E0A"     // 活力琥珀金
        case "music": return "#FF2D55"    // 霓虹品红
        case "vitals": return "#00E5A3"   // 性能翠绿
        case "shelf": return "#2ED573"    // 极客薄荷绿
        case "notes": return "#FFD166"    // 便签金黄
        case "scripts": return "#6C5CE7"  // 终端曜石电紫
        default: return "#00F5D4"
        }
    }

    public func podColorHex(for podId: String) -> String {
        customPodColors[podId] ?? defaultColorHex(for: podId)
    }

    public func setPodColorHex(podId: String, hex: String) {
        customPodColors[podId] = hex
    }

    // 内置 Pod 业务数据
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
        autoLayoutAll()
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
            SlotPod(id: "calendar", name: "日程时间标尺", systemIcon: "calendar", edge: .right, range: .init(start: 0.15, length: 0.35), ambientStyle: .progressTimeline, preferredZone: .goldenAction, ergonomicWeight: 40, minLength: 0.12),
            SlotPod(id: "todo", name: "待办指示标", systemIcon: "checklist", edge: .right, range: .init(start: 0.52, length: 0.25), ambientStyle: .segmentGauge, preferredZone: .goldenAction, ergonomicWeight: 35, minLength: 0.12),
            SlotPod(id: "music", name: "音乐律动波", systemIcon: "waveform", edge: .right, range: .init(start: 0.79, length: 0.12), ambientStyle: .waveLevelMeter, preferredZone: .quickFlick, ergonomicWeight: 25, minLength: 0.08),
            SlotPod(id: "vitals", name: "性能热态脉搏", systemIcon: "waveform.path.ecg", edge: .left, range: .init(start: 0.10, length: 0.16), ambientStyle: .progressTimeline, preferredZone: .glance, ergonomicWeight: 30, minLength: 0.10),
            SlotPod(id: "shelf", name: "临时暂存架", systemIcon: "tray.fill", edge: .left, range: .init(start: 0.28, length: 0.30), ambientStyle: .ghostDot, preferredZone: .goldenAction, ergonomicWeight: 40, minLength: 0.12),
            SlotPod(id: "notes", name: "灵感草稿纸", systemIcon: "note.text", edge: .left, range: .init(start: 0.60, length: 0.18), ambientStyle: .ghostDot, preferredZone: .goldenAction, ergonomicWeight: 30, minLength: 0.10),
            SlotPod(id: "scripts", name: "瞬时脚本跑道", systemIcon: "terminal.fill", edge: .left, range: .init(start: 0.80, length: 0.14), ambientStyle: .ghostDot, preferredZone: .quickFlick, ergonomicWeight: 25, minLength: 0.08)
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
            CalendarEventItem(title: "Purah Pad 架构评审会议", location: "希卡中央工坊", startTime: d1, endTime: d2),
            CalendarEventItem(title: "海拉鲁空岛环境监测研讨", location: "初始空岛观测站", startTime: d3, endTime: d4)
        ]
    }

    private static func defaultTodos() -> [TodoItem] {
        [
            TodoItem(title: "校准左侧边缘触觉传感器", isCompleted: true),
            TodoItem(title: "更新希卡符文能量波形图", isCompleted: false),
            TodoItem(title: "测试多显示器自适应流式排布", isCompleted: false),
            TodoItem(title: "集成 Fitts 定律盲甩阈值过滤", isCompleted: false)
        ]
    }

    private static func defaultShelfFiles() -> [ShelfFileItem] {
        [
            ShelfFileItem(name: "Zonai_Battery_Spec.pdf", sizeDescription: "2.4 MB", fileExtension: "pdf"),
            ShelfFileItem(name: "Hyrule_Survey_Map.png", sizeDescription: "14.8 MB", fileExtension: "png")
        ]
    }
}
