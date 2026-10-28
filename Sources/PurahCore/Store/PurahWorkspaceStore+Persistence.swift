// Sources/PurahCore/Store/PurahWorkspaceStore+Persistence.swift
import Foundation
import AppKit

// Local persistence: reading and writing the workspace layout.
//
// Split out of `PurahWorkspaceStore` because it is the one part of the store
// with no run-time dependency on layout or UI state — it only serialises and
// deserialises. Keeping it here means a persistence change cannot accidentally
// be reviewed as a layout change.
extension PurahWorkspaceStore {
    // MARK: - Local Persistence
    public static func resetToFactoryDefaults(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: "purah.pods")
    }

    public func loadPersistentState() {
        let defaults = userDefaults
        loadExternalDecomposedState()

        if defaults.data(forKey: "purah.pods") != nil && defaults.object(forKey: "purah.hasCompletedOnboarding") == nil {
            defaults.set(true, forKey: "purah.hasCompletedOnboarding")
        }

        if let data = defaults.data(forKey: "purah.pods"),
           let savedPods = try? JSONDecoder().decode([SlotPod].self, from: data),
           !savedPods.isEmpty {
            var merged = savedPods
            let savedIds = Set(savedPods.map(\.id))
            for var def in Self.defaultPods() where !savedIds.contains(def.id) {
                if def.id == "ai" && !defaults.bool(forKey: "purah.didAutoInstallAIPlugin") {
                    def.isEnabled = true
                } else {
                    def.isEnabled = false
                }
                merged.append(def)
            }
            self.pods = merged
        }

        var didRepairPods = false
        if !defaults.bool(forKey: "purah.didRepairLegacyAutoStacks_v1") {
            let legacyPattern = try? NSRegularExpression(pattern: #"^major_(left|right)_[0-9]+$"#)
            for idx in self.pods.indices {
                if let gid = self.pods[idx].majorGroupId {
                    let range = NSRange(location: 0, length: gid.utf16.count)
                    if legacyPattern?.firstMatch(in: gid, range: range) != nil {
                        self.pods[idx].majorGroupId = nil
                        didRepairPods = true
                    }
                }
            }
            defaults.set(true, forKey: "purah.didRepairLegacyAutoStacks_v1")
            normalizePageRanges(for: .left)
            normalizePageRanges(for: .right)
            didRepairPods = true
        }

        for edge in [MountEdge.left, MountEdge.right] {
            let edgePods = self.pods.filter { $0.edge == edge && $0.isEnabled }
            let groupedByPage = Dictionary(grouping: edgePods, by: { max(0, $0.pageIndex) })
            var needsNormalize = false
            for (_, pagePods) in groupedByPage {
                let sorted = pagePods.sorted { $0.range.start < $1.range.start }
                if sorted.count >= 2 {
                    for i in 1..<sorted.count {
                        if sorted[i].range.start < sorted[i - 1].range.end - 0.005 {
                            needsNormalize = true
                            break
                        }
                    }
                }
                let sumLengths = sorted.reduce(0.0) { $0 + $1.range.length }
                if sumLengths > 0.96 {
                    needsNormalize = true
                }
                if needsNormalize { break }
            }
            if needsNormalize {
                normalizePageRanges(for: edge)
                didRepairPods = true
            }
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

        // Migrate legacy root keys into ScopedPluginStorage partition
        if defaults.object(forKey: "purah.calendarMaxRailEvents") != nil {
            let legacy = defaults.integer(forKey: "purah.calendarMaxRailEvents")
            if legacy > 0 { self.calendarMaxRailEvents = legacy }
            defaults.removeObject(forKey: "purah.calendarMaxRailEvents")
        }
        if defaults.object(forKey: "purah.todoMaxRailTasks") != nil {
            let legacy = defaults.integer(forKey: "purah.todoMaxRailTasks")
            if legacy > 0 { self.todoMaxRailTasks = legacy }
            defaults.removeObject(forKey: "purah.todoMaxRailTasks")
        }
        if defaults.object(forKey: "purah.clipboardMaxRailItems") != nil {
            let legacy = defaults.integer(forKey: "purah.clipboardMaxRailItems")
            if legacy > 0 { self.clipboardMaxRailItems = legacy }
            defaults.removeObject(forKey: "purah.clipboardMaxRailItems")
        }
        if defaults.object(forKey: "purah.vitals.isDecomposed") != nil {
            let legacy = defaults.bool(forKey: "purah.vitals.isDecomposed")
            ScopedPluginStorage(pluginId: "vitals", defaults: defaults).set(legacy, forKey: "isDecomposed")
            defaults.removeObject(forKey: "purah.vitals.isDecomposed")
        }
        if let legacyArr = defaults.stringArray(forKey: "purah.vitals.enabledMetrics") {
            let parsed = legacyArr.compactMap { VitalsMetricType(rawValue: $0) }
            if !parsed.isEmpty {
                ScopedPluginStorage(pluginId: "vitals", defaults: defaults).setCodable(parsed, forKey: "enabledMetrics")
            }
            defaults.removeObject(forKey: "purah.vitals.enabledMetrics")
        }
        if let legacyData = defaults.data(forKey: "purah.vitals.thresholds") {
            if let decoded = try? JSONDecoder().decode(VitalsColorThresholds.self, from: legacyData) {
                ScopedPluginStorage(pluginId: "vitals", defaults: defaults).setCodable(decoded, forKey: "thresholds")
            }
            defaults.removeObject(forKey: "purah.vitals.thresholds")
        }
        if defaults.object(forKey: "purah.scripts.isDecomposed") != nil {
            let legacy = defaults.bool(forKey: "purah.scripts.isDecomposed")
            ScopedPluginStorage(pluginId: "scripts", defaults: defaults).set(legacy, forKey: "isDecomposed")
            defaults.removeObject(forKey: "purah.scripts.isDecomposed")
        }
        if let legacyActionIds = defaults.stringArray(forKey: "purah.scripts.enabledActionIds") {
            ScopedPluginStorage(pluginId: "scripts", defaults: defaults).setCodable(legacyActionIds, forKey: "enabledActionIds")
            defaults.removeObject(forKey: "purah.scripts.enabledActionIds")
        }

        if defaults.object(forKey: "purah.isDynamicBreathingEnabled") != nil {
            self.isDynamicBreathingEnabled = defaults.bool(forKey: "purah.isDynamicBreathingEnabled")
        } else {
            self.isDynamicBreathingEnabled = true
        }

        if defaults.object(forKey: "purah.hotkey.keyCode") != nil {
            let code = UInt32(defaults.integer(forKey: "purah.hotkey.keyCode"))
            let mods = UInt32(defaults.integer(forKey: "purah.hotkey.modifiers"))
            self.hotKeyShortcut = HotKeyShortcut(keyCode: code, modifiers: mods)
        }
        if defaults.object(forKey: "purah.sculptorHotkey.keyCode") != nil {
            let code = UInt32(defaults.integer(forKey: "purah.sculptorHotkey.keyCode"))
            let mods = UInt32(defaults.integer(forKey: "purah.sculptorHotkey.modifiers"))
            self.sculptorHotKeyShortcut = HotKeyShortcut(keyCode: code, modifiers: mods)
        }

        if let modeStr = defaults.string(forKey: "purah.edgeTriggerMode"),
           let mode = EdgeTriggerMode(rawValue: modeStr) {
            self.edgeTriggerMode = mode
        }
        if let alertStr = defaults.string(forKey: "purah.alertStyle"),
           let style = PluginAlertStyle(rawValue: alertStr) {
            self.alertStyle = style
        }
        if let quietData = defaults.data(forKey: "purah.quietHours"),
           let decoded = try? JSONDecoder().decode(QuietHours.self, from: quietData) {
            // Assign the backing storage directly: the `didSet` would write it
            // straight back to disk during a load.
            _quietHours = decoded
        }
        if defaults.object(forKey: "purah.appFocusSettings") != nil {
            // The per-app page rules this build replaced are gone. The blob is
            // removed rather than merely ignored so a stale rules dictionary
            // cannot confuse a future migration.
            defaults.removeObject(forKey: "purah.appFocusSettings")
        }
        if defaults.object(forKey: "purah.isAppProfileSwitchingEnabled") != nil {
            self.isAppProfileSwitchingEnabled = defaults.bool(forKey: "purah.isAppProfileSwitchingEnabled")
        }
        if let profileData = defaults.data(forKey: "purah.contextProfiles"),
           let decoded = try? JSONDecoder().decode(ContextProfileStore.self, from: profileData) {
            _contextProfiles = decoded
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

        if defaults.object(forKey: "purah.isToastSoundEnabled") != nil {
            self.isToastSoundEnabled = defaults.bool(forKey: "purah.isToastSoundEnabled")
        }
        if let soundStr = defaults.string(forKey: "purah.toastNotificationSound"),
           let sound = ToastNotificationSound(rawValue: soundStr) {
            self.toastNotificationSound = sound
        }
        if defaults.object(forKey: "purah.isTrackpadHapticsEnabled") != nil {
            self.isTrackpadHapticsEnabled = defaults.bool(forKey: "purah.isTrackpadHapticsEnabled")
        }
        if defaults.object(forKey: "purah.isDrawerPopHapticEnabled") != nil {
            self.isDrawerPopHapticEnabled = defaults.bool(forKey: "purah.isDrawerPopHapticEnabled")
        }
        if defaults.object(forKey: "purah.isControlHapticEnabled") != nil {
            self.isControlHapticEnabled = defaults.bool(forKey: "purah.isControlHapticEnabled")
        }

        if didRepairPods {
            savePersistentState()
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
        defaults.set(isDynamicBreathingEnabled, forKey: "purah.isDynamicBreathingEnabled")
        defaults.set(Int(hotKeyShortcut.keyCode), forKey: "purah.hotkey.keyCode")
        defaults.set(Int(hotKeyShortcut.modifiers), forKey: "purah.hotkey.modifiers")
        defaults.set(Int(sculptorHotKeyShortcut.keyCode), forKey: "purah.sculptorHotkey.keyCode")
        defaults.set(Int(sculptorHotKeyShortcut.modifiers), forKey: "purah.sculptorHotkey.modifiers")
        defaults.set(displayTargetMode.rawValue, forKey: "purah.displayTargetMode")
        defaults.set(edgeTriggerMode.rawValue, forKey: "purah.edgeTriggerMode")
        defaults.set(alertStyle.rawValue, forKey: "purah.alertStyle")
        if let quietData = try? JSONEncoder().encode(quietHours) {
            defaults.set(quietData, forKey: "purah.quietHours")
        }
        if let profileData = try? JSONEncoder().encode(contextProfiles) {
            defaults.set(profileData, forKey: "purah.contextProfiles")
        }
        defaults.set(isAppProfileSwitchingEnabled, forKey: "purah.isAppProfileSwitchingEnabled")
        defaults.set(isEventToastAlertEnabled, forKey: "purah.isEventToastAlertEnabled")
        defaults.set(isToastSoundEnabled, forKey: "purah.isToastSoundEnabled")
        defaults.set(toastNotificationSound.rawValue, forKey: "purah.toastNotificationSound")
        defaults.set(isTrackpadHapticsEnabled, forKey: "purah.isTrackpadHapticsEnabled")
        defaults.set(isDrawerPopHapticEnabled, forKey: "purah.isDrawerPopHapticEnabled")
        defaults.set(isControlHapticEnabled, forKey: "purah.isControlHapticEnabled")
        defaults.set(edgeTriggerSensitivity.rawValue, forKey: "purah.edgeTriggerSensitivity")
        defaults.set(customInitialDwellMs, forKey: "purah.customInitialDwellMs")
        defaults.set(customExitGraceMs, forKey: "purah.customExitGraceMs")
        defaults.set(customCatchCorridorPt, forKey: "purah.customCatchCorridorPt")
        defaults.set(customPushForceThreshold, forKey: "purah.customPushForceThreshold")
        defaults.set(customPushResistanceBarrier, forKey: "purah.customPushResistanceBarrier")
    }


    public func scheduleSavePersistentState() {
        if Self.isTestingEnvironment {
            savePersistentState()
            return
        }
        debouncedSaveTask?.cancel()
        debouncedSaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled, let self else { return }
            self.savePersistentState()
        }
    }
}
