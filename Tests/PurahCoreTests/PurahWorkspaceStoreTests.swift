// Tests/PurahCoreTests/PurahWorkspaceStoreTests.swift
import Testing
import Foundation
import AppKit
@testable import PurahCore

@Suite("Workspace Store Tests")
@MainActor
struct PurahWorkspaceStoreTests {
    @Test("Initializes with standard built-in pods including vitals and scripts")
    func testDefaultPods() {
        let isolated = UserDefaults(suiteName: "test_default_\(UUID().uuidString)")!
        let store = PurahWorkspaceStore(userDefaults: isolated)
        #expect(store.pods.count == 10)
        #expect(store.pods.contains(where: { $0.id == "calendar" }))
        #expect(store.pods.contains(where: { $0.id == "todo" }))
        #expect(store.pods.contains(where: { $0.id == "music" }))
        #expect(store.pods.contains(where: { $0.id == "shelf" }))
        #expect(store.pods.contains(where: { $0.id == "notes" }))
        #expect(store.pods.contains(where: { $0.id == "vitals" }))
        #expect(store.pods.contains(where: { $0.id == "scripts" }))
        #expect(store.pods.contains(where: { $0.id == "terminal" }))
        #expect(store.pods.contains(where: { $0.id == "clipboard" }))
        #expect(store.pods.contains(where: { $0.id == "ai" }))
    }

    @Test("Applies Sprint Productivity preset properly")
    func testSprintPreset() {
        let isolated = UserDefaults(suiteName: "test_sprint")!
        let store = PurahWorkspaceStore(userDefaults: isolated)
        store.applyPreset(.sprintProductivity)

        // Sprint preset: left rail hosts shelf and notes
        let leftPods = store.pods.filter { $0.edge == .left && $0.isEnabled }
        #expect(leftPods.contains(where: { $0.id == "shelf" }))
        #expect(leftPods.contains(where: { $0.id == "notes" }))

        // Right rail hosts calendar and todo
        let rightPods = store.pods.filter { $0.edge == .right && $0.isEnabled }
        #expect(rightPods.contains(where: { $0.id == "calendar" }))
        #expect(rightPods.contains(where: { $0.id == "todo" }))
    }

    @Test("All presets configure 7 pods within safe rail capacity without overload warnings")
    func testPresetsWithinSafeCapacity() {
        let isolated = UserDefaults(suiteName: "test_presets")!
        let store = PurahWorkspaceStore(userDefaults: isolated)

        for preset in PodPreset.allCases {
            store.applyPreset(preset)
            #expect(store.capacityRatio(for: .left) <= 1.0, "Preset \(preset.rawValue) overloaded left rail")
            #expect(store.capacityRatio(for: .right) <= 1.0, "Preset \(preset.rawValue) overloaded right rail")
        }
    }

    @Test("Toggle pod enabled/disabled updates active layout")
    func testTogglePodEnabled() {
        let isolated = UserDefaults(suiteName: "test_toggle")!
        let store = PurahWorkspaceStore(userDefaults: isolated)
        #expect(store.pods.first(where: { $0.id == "music" })?.isEnabled == true)

        store.togglePodEnabled(id: "music")
        #expect(store.pods.first(where: { $0.id == "music" })?.isEnabled == false)

        store.togglePodEnabled(id: "music")
        #expect(store.pods.first(where: { $0.id == "music" })?.isEnabled == true)
    }

    @Test("Fill rail expands pod to span safe boundary without crashing")
    func testFillRail() throws {
        let isolated = UserDefaults(suiteName: "test_fill_rail")!
        let store = PurahWorkspaceStore(userDefaults: isolated)
        store.fillRail(podId: "calendar")

        let cal = try #require(store.pods.first(where: { $0.id == "calendar" }))
        #expect(cal.range.length >= 0.35)
    }

    @Test("PurahWorkspaceStore persists settings via savePersistentState and loadPersistentState")
    func testStorePersistence() {
        let isolated = UserDefaults(suiteName: "test_store_persistence")!
        let store = PurahWorkspaceStore(userDefaults: isolated)
        store.setPodColorHex(podId: "notes", hex: "#123456")
        store.fixedDrawerWidth = 310.0
        store.drawerWidthMode = .adaptive
        store.railBarWidth = 12.0
        store.edgeTriggerMode = .pushForce
        store.savePersistentState()

        let freshStore = PurahWorkspaceStore(userDefaults: isolated)
        freshStore.loadPersistentState()

        #expect(freshStore.customPodColors["notes"] == "#123456")
        #expect(freshStore.fixedDrawerWidth == 310.0)
        #expect(freshStore.drawerWidthMode == .adaptive)
        #expect(freshStore.railBarWidth == 12.0)
        #expect(freshStore.edgeTriggerMode == .pushForce)
    }

    @Test("SystemCalendarSyncService and SystemRemindersSyncService bind store weakly")
    func testSyncServiceStoreBinding() {
        let store = PurahWorkspaceStore()
        SystemCalendarSyncService.shared.boundStore = store
        #expect(SystemCalendarSyncService.shared.boundStore === store)

        SystemRemindersSyncService.shared.boundStore = store
        #expect(SystemRemindersSyncService.shared.boundStore === store)
    }

    @Test("Dynamic capability provider registers and resolves height, decomposed state, and sub-items generically")
    func testGenericCapabilityProviderResolution() {
        @MainActor
        struct MockDecomposedProvider: PurahPodCapabilityProvider {
            let podId: String = "test.custom.pod"
            var isDecomposed: Bool { true }
            var subItemCount: Int { 3 }
            var subItemTitles: [String] { ["Alpha", "Beta", "Gamma"] }
            var pinnedIds: Set<String> = []

            func minimumDrawerHeight(store: PurahWorkspaceStore) -> CGFloat {
                240.0
            }

            func hasPinnedChild(store: PurahWorkspaceStore) -> Bool {
                (0..<subItemCount).contains { idx in
                    store.isItemPinned(id: "test.custom.pod-item-\(idx)")
                }
            }

            func ownsSubItemId(_ itemId: String, store: PurahWorkspaceStore) -> Bool {
                itemId.hasPrefix("test.custom.pod-")
            }

            func subItemCount(store: PurahWorkspaceStore) -> Int {
                3
            }

            func subItemId(at index: Int, store: PurahWorkspaceStore) -> String? {
                guard index >= 0 && index < 3 else { return nil }
                return "test.custom.pod-item-\(index)"
            }

            func subItemTitle(at index: Int, store: PurahWorkspaceStore) -> String? {
                guard index >= 0 && index < subItemTitles.count else { return nil }
                return subItemTitles[index]
            }
        }

        let store = PurahWorkspaceStore()
        let customPod = SlotPod(
            id: "test.custom.pod",
            name: "Custom Testing Pod",
            systemIcon: "star.fill",
            edge: .right,
            range: .init(start: 0.1, length: 0.2),
            ambientStyle: .ghostDot,
            preferredZone: .goldenAction,
            ergonomicWeight: 30,
            defaultColorHex: "#AABBCC"
        )
        store.pods.append(customPod)

        let provider = MockDecomposedProvider()
        store.registerCapabilityProvider(provider)

        // 1. Minimum drawer height delegates strictly to provider
        #expect(store.minimumDrawerHeight(for: "test.custom.pod") == 240.0)

        // 2. isPodDecomposed delegates strictly to provider
        #expect(store.isPodDecomposed("test.custom.pod") == true)

        // 3. pod(forItemId:) resolves ownership without hardcoded logic
        #expect(store.pod(forItemId: "test.custom.pod-item-1")?.id == "test.custom.pod")
        #expect(store.pod(forItemId: "unrelated-item") == nil)

        // 4. hasPinnedItem resolves via provider.hasPinnedChild
        #expect(store.hasPinnedItem(on: .right) == false)
        store.togglePinItem(id: "test.custom.pod-item-1")
        #expect(store.hasPinnedItem(on: .right) == true)

        // 5. hasActiveOrPinnedChild delegates to provider
        #expect(store.hasActiveOrPinnedChild(for: "test.custom.pod") == true)

        // 6. activeDrawerCardFrames generates precision frames for decomposed sub-items
        store.activateDrawer(podId: "test.custom.pod", itemId: "test.custom.pod-item-1")
        let frames = store.activeDrawerCardFrames(for: .right, totalHeight: 1000.0, windowWidth: 340.0)
        #expect(frames.count == 1)
        guard let frame = frames.first else {
            Issue.record("Expected 1 active sub-item frame")
            return
        }
        #expect(frame.width > 0)
        #expect(frame.height >= 34.0)
    }

    @Test("defaultColorHex resolves from SlotPod and defaults to cyan without hardcoded switch")
    func testGenericDefaultColorHex() {
        let store = PurahWorkspaceStore()

        #expect(store.defaultColorHex(for: "calendar") == "#FF5A60")
        #expect(store.defaultColorHex(for: "todo") == "#FF9E0A")
        #expect(store.defaultColorHex(for: "music") == "#FF2D55")
        #expect(store.defaultColorHex(for: "vitals") == "#00E5A3")
        #expect(store.defaultColorHex(for: "shelf") == "#2ED573")
        #expect(store.defaultColorHex(for: "notes") == "#FFD166")
        #expect(store.defaultColorHex(for: "scripts") == "#6C5CE7")
        #expect(store.defaultColorHex(for: "terminal") == "#00F5D4")

        let customPod = SlotPod(
            id: "my-custom-pod",
            name: "Custom Pod",
            systemIcon: "cube.fill",
            edge: .left,
            range: .init(start: 0.1, length: 0.2),
            ambientStyle: .ghostDot,
            preferredZone: .glance,
            ergonomicWeight: 20,
            defaultColorHex: "#998877"
        )
        store.pods.append(customPod)
        #expect(store.defaultColorHex(for: "my-custom-pod") == "#998877")
        #expect(store.defaultColorHex(for: "nonexistent-pod") == "#00F5D4")
    }

    @Test("togglePodEnabled triggers onPodEnabledChanged and triggers window rebuild")
    func testTogglePodEnabledLifecycleAndServices() {
        let store = PurahWorkspaceStore()
        var changedId: String?
        var changedState: Bool?
        var rebuildTriggered = false

        store.onPodEnabledChanged = { id, enabled in
            changedId = id
            changedState = enabled
        }
        store.onWindowsRebuildNeeded = {
            rebuildTriggered = true
        }

        // 1. Disable music pod: must notify and trigger rebuild
        if store.pods.first(where: { $0.id == "music" })?.isEnabled == true {
            store.togglePodEnabled(id: "music")
            #expect(store.pods.first(where: { $0.id == "music" })?.isEnabled == false)
            #expect(changedId == "music")
            #expect(changedState == false)
            #expect(rebuildTriggered == true)
        }

        // 2. Disable vitals pod: must stop kernel monitoring
        if store.pods.first(where: { $0.id == "vitals" })?.isEnabled == true {
            rebuildTriggered = false
            store.togglePodEnabled(id: "vitals")
            #expect(store.pods.first(where: { $0.id == "vitals" })?.isEnabled == false)
            #expect(changedId == "vitals")
            #expect(changedState == false)
            #expect(rebuildTriggered == true)
        }

        // 3. Re-enable music: must resume and notify
        rebuildTriggered = false
        store.togglePodEnabled(id: "music")
        #expect(store.pods.first(where: { $0.id == "music" })?.isEnabled == true)
        #expect(changedId == "music")
        #expect(changedState == true)
        #expect(rebuildTriggered == true)
    }

    @Test("movePodInOrder and swapPods cleanly swap relative vertical order and persist")
    func testPodReorderingAndPositionSwapping() {
        let isolated = UserDefaults(suiteName: "test_reordering_\(UUID().uuidString)")!
        let store = PurahWorkspaceStore(userDefaults: isolated)
        let rightPods = store.pods.filter { $0.edge == .right && $0.isEnabled }
            .sorted { $0.range.start < $1.range.start }
        #expect(rightPods.count >= 2)

        let topPodId = rightPods[0].id
        let secondPodId = rightPods[1].id

        #expect(store.canMovePod(id: topPodId, direction: .up) == false)
        #expect(store.canMovePod(id: topPodId, direction: .down) == true)
        #expect(store.canMovePod(id: secondPodId, direction: .up) == true)

        // Swap top pod down
        store.movePodInOrder(id: topPodId, direction: .down)

        let reorderedRightPods = store.pods.filter { $0.edge == .right && $0.isEnabled }
            .sorted { $0.range.start < $1.range.start }

        #expect(reorderedRightPods[0].id == secondPodId)
        #expect(reorderedRightPods[1].id == topPodId)

        // Swap back up
        store.movePodInOrder(id: topPodId, direction: .up)
        let restoredPods = store.pods.filter { $0.edge == .right && $0.isEnabled }
            .sorted { $0.range.start < $1.range.start }
        #expect(restoredPods[0].id == topPodId)
        #expect(restoredPods[1].id == secondPodId)
    }

    @Test("snapPod cleanly snaps pod to the bottom of its predecessor eliminating gap")
    func testSnapPodToPredecessor() {
        let isolated = UserDefaults(suiteName: "test_snap_\(UUID().uuidString)")!
        let store = PurahWorkspaceStore(userDefaults: isolated)
        let rightPods = store.pods.filter { $0.edge == .right && $0.isEnabled }
            .sorted { $0.range.start < $1.range.start }
        guard rightPods.count >= 2 else { return }

        let bottomPod = rightPods.last!
        if store.hasGapAbove(id: bottomPod.id) {
            let oldStart = bottomPod.range.start
            store.snapPod(id: bottomPod.id, to: .predecessor)
            let updatedPod = store.pods.first(where: { $0.id == bottomPod.id })!
            #expect(updatedPod.range.start < oldStart)
            #expect(store.hasGapAbove(id: bottomPod.id) == false)
        }
    }

    @Test("Pods persistence stores custom layout in UserDefaults and restores on launch")
    func testPodsPersistence() {
        let suiteName = "test_pods_persistence_\(UUID().uuidString)"
        let isolatedDefaults = UserDefaults(suiteName: suiteName)!
        defer { isolatedDefaults.removePersistentDomain(forName: suiteName) }

        let store = PurahWorkspaceStore(userDefaults: isolatedDefaults)
        guard let terminalIdx = store.pods.firstIndex(where: { $0.id == "terminal" }) else { return }
        let originalTerminalEnabled = store.pods[terminalIdx].isEnabled

        // Mutate pod state and save
        store.pods[terminalIdx].isEnabled = !originalTerminalEnabled
        store.savePersistentState()

        // Create new store with same isolated defaults and verify it loads the mutated state
        let newStore = PurahWorkspaceStore(userDefaults: isolatedDefaults)
        let reloadedTerminal = newStore.pods.first(where: { $0.id == "terminal" })
        #expect(reloadedTerminal?.isEnabled == !originalTerminalEnabled)
    }

    @Test("Layout operations immediately persist to disk without requiring app quit or explicit save")
    func testImmediateLayoutPersistenceOnOperations() {
        let suiteName = "test_immediate_persistence_\(UUID().uuidString)"
        let isolatedDefaults = UserDefaults(suiteName: suiteName)!
        defer { isolatedDefaults.removePersistentDomain(forName: suiteName) }

        let store = PurahWorkspaceStore(userDefaults: isolatedDefaults)

        // 1. Operation: movePod immediately persists
        store.movePod(id: "shelf", to: .right)
        let storeAfterMove = PurahWorkspaceStore(userDefaults: isolatedDefaults)
        #expect(storeAfterMove.pods.first(where: { $0.id == "shelf" })?.edge == .right)

        // 2. Operation: updatePodRange immediately persists
        let targetPod = store.pods.first(where: { $0.id == "calendar" })!
        let newRange = NormalizedRange(start: 0.12, length: 0.38)
        store.updatePodRange(id: targetPod.id, newRange: newRange)
        let storeAfterRange = PurahWorkspaceStore(userDefaults: isolatedDefaults)
        let reloadedCal = storeAfterRange.pods.first(where: { $0.id == "calendar" })!
        #expect(abs(reloadedCal.range.start - 0.12) < 0.05)

        // 3. Operation: fillRail immediately persists
        store.fillRail(podId: "calendar")
        let storeAfterFill = PurahWorkspaceStore(userDefaults: isolatedDefaults)
        let filledCal = storeAfterFill.pods.first(where: { $0.id == "calendar" })!
        #expect(filledCal.range.length > 0.30)
    }

    @Test("App launch sequence with PluginMarketManager does not overwrite custom layout")
    func testAppLaunchWithMarketManagerPreservesCustomLayout() {
        let suiteName = "test_launch_preserve_\(UUID().uuidString)"
        let isolatedDefaults = UserDefaults(suiteName: suiteName)!
        defer { isolatedDefaults.removePersistentDomain(forName: suiteName) }

        // 1. Initial run: customize layout
        let initialStore = PurahWorkspaceStore(userDefaults: isolatedDefaults)
        initialStore.movePod(id: "music", to: .left)
        guard let calPod = initialStore.pods.first(where: { $0.id == "calendar" }) else { return }
        let customRange = NormalizedRange(start: 0.08, length: 0.45)
        initialStore.updatePodRange(id: calPod.id, newRange: customRange)
        initialStore.savePersistentState()

        // 2. Simulate next app launch:
        // PurahWorkspaceStore inits, then PluginRegistry binds store (instantiating PluginMarketManager)
        let freshStore = PurahWorkspaceStore(userDefaults: isolatedDefaults)
        let market = PluginMarketManager(store: freshStore, userDefaults: isolatedDefaults)
        freshStore.setMarketManager(market)

        // Custom edge must be preserved!
        let reloadedMusic = freshStore.pods.first(where: { $0.id == "music" })
        #expect(reloadedMusic?.edge == .left)

        // Custom range must be preserved (not reset by autoLayoutAll)!
        let reloadedCal = freshStore.pods.first(where: { $0.id == "calendar" })
        #expect(abs((reloadedCal?.range.start ?? 0) - 0.08) < 0.05)
    }

    @Test("Disabling pods to leave only 4 active pods preserves exact 4 pods across app restarts")
    func testLeavingFourPodsPreservedAcrossRestarts() {
        let suiteName = "test_four_pods_\(UUID().uuidString)"
        let isolatedDefaults = UserDefaults(suiteName: suiteName)!
        defer { isolatedDefaults.removePersistentDomain(forName: suiteName) }

        let store = PurahWorkspaceStore(userDefaults: isolatedDefaults)
        let market = PluginMarketManager(store: store, userDefaults: isolatedDefaults)
        store.setMarketManager(market)

        // Keep only 4 pods enabled (e.g. calendar, music, vitals, shelf)
        let keepIds: Set<String> = ["calendar", "music", "vitals", "shelf"]
        for pod in store.pods {
            if !keepIds.contains(pod.id) && pod.isEnabled {
                store.togglePodEnabled(id: pod.id)
            }
        }
        #expect(store.pods.filter(\.isEnabled).count == 4)

        // Simulate app relaunch
        let relaunchedStore = PurahWorkspaceStore(userDefaults: isolatedDefaults)
        let relaunchedMarket = PluginMarketManager(store: relaunchedStore, userDefaults: isolatedDefaults)
        relaunchedStore.setMarketManager(relaunchedMarket)

        let enabledPods = relaunchedStore.pods.filter(\.isEnabled)
        #expect(enabledPods.count == 4)
        #expect(Set(enabledPods.map(\.id)) == keepIds)
    }

    @Test("Plugin-scoped storage bridges and legacy migration ensure store purity")
    func testPluginScopedStorageBridgesAndMigration() {
        let suiteName = "test_scoped_bridges_\(UUID().uuidString)"
        let isolated = UserDefaults(suiteName: suiteName)!
        defer { isolated.removePersistentDomain(forName: suiteName) }

        // 1. Simulate legacy keys placed directly in root UserDefaults
        isolated.set(5, forKey: "purah.calendarMaxRailEvents")
        isolated.set(8, forKey: "purah.todoMaxRailTasks")
        isolated.set(6, forKey: "purah.clipboardMaxRailItems")
        isolated.set(false, forKey: "purah.vitals.isDecomposed")
        isolated.set(["cpu", "disk"], forKey: "purah.vitals.enabledMetrics")
        isolated.set(false, forKey: "purah.scripts.isDecomposed")
        isolated.set(["action1", "action2"], forKey: "purah.scripts.enabledActionIds")

        // 2. Initialize store: must migrate legacy keys into ScopedPluginStorage
        let store = PurahWorkspaceStore(userDefaults: isolated)
        store.loadPersistentState()

        #expect(store.calendarMaxRailEvents == 5)
        #expect(store.todoMaxRailTasks == 8)
        #expect(store.clipboardMaxRailItems == 6)
        #expect(store._isVitalsDecomposed == false)
        #expect(store._vitalsEnabledMetrics == [.cpu, .disk])
        #expect(store._isScriptsDecomposed == false)
        #expect(store._scriptsEnabledActionIds == ["action1", "action2"])

        // Root keys must be cleaned up
        #expect(isolated.object(forKey: "purah.calendarMaxRailEvents") == nil)
        #expect(isolated.object(forKey: "purah.todoMaxRailTasks") == nil)
        #expect(isolated.object(forKey: "purah.clipboardMaxRailItems") == nil)
        #expect(isolated.object(forKey: "purah.vitals.isDecomposed") == nil)
        #expect(isolated.object(forKey: "purah.vitals.enabledMetrics") == nil)
        #expect(isolated.object(forKey: "purah.scripts.isDecomposed") == nil)
        #expect(isolated.object(forKey: "purah.scripts.enabledActionIds") == nil)

        // Partitioned plugin storage must hold the migrated values
        let calStorage = ScopedPluginStorage(pluginId: "calendar", defaults: isolated)
        let todoStorage = ScopedPluginStorage(pluginId: "todo", defaults: isolated)
        let clipStorage = ScopedPluginStorage(pluginId: "clipboard", defaults: isolated)
        let vitalsStorage = ScopedPluginStorage(pluginId: "vitals", defaults: isolated)
        let scriptsStorage = ScopedPluginStorage(pluginId: "scripts", defaults: isolated)
        let musicStorage = ScopedPluginStorage(pluginId: "music", defaults: isolated)

        #expect(calStorage.int(forKey: "maxRailEvents") == 5)
        #expect(todoStorage.int(forKey: "maxRailTodos") == 8)
        #expect(clipStorage.int(forKey: "maxRailItems") == 6)
        #expect(vitalsStorage.bool(forKey: "isDecomposed") == false)
        #expect(vitalsStorage.codable(forKey: "enabledMetrics", as: [VitalsMetricType].self) == [.cpu, .disk])
        #expect(scriptsStorage.bool(forKey: "isDecomposed") == false)
        #expect(scriptsStorage.codable(forKey: "enabledActionIds", as: [String].self) == ["action1", "action2"])

        // 3. Mutating scoped storage directly updates store computed properties seamlessly
        calStorage.set(3, forKey: "maxRailEvents")
        #expect(store.calendarMaxRailEvents == 3)

        // 4. Mutating via store updates scoped storage seamlessly without contaminating root
        store.todoMaxRailTasks = 9
        #expect(todoStorage.int(forKey: "maxRailTodos") == 9)
        #expect(isolated.object(forKey: "purah.todoMaxRailTasks") == nil)

        store._isVitalsDecomposed = true
        #expect(vitalsStorage.bool(forKey: "isDecomposed") == true)
        #expect(isolated.object(forKey: "purah.vitals.isDecomposed") == nil)

        // 5. Test music waveform animation boolean compatibility (Codable JSON Data vs plist bool)
        store.isMusicWaveformAnimationEnabled = false
        #expect(store.isMusicWaveformAnimationEnabled == false)
        #expect(musicStorage.codable(forKey: "isWaveformAnimationEnabled", as: Bool.self) == false)

        // 6. Saving persistent state does not re-contaminate root defaults with plugin keys
        store.savePersistentState()
        #expect(isolated.object(forKey: "purah.calendarMaxRailEvents") == nil)
        #expect(isolated.object(forKey: "purah.todoMaxRailTasks") == nil)
        #expect(isolated.object(forKey: "purah.clipboardMaxRailItems") == nil)
        #expect(isolated.object(forKey: "purah.vitals.isDecomposed") == nil)
        #expect(isolated.object(forKey: "purah.scripts.isDecomposed") == nil)
    }

    @Test("Onboarding Step 6 Anti-Touch Calibration initializes live gate telemetry and handles drawer states")
    func testOnboardingStep6GateTelemetry() {
        let isolated = UserDefaults(suiteName: "test_gate_telemetry_\(UUID().uuidString)")!
        let store = PurahWorkspaceStore(userDefaults: isolated)
        store.isOnboardingGuideActive = true
        store.edgeTriggerSensitivity = .agile
        store.edgeTriggerMode = .hoverDwell

        // Enter Step 6: must force .balanced sensitivity, reset gate state and target value to 150ms
        store.selectOnboardingStep(.antiTouchCalibration)
        #expect(store.edgeTriggerSensitivity == .balanced)
        #expect(store.onboardingGateState == .idle)
        #expect(store.onboardingGateProgress == 0.0)
        #expect(store.onboardingGateCurrentValue == 0)
        #expect(store.onboardingGateTargetValue == 150)

        // Activating a drawer sets state to .opened and progress to 1.0
        store.activateDrawer(podId: "vitals")
        #expect(store.onboardingDidTriggerEdgeDrawer == true)
        #expect(store.onboardingGateState == .opened)
        #expect(store.onboardingGateProgress == 1.0)
        #expect(store.onboardingGateCurrentValue == 150)

        // Dismissing drawer resets gate back to .idle
        store.dismissActiveDrawer()
        #expect(store.onboardingGateState == .idle)
        #expect(store.onboardingGateProgress == 0.0)
        #expect(store.onboardingGateCurrentValue == 0)
    }

    @Test("Onboarding Step 2 and Step 6 localized strings exist across EN, zh-Hans, zh-Hant")
    func testOnboardingLocalizedStrings() {
        let requiredKeys = [
            "onboarding.step2.arrowPrompt",
            "onboarding.step2.heroButton.toChips",
            "onboarding.step2.heroButton.toBar",
            "onboarding.step6.gate.title",
            "onboarding.step6.gate.idle",
            "onboarding.step6.gate.dwelling",
            "onboarding.step6.gate.pushing",
            "onboarding.step6.gate.suppressedFling",
            "onboarding.step6.gate.opened"
        ]
        for key in requiredKeys {
            #expect(!key.localized.isEmpty && key.localized != key, "Missing localization for \(key)")
        }
    }
}
