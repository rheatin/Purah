// Sources/PurahCore/Store/PurahWorkspaceStore.swift
import Foundation
import AppKit
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
@MainActor
public final class PurahWorkspaceStore {
    public var pods: [SlotPod] = []
    public var activeDrawerPodId: String? = nil
    public var activeDrawerItemId: String? = nil
    public var hoveredPodId: String? = nil
    public var isDrawerPinned: Bool = false
    public var pinnedDrawerItemIds: Set<String> = []
    public var currentPreset: PodPreset = .balanced
    @available(*, deprecated, message: "Use Emil Kowalski unified physics-driven spring animations instead")
    public var animationStyle: AnimationStyle = .magneticCascade
    public var isRailsFrozen: Bool = false
    public var hotKeyShortcut: HotKeyShortcut = .defaultShortcut

    @ObservationIgnored
    private var capabilityProviders: [String: any PurahPodCapabilityProvider] = [:]

    public func registerCapabilityProvider(_ provider: any PurahPodCapabilityProvider) {
        capabilityProviders[provider.podId] = provider
    }

    public func capabilityProvider(for podId: String) -> (any PurahPodCapabilityProvider)? {
        capabilityProviders[podId]
    }

    public func toggleFreezeRails() {
        isRailsFrozen.toggle()
    }

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
            if let provider = capabilityProvider(for: pod.id), provider.hasPinnedChild(store: self) {
                return true
            }
            if pod.id == "todo" && todos.contains(where: { isItemPinned(id: $0.id) }) { return true }
            if pod.id == "calendar" && calendarEvents.contains(where: { isItemPinned(id: $0.id) }) { return true }
            if pod.id == "vitals" && vitalsEnabledMetrics.contains(where: { isItemPinned(id: "vitals-\($0.rawValue)") }) { return true }
            if pod.id == "scripts" && scriptsEnabledActions.contains(where: { isItemPinned(id: "scripts-\($0.id)") }) { return true }
        }
        return false
    }

    public func pod(forItemId id: String) -> SlotPod? {
        if let p = pods.first(where: { $0.id == id }) {
            return p
        }
        for (podId, provider) in capabilityProviders {
            if provider.ownsSubItemId(id, store: self) {
                return pods.first(where: { $0.id == podId })
            }
        }
        if id.hasPrefix("vitals-") {
            return pods.first(where: { $0.id == "vitals" })
        }
        if id.hasPrefix("scripts-") {
            return pods.first(where: { $0.id == "scripts" })
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
            return pod(forItemId: itemId)
        }
        return nil
    }

    // Decomposable Hardware Vitals settings
    public var isVitalsDecomposed: Bool = false
    public var vitalsEnabledMetrics: [VitalsMetricType] = [.cpu, .ram, .power, .disk]
    public var vitalsThresholds: VitalsColorThresholds = .init()

    // Decomposable Scripts Runway settings
    public var isScriptsDecomposed: Bool = false
    public var scriptsEnabledActionIds: [String] = []

    public var scriptsEnabledActions: [ScriptActionItem] {
        let all = ScriptRunwayService.shared.actions
        if scriptsEnabledActionIds.isEmpty {
            return all
        }
        let filtered = all.filter { scriptsEnabledActionIds.contains($0.id) }
        return filtered.isEmpty ? all : filtered
    }

    // Multi-display behavior
    public var displayTargetMode: DisplayTargetMode = .followCursor

    // Edge Trigger Mode (Hover Dwell vs Push Force - Mutually Exclusive)
    public var edgeTriggerMode: EdgeTriggerMode = .hoverDwell

    // Dynamic Attention Alert Settings
    public var alertStyle: PluginAlertStyle = .breathingBeacon
    public var dismissAlertOnHover: Bool = true
    public var isEventToastAlertEnabled: Bool = true
    public var acknowledgedAlertIds: Set<String> = []
    public var notifiedToastEventIds: Set<String> = []

    public func acknowledgeAlert(id: String) {
        acknowledgedAlertIds.insert(id)
    }

    public func isAlertAcknowledged(id: String) -> Bool {
        acknowledgedAlertIds.contains(id)
    }

    public func resetAlertAcknowledgment(id: String) {
        acknowledgedAlertIds.remove(id)
    }

    public func notifyEventAlertIfNeeded(for event: CalendarEventItem) {
        guard isEventToastAlertEnabled, !notifiedToastEventIds.contains(event.id) else { return }
        notifiedToastEventIds.insert(event.id)
        let msg = "\(event.title) is starting now"
        onCapacityWarningToast?("📅 \(msg)")
    }

    // Edge Trigger Intentionality Sensitivity & Calibration
    public var edgeTriggerSensitivity: EdgeTriggerSensitivity = .balanced
    public var customInitialDwellMs: Double = 150.0
    public var customExitGraceMs: Double = 280.0
    public var customCatchCorridorPt: Double = 50.0
    public var customPushForceThreshold: Double = 380.0
    public var customPushResistanceBarrier: Double = 40.0

    public var activeInitialDwellSeconds: Double {
        edgeTriggerSensitivity == .custom ? (customInitialDwellMs / 1000.0) : edgeTriggerSensitivity.initialDwellSeconds
    }

    public var activeDeepEdgeDwellSeconds: Double {
        edgeTriggerSensitivity == .custom ? min(customInitialDwellMs / 2000.0, 0.12) : edgeTriggerSensitivity.deepEdgeDwellSeconds
    }

    public var activeExitGraceSeconds: Double {
        edgeTriggerSensitivity == .custom ? (customExitGraceMs / 1000.0) : edgeTriggerSensitivity.exitGraceDurationSeconds
    }

    public var activeCatchCorridor: Double {
        edgeTriggerSensitivity == .custom ? customCatchCorridorPt : edgeTriggerSensitivity.overshootCatchCorridor
    }

    public var activePushForceThreshold: Double {
        edgeTriggerSensitivity == .custom ? customPushForceThreshold : edgeTriggerSensitivity.pushForceThreshold
    }

    public var activePushResistanceBarrier: Double {
        edgeTriggerSensitivity == .custom ? customPushResistanceBarrier : edgeTriggerSensitivity.pushResistanceBarrier
    }

    public func applySensitivityPreset(_ preset: EdgeTriggerSensitivity) {
        edgeTriggerSensitivity = preset
        if preset != .custom {
            customInitialDwellMs = preset.initialDwellSeconds * 1000.0
            customExitGraceMs = preset.exitGraceDurationSeconds * 1000.0
            customCatchCorridorPt = preset.overshootCatchCorridor
            customPushForceThreshold = preset.pushForceThreshold
            customPushResistanceBarrier = preset.pushResistanceBarrier
        }
        savePersistentState()
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

    // Terminal Plugin Custom Settings
    public var terminalFontFamily: String = "Auto (Nerd Font)"
    public var terminalFontSize: Double = 11.5

    public func effectiveDrawerWidth(for text: String = "", baseWidth: Double = 290.0, podId: String = "") -> CGFloat {
        if podId == "terminal" || baseWidth >= 400.0 {
            switch drawerWidthMode {
            case .fixed:
                return CGFloat(max(fixedDrawerWidth, 340.0))
            case .adaptive:
                return CGFloat(max(baseWidth, 500.0))
            }
        }
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
        if let provider = capabilityProvider(for: podId) {
            return provider.minimumDrawerHeight(store: self)
        }
        if podId == "vitals" && isVitalsDecomposed {
            let count = max(vitalsEnabledMetrics.count, 1)
            return CGFloat(count) * 56.0 + CGFloat(count - 1) * 2.5
        }
        if podId == "scripts" && isScriptsDecomposed {
            let count = max(scriptsEnabledActions.count, 1)
            return CGFloat(count) * 56.0 + CGFloat(count - 1) * 2.5
        }
        switch podId {
        case "vitals": return 300.0
        case "scripts": return 160.0
        case "terminal": return 350.0
        case "shelf": return 130.0
        case "notes": return 130.0
        case "music": return 110.0
        case "calendar": return 150.0
        case "todo": return 150.0
        default: return 120.0
        }
    }

    // MARK: - Rail Capacity & Ergonomic Height Budget
    public func totalRequiredHeight(for edge: MountEdge) -> CGFloat {
        let edgePods = pods.filter { $0.edge == edge && $0.isEnabled }
        guard !edgePods.isEmpty else { return 0 }
        let gap: CGFloat = 10.0
        var total: CGFloat = CGFloat(edgePods.count - 1) * gap
        for pod in edgePods {
            total += minimumDrawerHeight(for: pod.id)
        }
        return total
    }

    public func availableScreenHeight(for edge: MountEdge) -> CGFloat {
        let screens = NSScreen.screens
        let mainScreen = NSScreen.main ?? screens.first
        guard let screen = mainScreen else { return 850.0 }
        return max(screen.visibleFrame.height - 30.0, 400.0)
    }

    public func capacityRatio(for edge: MountEdge) -> Double {
        let avail = availableScreenHeight(for: edge)
        guard avail > 0 else { return 0.0 }
        let required = totalRequiredHeight(for: edge)
        return Double(required / avail)
    }

    public func isRailOverloaded(edge: MountEdge) -> Bool {
        capacityRatio(for: edge) > 1.0
    }

    public var onCapacityWarningToast: ((String) -> Void)?
    public var onLocalMouseMove: (@MainActor (NSEvent) -> Void)?
    private var lastCapacityAlertTime: Date?

    public func notifyCapacityWarningIfNeeded() {
        let now = Date()
        if let last = lastCapacityAlertTime, now.timeIntervalSince(last) < 6.0 {
            return
        }
        if isRailOverloaded(edge: .left) {
            lastCapacityAlertTime = now
            let req = Int(totalRequiredHeight(for: .left))
            let avail = Int(availableScreenHeight(for: .left))
            onCapacityWarningToast?("⚠️ Left rail capacity overload (\(req)pt / \(avail)pt available). Consider moving pods to the right rail.")
        } else if isRailOverloaded(edge: .right) {
            lastCapacityAlertTime = now
            let req = Int(totalRequiredHeight(for: .right))
            let avail = Int(availableScreenHeight(for: .right))
            onCapacityWarningToast?("⚠️ Right rail capacity overload (\(req)pt / \(avail)pt available). Consider moving pods to the left rail.")
        }
    }

    public func hasActiveOrPinnedChild(for podId: String) -> Bool {
        if let provider = capabilityProvider(for: podId) {
            return provider.hasPinnedChild(store: self) || (activeDrawerPodId == podId)
        }
        if podId == "todo" {
            return todos.contains { isItemPinned(id: $0.id) || $0.id == activeDrawerItemId }
        }
        if podId == "calendar" {
            return calendarEvents.contains { isItemPinned(id: $0.id) || $0.id == activeDrawerItemId }
        }
        if podId == "vitals" && isVitalsDecomposed {
            return vitalsEnabledMetrics.contains { isItemPinned(id: "vitals-\($0.rawValue)") || "vitals-\($0.rawValue)" == activeDrawerItemId }
        }
        if podId == "scripts" && isScriptsDecomposed {
            return scriptsEnabledActions.contains { isItemPinned(id: "scripts-\($0.id)") || "scripts-\($0.id)" == activeDrawerItemId }
        }
        return false
    }

    public func isPodDecomposed(_ id: String) -> Bool {
        if let provider = capabilityProvider(for: id) {
            return provider.isDecomposed
        }
        if id == "vitals" { return isVitalsDecomposed }
        if id == "scripts" { return isScriptsDecomposed }
        if id == "calendar" || id == "todo" { return true }
        return false
    }

    public func effectivePodSpan(for pod: SlotPod, totalHeight: CGFloat) -> CGFloat {
        let podHeight = max(pod.range.length * totalHeight, 36.0)
        if isPodDecomposed(pod.id) {
            return max(podHeight, minimumDrawerHeight(for: pod.id))
        }
        return podHeight
    }

    public func resolvedPhysicalLayout(for edge: MountEdge, totalHeight: Double) -> [ResolvedPodLayoutItem] {
        ErgonomicAutoLayoutEngine.resolvePhysicalRailLayout(
            pods: pods,
            on: edge,
            totalHeight: totalHeight,
            gap: 8.0,
            safeTop: 16.0,
            safeBottom: totalHeight - 16.0
        ) { [weak self] pod in
            guard let self = self else { return max(pod.range.length * totalHeight, 36.0) }
            return Double(self.effectivePodSpan(for: pod, totalHeight: CGFloat(totalHeight)))
        }
    }

    public func activeDrawerCardFrames(for edge: MountEdge, totalHeight: Double, windowWidth: Double = 580.0) -> [CGRect] {
        guard !isRailsFrozen else { return [] }
        var frames: [CGRect] = []
        let layoutItems = resolvedPhysicalLayout(for: edge, totalHeight: totalHeight)
        let corridor = activeCatchCorridor

        for item in layoutItems {
            let pod = item.pod
            let hasChild = hasActiveOrPinnedChild(for: pod.id)
            let isPodActive = (activeDrawerItemId == pod.id || activeDrawerPodId == pod.id)
            let isPodPinned = isItemPinned(id: pod.id)

            if let provider = capabilityProvider(for: pod.id),
               let subFrames = provider.activeSubItemFrames(
                   item: item,
                   store: self,
                   totalHeight: totalHeight,
                   windowWidth: windowWidth,
                   corridor: corridor
               ) {
                frames.append(contentsOf: subFrames)
                continue
            }

            // Case A: Decomposed Scripts (Precision sub-item bounding box)
            if pod.id == "scripts" && isScriptsDecomposed {
                let actions = scriptsEnabledActions
                let count = max(actions.count, 1)
                let spacing = 2.5
                let totalSpacing = spacing * Double(count - 1)
                let itemH = max((item.spanH - totalSpacing) / Double(count), 46.0)
                let cardH = max(itemH, 48.0)

                for (idx, action) in actions.enumerated() {
                    let itemId = "scripts-\(action.id)"
                    let itemActive = (activeDrawerItemId == itemId)
                    let itemPinned = isItemPinned(id: itemId)
                    if itemActive || itemPinned {
                        let itemTop = item.startY + Double(idx) * (itemH + spacing)
                        let itemBottom = itemTop + cardH
                        let maxAllowedY = totalHeight - 12.0
                        let shift = itemActive ? max(itemBottom - maxAllowedY, 0.0) : 0.0
                        let effTop = itemTop - shift

                        let appKitTop = totalHeight - effTop
                        let appKitBottom = appKitTop - cardH
                        let minY = max(appKitBottom - 6.0, 0.0)
                        let maxY = min(appKitTop + 6.0, totalHeight)

                        let drawerW = min(effectiveDrawerWidth(for: action.name, baseWidth: 280.0) + corridor, windowWidth)
                        let x = (edge == .right) ? (windowWidth - drawerW) : 0.0
                        frames.append(CGRect(x: x, y: minY, width: drawerW, height: maxY - minY))
                    }
                }
                continue
            }

            // Case B: Decomposed Vitals (Precision sub-item bounding box)
            if pod.id == "vitals" && isVitalsDecomposed {
                let metrics = vitalsEnabledMetrics
                let count = max(metrics.count, 1)
                let spacing = 2.5
                let totalSpacing = spacing * Double(count - 1)
                let itemH = max((item.spanH - totalSpacing) / Double(count), 46.0)
                let cardH = max(itemH, 48.0)

                for (idx, metric) in metrics.enumerated() {
                    let itemId = "vitals-\(metric.rawValue)"
                    let itemActive = (activeDrawerItemId == itemId)
                    let itemPinned = isItemPinned(id: itemId)
                    if itemActive || itemPinned {
                        let itemTop = item.startY + Double(idx) * (itemH + spacing)
                        let itemBottom = itemTop + cardH
                        let maxAllowedY = totalHeight - 12.0
                        let shift = itemActive ? max(itemBottom - maxAllowedY, 0.0) : 0.0
                        let effTop = itemTop - shift

                        let appKitTop = totalHeight - effTop
                        let appKitBottom = appKitTop - cardH
                        let minY = max(appKitBottom - 6.0, 0.0)
                        let maxY = min(appKitTop + 6.0, totalHeight)

                        let drawerW = min(effectiveDrawerWidth(baseWidth: 280.0) + corridor, windowWidth)
                        let x = (edge == .right) ? (windowWidth - drawerW) : 0.0
                        frames.append(CGRect(x: x, y: minY, width: drawerW, height: maxY - minY))
                    }
                }
                continue
            }

            // Case C: Stepped Calendar (Precision event bounding box)
            if pod.id == "calendar" {
                let events = calendarEvents
                let count = max(events.count, 1)
                let spacing = 2.5
                let totalSpacing = spacing * Double(count - 1)
                let itemH = max((item.spanH - totalSpacing) / Double(count), 26.0)
                let cardH = max(itemH, 34.0)

                var matchedSubItem = false
                for (idx, event) in events.enumerated() {
                    let itemActive = (activeDrawerItemId == event.id)
                    let itemPinned = isItemPinned(id: event.id)
                    if itemActive || itemPinned {
                        matchedSubItem = true
                        let itemTop = item.startY + Double(idx) * (itemH + spacing)
                        let appKitTop = totalHeight - itemTop
                        let appKitBottom = appKitTop - cardH
                        let minY = max(appKitBottom - 6.0, 0.0)
                        let maxY = min(appKitTop + 6.0, totalHeight)

                        let baseW = event.url != nil ? 310.0 : 280.0
                        let drawerW = min(effectiveDrawerWidth(for: event.title, baseWidth: baseW) + corridor, windowWidth)
                        let x = (edge == .right) ? (windowWidth - drawerW) : 0.0
                        frames.append(CGRect(x: x, y: minY, width: drawerW, height: maxY - minY))
                    }
                }

                if !matchedSubItem && (isPodActive || isPodPinned || hasChild) {
                    let topOfPodY = totalHeight - item.startY
                    let bottomOfPodY = topOfPodY - item.spanH
                    let minY = max(bottomOfPodY - 6.0, 0.0)
                    let maxY = min(topOfPodY + 6.0, totalHeight)
                    let drawerW = min(effectiveDrawerWidth(baseWidth: pod.drawerWidth) + corridor, windowWidth)
                    let x = (edge == .right) ? (windowWidth - drawerW) : 0.0
                    frames.append(CGRect(x: x, y: minY, width: drawerW, height: maxY - minY))
                }
                continue
            }

            // Case D: Stepped Todo (Precision task bounding box)
            if pod.id == "todo" {
                let items = todos
                let count = max(items.count, 1)
                let spacing = 2.5
                let totalSpacing = spacing * Double(count - 1)
                let itemH = max((item.spanH - totalSpacing) / Double(count), 24.0)
                let cardH = max(itemH, 30.0)

                var matchedSubItem = false
                for (idx, todo) in items.enumerated() {
                    let itemActive = (activeDrawerItemId == todo.id)
                    let itemPinned = isItemPinned(id: todo.id)
                    if itemActive || itemPinned {
                        matchedSubItem = true
                        let itemTop = item.startY + Double(idx) * (itemH + spacing)
                        let appKitTop = totalHeight - itemTop
                        let appKitBottom = appKitTop - cardH
                        let minY = max(appKitBottom - 6.0, 0.0)
                        let maxY = min(appKitTop + 6.0, totalHeight)

                        let drawerW = min(effectiveDrawerWidth(for: todo.title, baseWidth: 260.0) + corridor, windowWidth)
                        let x = (edge == .right) ? (windowWidth - drawerW) : 0.0
                        frames.append(CGRect(x: x, y: minY, width: drawerW, height: maxY - minY))
                    }
                }

                if !matchedSubItem && (isPodActive || isPodPinned || hasChild) {
                    let topOfPodY = totalHeight - item.startY
                    let bottomOfPodY = topOfPodY - item.spanH
                    let minY = max(bottomOfPodY - 6.0, 0.0)
                    let maxY = min(topOfPodY + 6.0, totalHeight)
                    let drawerW = min(effectiveDrawerWidth(baseWidth: pod.drawerWidth) + corridor, windowWidth)
                    let x = (edge == .right) ? (windowWidth - drawerW) : 0.0
                    frames.append(CGRect(x: x, y: minY, width: drawerW, height: maxY - minY))
                }
                continue
            }

            // Case E: Full-pod Composite Drawers (Music, Shelf, Notes, and custom plugins)
            if isPodPinned || isPodActive || hasChild {
                let topOfPodY = totalHeight - item.startY
                let bottomOfPodY = topOfPodY - item.spanH
                let minY = max(bottomOfPodY - 6.0, 0.0)
                let maxY = min(topOfPodY + 6.0, totalHeight)

                let drawerW = min(effectiveDrawerWidth(baseWidth: pod.drawerWidth, podId: pod.id) + corridor, windowWidth)
                let x = (edge == .right) ? (windowWidth - drawerW) : 0.0
                frames.append(CGRect(x: x, y: minY, width: drawerW, height: maxY - minY))
            }
        }
        return frames
    }

    public func defaultColorHex(for podId: String) -> String {
        switch podId {
        case "calendar": return "#FF5A60" // Coral Red
        case "todo": return "#FF9E0A"     // Amber Gold
        case "music": return "#FF2D55"    // Neon Magenta
        case "vitals": return "#00E5A3"   // Emerald Green
        case "terminal": return "#00F5D4" // Cyber Cyan
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

        if defaults.object(forKey: "purah.hotkey.keyCode") != nil {
            let code = UInt32(defaults.integer(forKey: "purah.hotkey.keyCode"))
            let mods = UInt32(defaults.integer(forKey: "purah.hotkey.modifiers"))
            self.hotKeyShortcut = HotKeyShortcut(keyCode: code, modifiers: mods)
        }

        if defaults.object(forKey: "purah.vitals.isDecomposed") != nil {
            self.isVitalsDecomposed = defaults.bool(forKey: "purah.vitals.isDecomposed")
        }
        if let metricsArr = defaults.stringArray(forKey: "purah.vitals.enabledMetrics") {
            let parsed = metricsArr.compactMap { VitalsMetricType(rawValue: $0) }
            if !parsed.isEmpty {
                self.vitalsEnabledMetrics = parsed
            }
        }
        if let data = defaults.data(forKey: "purah.vitals.thresholds"),
           let thresholds = try? JSONDecoder().decode(VitalsColorThresholds.self, from: data) {
            self.vitalsThresholds = thresholds
        }

        self.isScriptsDecomposed = defaults.bool(forKey: "purah.scripts.isDecomposed")
        if let actions = defaults.stringArray(forKey: "purah.scripts.enabledActionIds") {
            self.scriptsEnabledActionIds = actions
        } else {
            self.scriptsEnabledActionIds = ScriptRunwayService.shared.actions.map(\.id)
        }

        if let modeStr = defaults.string(forKey: "purah.edgeTriggerMode"),
           let mode = EdgeTriggerMode(rawValue: modeStr) {
            self.edgeTriggerMode = mode
        }
        if let alertStr = defaults.string(forKey: "purah.alertStyle"),
           let style = PluginAlertStyle(rawValue: alertStr) {
            self.alertStyle = style
        }
        if defaults.object(forKey: "purah.dismissAlertOnHover") != nil {
            self.dismissAlertOnHover = defaults.bool(forKey: "purah.dismissAlertOnHover")
        }
        if defaults.object(forKey: "purah.isEventToastAlertEnabled") != nil {
            self.isEventToastAlertEnabled = defaults.bool(forKey: "purah.isEventToastAlertEnabled")
        }

        if let dispModeStr = defaults.string(forKey: "purah.displayTargetMode"),
           let dispMode = DisplayTargetMode(rawValue: dispModeStr) {
            self.displayTargetMode = dispMode
        }

        if let sensStr = defaults.string(forKey: "purah.edgeTriggerSensitivity"),
           let sens = EdgeTriggerSensitivity(rawValue: sensStr) {
            self.edgeTriggerSensitivity = sens
        }
        let dwellMs = defaults.double(forKey: "purah.customInitialDwellMs")
        if dwellMs > 0 { self.customInitialDwellMs = dwellMs }
        let graceMs = defaults.double(forKey: "purah.customExitGraceMs")
        if graceMs > 0 { self.customExitGraceMs = graceMs }
        let corridorPt = defaults.double(forKey: "purah.customCatchCorridorPt")
        if corridorPt > 0 { self.customCatchCorridorPt = corridorPt }
        let pushForce = defaults.double(forKey: "purah.customPushForceThreshold")
        if pushForce > 0 { self.customPushForceThreshold = pushForce }
        let barrier = defaults.double(forKey: "purah.customPushResistanceBarrier")
        if barrier >= 15.0 && barrier <= 150.0 {
            self.customPushResistanceBarrier = barrier
        } else {
            self.customPushResistanceBarrier = 40.0
        }

        if let font = defaults.string(forKey: "purah.terminal.fontFamily"), !font.isEmpty {
            self.terminalFontFamily = font
        }
        let termSize = defaults.double(forKey: "purah.terminal.fontSize")
        if termSize >= 9.0 && termSize <= 24.0 {
            self.terminalFontSize = termSize
        }
    }

    public func savePersistentState() {
        let defaults = UserDefaults.standard
        defaults.set(terminalFontFamily, forKey: "purah.terminal.fontFamily")
        defaults.set(terminalFontSize, forKey: "purah.terminal.fontSize")
        defaults.set(quickNote.text, forKey: "purah.quickNote.text")
        defaults.set(quickNote.lastModified, forKey: "purah.quickNote.lastModified")
        defaults.set(customPodColors, forKey: "purah.customPodColors")
        defaults.set(drawerWidthMode.rawValue, forKey: "purah.drawerWidthMode")
        defaults.set(fixedDrawerWidth, forKey: "purah.fixedDrawerWidth")
        defaults.set(railBarWidth, forKey: "purah.railBarWidth")
        defaults.set(currentPreset.rawValue, forKey: "purah.currentPreset")
        defaults.set(Int(hotKeyShortcut.keyCode), forKey: "purah.hotkey.keyCode")
        defaults.set(Int(hotKeyShortcut.modifiers), forKey: "purah.hotkey.modifiers")
        defaults.set(isVitalsDecomposed, forKey: "purah.vitals.isDecomposed")
        defaults.set(vitalsEnabledMetrics.map { $0.rawValue }, forKey: "purah.vitals.enabledMetrics")
        if let data = try? JSONEncoder().encode(vitalsThresholds) {
            defaults.set(data, forKey: "purah.vitals.thresholds")
        }
        defaults.set(isScriptsDecomposed, forKey: "purah.scripts.isDecomposed")
        defaults.set(scriptsEnabledActionIds, forKey: "purah.scripts.enabledActionIds")
        defaults.set(displayTargetMode.rawValue, forKey: "purah.displayTargetMode")
        defaults.set(edgeTriggerMode.rawValue, forKey: "purah.edgeTriggerMode")
        defaults.set(alertStyle.rawValue, forKey: "purah.alertStyle")
        defaults.set(dismissAlertOnHover, forKey: "purah.dismissAlertOnHover")
        defaults.set(isEventToastAlertEnabled, forKey: "purah.isEventToastAlertEnabled")
        defaults.set(edgeTriggerSensitivity.rawValue, forKey: "purah.edgeTriggerSensitivity")
        defaults.set(customInitialDwellMs, forKey: "purah.customInitialDwellMs")
        defaults.set(customExitGraceMs, forKey: "purah.customExitGraceMs")
        defaults.set(customCatchCorridorPt, forKey: "purah.customCatchCorridorPt")
        defaults.set(customPushForceThreshold, forKey: "purah.customPushForceThreshold")
        defaults.set(customPushResistanceBarrier, forKey: "purah.customPushResistanceBarrier")
        notifyCapacityWarningIfNeeded()
    }

    public func autoLayoutAll() {
        let left = ErgonomicAutoLayoutEngine.layout(pods: pods, on: .left)
        let right = ErgonomicAutoLayoutEngine.layout(pods: pods, on: .right)
        let map = Dictionary(uniqueKeysWithValues: (left + right).map { ($0.id, $0) })
        pods = pods.map { map[$0.id] ?? $0 }
        notifyCapacityWarningIfNeeded()
    }

    public func togglePodEnabled(id: String) {
        guard let index = pods.firstIndex(where: { $0.id == id }) else { return }
        pods[index].isEnabled.toggle()
        autoLayoutAll()
    }

    public func fillRail(podId: String) {
        guard pods.contains(where: { $0.id == podId }) else { return }
        // 让当前 Pod 占满整条轨道的有效安全区间 (0.02 ~ 0.98)
        let safeSpan = 0.96
        let newRange = NormalizedRange(start: 0.02, length: safeSpan)
        updatePodRange(id: podId, newRange: newRange)
    }

    public func applyPreset(_ preset: PodPreset) {
        currentPreset = preset
        switch preset {
        case .balanced:
            // Left Rail: Vitals, Shelf, Notes (~480pt budget)
            setPod(id: "vitals", edge: .left, zone: .glance, weight: 30, isEnabled: true)
            setPod(id: "shelf", edge: .left, zone: .goldenAction, weight: 35, isEnabled: true)
            setPod(id: "notes", edge: .left, zone: .quickFlick, weight: 30, isEnabled: true)

            // Right Rail: Calendar, Todo, Scripts, Music (~600pt budget)
            setPod(id: "calendar", edge: .right, zone: .goldenAction, weight: 40, isEnabled: true)
            setPod(id: "todo", edge: .right, zone: .goldenAction, weight: 35, isEnabled: true)
            setPod(id: "scripts", edge: .right, zone: .quickFlick, weight: 25, isEnabled: true)
            setPod(id: "music", edge: .right, zone: .quickFlick, weight: 20, isEnabled: true)

        case .sprintProductivity:
            // Left Rail: Scripts Runway, Notes, Shelf (~440pt budget)
            setPod(id: "scripts", edge: .left, zone: .goldenAction, weight: 45, isEnabled: true)
            setPod(id: "notes", edge: .left, zone: .goldenAction, weight: 35, isEnabled: true)
            setPod(id: "shelf", edge: .left, zone: .quickFlick, weight: 25, isEnabled: true)

            // Right Rail: Tasks, Calendar, Vitals (~520pt budget)
            setPod(id: "todo", edge: .right, zone: .goldenAction, weight: 45, isEnabled: true)
            setPod(id: "calendar", edge: .right, zone: .goldenAction, weight: 40, isEnabled: true)
            setPod(id: "vitals", edge: .right, zone: .glance, weight: 25, isEnabled: true)

            // Mute music in sprint focus
            setPod(id: "music", edge: .right, zone: .quickFlick, weight: 10, isEnabled: false)

        case .immersiveMultimedia:
            // Left Rail: Showcase Music & Notes (~250pt budget, large stage for vinyl)
            setPod(id: "music", edge: .left, zone: .goldenAction, weight: 65, isEnabled: true)
            setPod(id: "notes", edge: .left, zone: .quickFlick, weight: 25, isEnabled: true)
            setPod(id: "shelf", edge: .left, zone: .quickFlick, weight: 10, isEnabled: false)

            // Right Rail: Calendar & Vitals (~360pt budget)
            setPod(id: "calendar", edge: .right, zone: .glance, weight: 50, isEnabled: true)
            setPod(id: "vitals", edge: .right, zone: .glance, weight: 30, isEnabled: true)

            // Disable distracting productivity tasks
            setPod(id: "todo", edge: .right, zone: .quickFlick, weight: 10, isEnabled: false)
            setPod(id: "scripts", edge: .right, zone: .quickFlick, weight: 10, isEnabled: false)
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

    private func setPod(id: String, edge: MountEdge, zone: ZoneType, weight: Double, isEnabled: Bool = true) {
        if let idx = pods.firstIndex(where: { $0.id == id }) {
            pods[idx].edge = edge
            pods[idx].preferredZone = zone
            pods[idx].ergonomicWeight = weight
            pods[idx].isEnabled = isEnabled
        }
    }

    public static func defaultPods() -> [SlotPod] {
        [
            SlotPod(id: "calendar", name: "Calendar Timeline", systemIcon: "calendar", edge: .right, range: .init(start: 0.15, length: 0.35), ambientStyle: .progressTimeline, preferredZone: .goldenAction, ergonomicWeight: 40, minLength: 0.15),
            SlotPod(id: "todo", name: "Todo Checklist", systemIcon: "checklist", edge: .right, range: .init(start: 0.52, length: 0.25), ambientStyle: .segmentGauge, preferredZone: .goldenAction, ergonomicWeight: 35, minLength: 0.15),
            SlotPod(id: "music", name: "Music Waveform", systemIcon: "waveform", edge: .right, range: .init(start: 0.79, length: 0.14), ambientStyle: .waveLevelMeter, preferredZone: .quickFlick, ergonomicWeight: 25, minLength: 0.12),
            SlotPod(id: "vitals", name: "Hardware Vitals", systemIcon: "waveform.path.ecg", edge: .left, range: .init(start: 0.08, length: 0.26), ambientStyle: .progressTimeline, preferredZone: .glance, ergonomicWeight: 35, minLength: 0.22),
            SlotPod(id: "shelf", name: "Temporary Shelf", systemIcon: "tray.fill", edge: .left, range: .init(start: 0.36, length: 0.20), ambientStyle: .ghostDot, preferredZone: .goldenAction, ergonomicWeight: 35, minLength: 0.16),
            SlotPod(id: "notes", name: "Quick Notes", systemIcon: "note.text", edge: .left, range: .init(start: 0.58, length: 0.18), ambientStyle: .ghostDot, preferredZone: .goldenAction, ergonomicWeight: 30, minLength: 0.15),
            SlotPod(id: "scripts", name: "Script Runway", systemIcon: "terminal.fill", edge: .left, range: .init(start: 0.78, length: 0.16), ambientStyle: .ghostDot, preferredZone: .quickFlick, ergonomicWeight: 25, minLength: 0.16),
            SlotPod(id: "terminal", name: "Terminal", systemIcon: "apple.terminal.fill", edge: .left, range: .init(start: 0.94, length: 0.04), ambientStyle: .ghostDot, preferredZone: .quickFlick, ergonomicWeight: 20, minLength: 0.12, isEnabled: false, drawerWidth: 500)
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
            CalendarEventItem(id: "default-event-1", title: "Architecture Review", location: "Central Workshop", startTime: d1, endTime: d2),
            CalendarEventItem(id: "default-event-2", title: "Environmental Monitoring", location: "Observation Station", startTime: d3, endTime: d4)
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
            ShelfFileItem(name: "macOS_Workflow_Spec.pdf", sizeDescription: "2.4 MB", fileExtension: "pdf"),
            ShelfFileItem(name: "Architecture_Diagram.png", sizeDescription: "4.8 MB", fileExtension: "png")
        ]
    }
}
