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
    public var isRailsFrozen: Bool = false
    public var hotKeyShortcut: HotKeyShortcut = .defaultShortcut

    @ObservationIgnored
    public var onRequestOpenPluginSettings: (@MainActor (String) -> Void)?

    public func openPluginSettings(id: String) {
        onRequestOpenPluginSettings?(id)
    }

    @ObservationIgnored
    private var capabilityProviders: [String: any PurahPodCapabilityProvider] = [:]

    @ObservationIgnored
    private var _marketManager: PluginMarketManager?

    public var marketManager: PluginMarketManager {
        if let existing = _marketManager {
            return existing
        }
        let manager = PluginMarketManager(store: self)
        _marketManager = manager
        return manager
    }

    public func setMarketManager(_ manager: PluginMarketManager) {
        self._marketManager = manager
    }

    public func registerCapabilityProvider(_ provider: any PurahPodCapabilityProvider) {
        capabilityProviders[provider.podId] = provider
    }

    public func unregisterCapabilityProvider(for podId: String) {
        capabilityProviders.removeValue(forKey: podId)
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
        if let pod = pods.first(where: { $0.id == podId }) {
            onRequestExpandCanvas?(pod.edge)
        }
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

    public func postToastNotification(id: String, message: String) {
        guard isEventToastAlertEnabled, !notifiedToastEventIds.contains(id) else { return }
        notifiedToastEventIds.insert(id)
        onCapacityWarningToast?(message)
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
    public var calendarMaxRailEvents: Int = 4
    public var todoMaxRailTasks: Int = 6
    public var clipboardMaxRailItems: Int = 4
    public var isMusicWaveformAnimationEnabled: Bool = true
    public var isEventGlowAlertEnabled: Bool = true

    // User-configurable rail width (4px ~ 16px) and drawer extrusion settings
    public var railBarWidth: Double = 8.0
    public var drawerWidthMode: DrawerWidthMode = .fixed
    public var fixedDrawerWidth: Double = 290.0 // Bounds: 220px ~ 330px
    public var customPodColors: [String: String] = [:]

    public func effectiveDrawerWidth(for text: String = "", baseWidth: Double = 290.0, podId: String = "") -> CGFloat {
        let resolvedPodId: String = {
            if !podId.isEmpty { return podId }
            let lower = text.lowercased()
            if let matched = pods.first(where: { lower.contains($0.id.lowercased()) || lower.contains($0.name.lowercased()) }) {
                return matched.id
            }
            return ""
        }()

        // 1. Autonomous Plugin Adaptive Width Resolution (Open-Closed Principle)
        if !resolvedPodId.isEmpty,
           let provider = capabilityProvider(for: resolvedPodId),
           let pluginAdaptiveWidth = provider.adaptiveDrawerWidth(store: self) {
            switch drawerWidthMode {
            case .fixed:
                return CGFloat(max(fixedDrawerWidth, Double(pluginAdaptiveWidth)))
            case .adaptive:
                return pluginAdaptiveWidth
            }
        }

        // 2. Base Fallback Estimation (Text length and baseline fallback)
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
        return 120.0
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
    public var onPodEnabledChanged: (@MainActor (String, Bool) -> Void)?
    public var onWindowsRebuildNeeded: (@MainActor () -> Void)?
    public var onRequestExpandCanvas: (@MainActor (MountEdge) -> Void)?
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
        return false
    }

    public func isPodDecomposed(_ id: String) -> Bool {
        capabilityProvider(for: id)?.isDecomposed(store: self) ?? false
    }

    public func effectivePodSpan(for pod: SlotPod, totalHeight: CGFloat) -> CGFloat {
        let podHeight = max(pod.range.length * totalHeight, 36.0)
        let minReserved = minimumDrawerHeight(for: pod.id)
        return max(podHeight, minReserved)
    }

    @ObservationIgnored
    private var cachedResolvedLayouts: [MountEdge: (height: Double, podsCount: Int, items: [ResolvedPodLayoutItem], timestamp: Double)] = [:]

    public func invalidateLayoutCache() {
        cachedResolvedLayouts.removeAll()
    }

    public func resolvedPhysicalLayout(for edge: MountEdge, totalHeight: Double) -> [ResolvedPodLayoutItem] {
        let now = Date().timeIntervalSinceReferenceDate
        if let cached = cachedResolvedLayouts[edge],
           abs(cached.height - totalHeight) < 0.5,
           cached.podsCount == pods.count,
           (now - cached.timestamp) < 0.05 {
            return cached.items
        }

        let items = ErgonomicAutoLayoutEngine.resolvePhysicalRailLayout(
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

        cachedResolvedLayouts[edge] = (height: totalHeight, podsCount: pods.count, items: items, timestamp: now)
        return items
    }

    public func activeDrawerCardFrames(for edge: MountEdge, totalHeight: Double, windowWidth: Double = 580.0) -> [CGRect] {
        guard !isRailsFrozen else { return [] }
        var frames: [CGRect] = []
        let layoutItems = resolvedPhysicalLayout(for: edge, totalHeight: totalHeight)
        let corridor = activeCatchCorridor

        for item in layoutItems {
            let pod = item.pod
            let isPodActive = (activeDrawerItemId == pod.id || activeDrawerPodId == pod.id)
            let isPodPinned = isItemPinned(id: pod.id)
            let hasChild = hasActiveOrPinnedChild(for: pod.id)

            // High-performance prune: Skip completely idle pods that have neither active nor pinned drawers
            guard isPodActive || isPodPinned || hasChild else { continue }

            if isPodDecomposed(pod.id), let provider = capabilityProvider(for: pod.id) {
                let rawCount = provider.subItemCount(store: self)
                let minChipH = 20.0
                let spacing = 2.5
                let maxAllowed = max(Int((item.spanH + spacing) / (minChipH + spacing)), 1)
                let count = min(rawCount, maxAllowed)
                let safeCount = max(count, 1)
                let totalSpacing = spacing * Double(safeCount - 1)
                let maxChipH = 185.0
                let itemH = min(max((item.spanH - totalSpacing) / Double(safeCount), minChipH), maxChipH)
                let cardH = max(itemH, 44.0)

                var matchedSubItem = false
                for idx in 0..<count {
                    guard let subId = provider.subItemId(at: idx, store: self) else { continue }
                    let itemActive = (activeDrawerItemId == subId)
                    let itemPinned = isItemPinned(id: subId)

                    if itemActive || itemPinned {
                        matchedSubItem = true
                        let itemTop = item.startY + Double(idx) * (itemH + spacing)
                        let itemBottom = itemTop + cardH
                        let maxAllowedY = totalHeight - 12.0
                        let shift = itemActive ? max(itemBottom - maxAllowedY, 0.0) : 0.0
                        let effTop = itemTop - shift

                        let appKitTop = totalHeight - effTop
                        let appKitBottom = appKitTop - cardH
                        let minY = max(appKitBottom - 10.0, 0.0)
                        let maxY = min(appKitTop + 10.0, totalHeight)

                        let subTitle = provider.subItemTitle(at: idx, store: self) ?? ""
                        let drawerW = min(effectiveDrawerWidth(for: subTitle, baseWidth: pod.drawerWidth, podId: pod.id) + corridor, windowWidth)
                        let x = (edge == .right) ? (windowWidth - drawerW) : 0.0
                        frames.append(CGRect(x: x, y: minY, width: drawerW, height: maxY - minY))
                    }
                }

                if !matchedSubItem && (isPodActive || isPodPinned || hasChild) {
                    let topOfPodY = totalHeight - item.startY
                    let bottomOfPodY = topOfPodY - item.spanH
                    let minY = max(bottomOfPodY - 6.0, 0.0)
                    let maxY = min(topOfPodY + 6.0, totalHeight)
                    let drawerW = min(effectiveDrawerWidth(baseWidth: pod.drawerWidth, podId: pod.id) + corridor, windowWidth)
                    let x = (edge == .right) ? (windowWidth - drawerW) : 0.0
                    frames.append(CGRect(x: x, y: minY, width: drawerW, height: maxY - minY))
                }
                continue
            }

            // Full-pod Composite Drawers (Music, Shelf, Notes, and custom plugins)
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
        pods.first(where: { $0.id == podId })?.defaultColorHex ?? "#00F5D4"
    }

    public func podColorHex(for podId: String) -> String {
        customPodColors[podId] ?? defaultColorHex(for: podId)
    }

    public func setPodColorHex(podId: String, hex: String) {
        customPodColors[podId] = hex
        savePersistentState()
    }

    // Internal backing storage for compatibility shims / default capability providers
    package var _calendarEvents: [CalendarEventItem] = PurahWorkspaceStore.defaultEvents()
    package var _todos: [TodoItem] = PurahWorkspaceStore.defaultTodos()
    package var _musicTrack: MusicTrackInfo = .init()
    package var _shelfFiles: [ShelfFileItem] = PurahWorkspaceStore.defaultShelfFiles()
    package var _quickNote: NoteContent = .init()
    package var _isVitalsDecomposed: Bool {
        get {
            if UserDefaults.standard.object(forKey: "purah.vitals.isDecomposed") == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: "purah.vitals.isDecomposed")
        }
        set { UserDefaults.standard.set(newValue, forKey: "purah.vitals.isDecomposed") }
    }
    package var _vitalsEnabledMetrics: [VitalsMetricType] {
        get {
            guard let arr = UserDefaults.standard.stringArray(forKey: "purah.vitals.enabledMetrics") else {
                return [.cpu, .ram, .power, .disk]
            }
            let parsed = arr.compactMap { VitalsMetricType(rawValue: $0) }
            return parsed.isEmpty ? [.cpu, .ram, .power, .disk] : parsed
        }
        set {
            UserDefaults.standard.set(newValue.map(\.rawValue), forKey: "purah.vitals.enabledMetrics")
        }
    }
    package var _vitalsThresholds: VitalsColorThresholds {
        get {
            guard let data = UserDefaults.standard.data(forKey: "purah.vitals.thresholds"),
                  let decoded = try? JSONDecoder().decode(VitalsColorThresholds.self, from: data) else {
                return VitalsColorThresholds()
            }
            return decoded
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: "purah.vitals.thresholds")
            }
        }
    }
    package var _isScriptsDecomposed: Bool {
        get {
            if UserDefaults.standard.object(forKey: "purah.scripts.isDecomposed") == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: "purah.scripts.isDecomposed")
        }
        set { UserDefaults.standard.set(newValue, forKey: "purah.scripts.isDecomposed") }
    }
    package var _scriptsEnabledActionIds: [String] {
        get {
            UserDefaults.standard.stringArray(forKey: "purah.scripts.enabledActionIds") ?? []
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "purah.scripts.enabledActionIds")
        }
    }
    package var _terminalFontFamily: String = "Auto (Nerd Font)"
    package var _terminalFontSize: Double = 11.5

    public var scriptsEnabledActions: [ScriptActionItem] {
        let all = ScriptRunwayService.shared.actions
        let ids = _scriptsEnabledActionIds
        if ids.isEmpty {
            return all
        }
        let filtered = all.filter { ids.contains($0.id) }
        return filtered.isEmpty ? all : filtered
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

    @ObservationIgnored
    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.pods = Self.defaultPods()
        registerDefaultCapabilityProviders()
        let hasCustomPods = userDefaults.object(forKey: "purah.pods") != nil
        loadPersistentState()
        if !hasCustomPods {
            autoLayoutAll()
        } else {
            // Re-apply dynamic minLength calculation without resetting custom layout
            for idx in pods.indices {
                let pod = pods[idx]
                let screenH = max(Double(availableScreenHeight(for: pod.edge)), 400.0)
                let minPt = Double(minimumDrawerHeight(for: pod.id))
                pods[idx].minLength = max(minPt / screenH, 0.05)
            }
            invalidateLayoutCache()
        }
    }

    private func registerDefaultCapabilityProviders() {
        registerCapabilityProvider(DefaultCalendarCapabilityProvider())
        registerCapabilityProvider(DefaultTodoCapabilityProvider())
        registerCapabilityProvider(DefaultVitalsCapabilityProvider())
        registerCapabilityProvider(DefaultScriptsCapabilityProvider())
        registerCapabilityProvider(DefaultCompositeCapabilityProvider(podId: "music", minHeight: 110.0, adaptiveWidth: 360.0))
        registerCapabilityProvider(DefaultCompositeCapabilityProvider(podId: "shelf", minHeight: 130.0, adaptiveWidth: 360.0))
        registerCapabilityProvider(DefaultCompositeCapabilityProvider(podId: "notes", minHeight: 130.0, adaptiveWidth: 320.0))
        registerCapabilityProvider(DefaultCompositeCapabilityProvider(podId: "terminal", minHeight: 60.0, adaptiveWidth: 520.0))
        registerCapabilityProvider(DefaultCompositeCapabilityProvider(podId: "clipboard", minHeight: 120.0, adaptiveWidth: 380.0))
    }

    // MARK: - Local Persistence
    public static func resetToFactoryDefaults(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: "purah.pods")
        defaults.removeObject(forKey: "purah.currentPreset")
    }

    public func loadPersistentState() {
        let defaults = userDefaults

        if let data = defaults.data(forKey: "purah.pods"),
           let savedPods = try? JSONDecoder().decode([SlotPod].self, from: data),
           !savedPods.isEmpty {
            var merged = savedPods
            let savedIds = Set(savedPods.map(\.id))
            for var def in Self.defaultPods() where !savedIds.contains(def.id) {
                def.isEnabled = false
                merged.append(def)
            }
            self.pods = merged
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

        let savedMaxCal = defaults.integer(forKey: "purah.calendarMaxRailEvents")
        if savedMaxCal > 0 {
            self.calendarMaxRailEvents = savedMaxCal
        }

        let savedMaxTodo = defaults.integer(forKey: "purah.todoMaxRailTasks")
        if savedMaxTodo > 0 {
            self.todoMaxRailTasks = savedMaxTodo
        }

        let savedMaxClip = defaults.integer(forKey: "purah.clipboardMaxRailItems")
        if savedMaxClip > 0 {
            self.clipboardMaxRailItems = savedMaxClip
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
    }

    public func savePersistentState() {
        let defaults = userDefaults
        if let data = try? JSONEncoder().encode(pods) {
            defaults.set(data, forKey: "purah.pods")
        }
        defaults.set(customPodColors, forKey: "purah.customPodColors")
        defaults.set(drawerWidthMode.rawValue, forKey: "purah.drawerWidthMode")
        defaults.set(fixedDrawerWidth, forKey: "purah.fixedDrawerWidth")
        defaults.set(railBarWidth, forKey: "purah.railBarWidth")
        defaults.set(currentPreset.rawValue, forKey: "purah.currentPreset")
        defaults.set(calendarMaxRailEvents, forKey: "purah.calendarMaxRailEvents")
        defaults.set(todoMaxRailTasks, forKey: "purah.todoMaxRailTasks")
        defaults.set(clipboardMaxRailItems, forKey: "purah.clipboardMaxRailItems")
        defaults.set(Int(hotKeyShortcut.keyCode), forKey: "purah.hotkey.keyCode")
        defaults.set(Int(hotKeyShortcut.modifiers), forKey: "purah.hotkey.modifiers")
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
        defaults.synchronize()
        notifyCapacityWarningIfNeeded()
    }

    public func autoLayoutAll() {
        // Dynamically update each pod's minLength to reflect capability provider's minimum required height
        for idx in pods.indices {
            let pod = pods[idx]
            let screenH = max(Double(availableScreenHeight(for: pod.edge)), 400.0)
            let minPt = Double(minimumDrawerHeight(for: pod.id))
            pods[idx].minLength = max(minPt / screenH, 0.05)
        }

        pods = ErgonomicAutoLayoutEngine.optimizeBilateralLayout(
            pods: pods,
            reassignEdges: false,
            availableHeight: Double(availableScreenHeight(for: .left))
        )
        invalidateLayoutCache()
        savePersistentState()
        notifyCapacityWarningIfNeeded()
    }

    public func togglePodEnabled(id: String) {
        guard let index = pods.firstIndex(where: { $0.id == id }) else { return }
        let pod = pods[index]
        if !pod.isEnabled {
            // Guard minimum height: reject enabling if required height overflows screen budget
            let currentReq = totalRequiredHeight(for: pod.edge)
            let additional = minimumDrawerHeight(for: pod.id) + 10.0
            let available = availableScreenHeight(for: pod.edge)
            if (currentReq + additional) > available {
                let reqTotal = Int(currentReq + additional)
                let availInt = Int(available)
                onCapacityWarningToast?("⚠️ Insufficient rail capacity (\(reqTotal)pt / \(availInt)pt). Cannot mount \(pod.name) without squashing existing pods.")
                return
            }
            pods[index].isEnabled = true
            let screenH = max(Double(availableScreenHeight(for: pod.edge)), 400.0)
            let minPt = Double(minimumDrawerHeight(for: pod.id))
            pods[index].minLength = max(minPt / screenH, 0.05)
            if id == "clipboard" {
                SystemClipboardSyncService.shared.startListening()
            } else if id == "vitals" {
                HardwareVitalsService.shared.startMonitoring()
            } else if id == "music" {
                SystemMusicSyncService.shared.startListening(into: self)
            }
            onPodEnabledChanged?(id, true)
        } else {
            pods[index].isEnabled = false
            if id == "clipboard" {
                SystemClipboardSyncService.shared.stopListening()
            } else if id == "vitals" {
                HardwareVitalsService.shared.stopMonitoring()
            } else if id == "music" {
                SystemMusicSyncService.shared.stopListening()
                SystemMusicSyncService.shared.clearArtworkCache()
            }
            onPodEnabledChanged?(id, false)
        }
        _marketManager?.enabledPluginIds = Set(pods.filter(\.isEnabled).map(\.id))
        _marketManager?.savePersistentState()
        invalidateLayoutCache()
        savePersistentState()
        onWindowsRebuildNeeded?()
    }

    public func fillRail(podId: String) {
        guard let currentPod = pods.first(where: { $0.id == podId && $0.isEnabled }) else { return }
        let edge = currentPod.edge
        let railPods = pods.filter { $0.edge == edge && $0.isEnabled }
            .sorted { $0.range.start < $1.range.start }
        guard let currentIndex = railPods.firstIndex(where: { $0.id == podId }),
              let podIndex = pods.firstIndex(where: { $0.id == podId }) else { return }

        if currentIndex == railPods.count - 1 {
            // Last pod on the rail (e.g. Music): expand length down to 0.98 to fill all remaining space!
            let start = pods[podIndex].range.start
            let newLength = max(0.98 - start, currentPod.minLength)
            pods[podIndex].range.length = newLength
        } else {
            // Expand towards successor above/below
            let nextPod = railPods[currentIndex + 1]
            let start = pods[podIndex].range.start
            let newLength = max(nextPod.range.start - start - 0.015, currentPod.minLength)
            pods[podIndex].range.length = newLength
        }

        invalidateLayoutCache()
        savePersistentState()
        onWindowsRebuildNeeded?()
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
        let screenH = max(Double(availableScreenHeight(for: pod.edge)), 600.0)
        pods = SpringConstraintSolver.resolve(
            draggedPodId: id,
            newRange: newRange,
            allPods: pods,
            on: pod.edge,
            minRatioProvider: { [weak self] p in
                guard let self else { return p.minLength }
                let minH = Double(self.minimumDrawerHeight(for: p.id))
                return minH / screenH
            }
        )
        invalidateLayoutCache()
        savePersistentState()
        onWindowsRebuildNeeded?()
    }

    public func movePod(id: String, to edge: MountEdge) {
        guard let index = pods.firstIndex(where: { $0.id == id }) else { return }
        pods[index].edge = edge
        autoLayoutAll()
        onWindowsRebuildNeeded?()
    }

    // MARK: - Pod Reordering & Position Swapping
    public enum PodMoveDirection: Sendable {
        case up
        case down
    }

    public func canMovePod(id: String, direction: PodMoveDirection) -> Bool {
        guard let currentPod = pods.first(where: { $0.id == id && $0.isEnabled }) else { return false }
        let railPods = pods.filter { $0.edge == currentPod.edge && $0.isEnabled }
            .sorted { $0.range.start < $1.range.start }
        guard let currentIndex = railPods.firstIndex(where: { $0.id == id }) else { return false }
        switch direction {
        case .up:
            return currentIndex > 0
        case .down:
            return currentIndex < railPods.count - 1
        }
    }

    public func movePodInOrder(id: String, direction: PodMoveDirection) {
        guard let currentPod = pods.first(where: { $0.id == id && $0.isEnabled }) else { return }
        let edge = currentPod.edge
        let railPods = pods.filter { $0.edge == edge && $0.isEnabled }
            .sorted { $0.range.start < $1.range.start }

        guard let currentIndex = railPods.firstIndex(where: { $0.id == id }) else { return }

        let targetIndex: Int
        switch direction {
        case .up:
            targetIndex = currentIndex - 1
        case .down:
            targetIndex = currentIndex + 1
        }

        guard targetIndex >= 0 && targetIndex < railPods.count else { return }
        let targetPod = railPods[targetIndex]

        swapPods(id1: currentPod.id, id2: targetPod.id)
    }

    public func swapPods(id1: String, id2: String) {
        guard let idx1 = pods.firstIndex(where: { $0.id == id1 }),
              let idx2 = pods.firstIndex(where: { $0.id == id2 }) else { return }

        let p1 = pods[idx1]
        let p2 = pods[idx2]
        guard p1.edge == p2.edge else { return }

        let start1 = p1.range.start
        let start2 = p2.range.start

        if start1 < start2 {
            // p1 is above p2 -> p2 moves up, p1 moves down
            let newP2Start = start1
            let newP1Start = start1 + p2.range.length + 0.02
            pods[idx2].range.start = newP2Start
            pods[idx1].range.start = newP1Start
        } else {
            // p1 is below p2 -> p1 moves up, p2 moves down
            let newP1Start = start2
            let newP2Start = start2 + p1.range.length + 0.02
            pods[idx1].range.start = newP1Start
            pods[idx2].range.start = newP2Start
        }

        invalidateLayoutCache()
        savePersistentState()
        onWindowsRebuildNeeded?()
    }

    // MARK: - Magnetic Pod Snapping
    public enum SnapTarget: Sendable {
        case predecessor // Snap to bottom of the pod above
        case successor   // Snap to top of the pod below
        case top         // Snap to top of the rail
    }

    public func hasGapAbove(id: String) -> Bool {
        guard let currentPod = pods.first(where: { $0.id == id && $0.isEnabled }) else { return false }
        let railPods = pods.filter { $0.edge == currentPod.edge && $0.isEnabled }
            .sorted { $0.range.start < $1.range.start }
        guard let currentIndex = railPods.firstIndex(where: { $0.id == id }), currentIndex > 0 else { return false }
        let prev = railPods[currentIndex - 1]
        let gap = currentPod.range.start - (prev.range.start + prev.range.length)
        let bottomGap = (currentIndex == railPods.count - 1) ? (0.98 - (currentPod.range.start + currentPod.range.length)) : 0.0
        return gap > 0.015 || bottomGap > 0.04
    }

    public func snapPod(id: String, to target: SnapTarget) {
        guard let currentPod = pods.first(where: { $0.id == id && $0.isEnabled }) else { return }
        let edge = currentPod.edge
        let railPods = pods.filter { $0.edge == edge && $0.isEnabled }
            .sorted { $0.range.start < $1.range.start }

        guard let currentIndex = railPods.firstIndex(where: { $0.id == id }) else { return }
        guard let podIndex = pods.firstIndex(where: { $0.id == id }) else { return }

        let minGap = 0.012

        switch target {
        case .predecessor:
            if currentIndex > 0 {
                let prev = railPods[currentIndex - 1]
                let newStart = prev.range.start + prev.range.length + minGap
                pods[podIndex].range.start = min(newStart, 0.96 - currentPod.range.length)
                // If this is the last pod on the rail, stretch length down to fill all remaining space to 0.98!
                if currentIndex == railPods.count - 1 {
                    let availableDown = max(0.98 - pods[podIndex].range.start, currentPod.minLength)
                    pods[podIndex].range.length = availableDown
                }
            } else {
                pods[podIndex].range.start = 0.02
            }
        case .successor:
            if currentIndex < railPods.count - 1 {
                let next = railPods[currentIndex + 1]
                let newStart = next.range.start - currentPod.range.length - minGap
                pods[podIndex].range.start = max(newStart, 0.02)
            }
        case .top:
            pods[podIndex].range.start = 0.02
        }

        invalidateLayoutCache()
        savePersistentState()
        onWindowsRebuildNeeded?()
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
            SlotPod(id: "calendar", name: "Calendar Timeline", systemIcon: "calendar", edge: .right, range: .init(start: 0.15, length: 0.35), ambientStyle: .progressTimeline, preferredZone: .goldenAction, ergonomicWeight: 40, minLength: 0.15, defaultColorHex: "#FF5A60"),
            SlotPod(id: "todo", name: "Todo Checklist", systemIcon: "checklist", edge: .right, range: .init(start: 0.52, length: 0.25), ambientStyle: .segmentGauge, preferredZone: .goldenAction, ergonomicWeight: 35, minLength: 0.15, defaultColorHex: "#FF9E0A"),
            SlotPod(id: "music", name: "Music Waveform", systemIcon: "waveform", edge: .right, range: .init(start: 0.79, length: 0.14), ambientStyle: .waveLevelMeter, preferredZone: .quickFlick, ergonomicWeight: 25, minLength: 0.12, defaultColorHex: "#FF2D55"),
            SlotPod(id: "vitals", name: "Hardware Vitals", systemIcon: "waveform.path.ecg", edge: .left, range: .init(start: 0.08, length: 0.22), ambientStyle: .progressTimeline, preferredZone: .glance, ergonomicWeight: 35, minLength: 0.18, defaultColorHex: "#00E5A3"),
            SlotPod(id: "shelf", name: "Temporary Shelf", systemIcon: "tray.fill", edge: .left, range: .init(start: 0.32, length: 0.20), ambientStyle: .ghostDot, preferredZone: .goldenAction, ergonomicWeight: 35, minLength: 0.16, defaultColorHex: "#2ED573"),
            SlotPod(id: "notes", name: "Quick Notes", systemIcon: "note.text", edge: .left, range: .init(start: 0.54, length: 0.14), ambientStyle: .ghostDot, preferredZone: .goldenAction, ergonomicWeight: 30, minLength: 0.12, isEnabled: false, defaultColorHex: "#FFD166"),
            SlotPod(id: "scripts", name: "Script Runway", systemIcon: "terminal.fill", edge: .left, range: .init(start: 0.54, length: 0.20), ambientStyle: .ghostDot, preferredZone: .quickFlick, ergonomicWeight: 30, minLength: 0.16, isEnabled: true, defaultColorHex: "#6C5CE7"),
            SlotPod(id: "terminal", name: "Terminal", systemIcon: "apple.terminal.fill", edge: .left, range: .init(start: 0.76, length: 0.20), ambientStyle: .ghostDot, preferredZone: .goldenAction, ergonomicWeight: 25, minLength: 0.14, isEnabled: true, drawerWidth: 520, defaultColorHex: "#00F5D4"),
            SlotPod(id: "clipboard", name: "Clipboard", systemIcon: "doc.on.clipboard.fill", edge: .left, range: .init(start: 0.88, length: 0.08), ambientStyle: .ghostDot, preferredZone: .goldenAction, ergonomicWeight: 20, minLength: 0.08, isEnabled: false, drawerWidth: 260, defaultColorHex: "#FF9F0A")
        ]
    }
}
