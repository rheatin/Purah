// Tests/PurahCoreTests/PurahConfigBackupTests.swift
import Testing
import Foundation
import AppKit
@testable import PurahCore
@testable import PurahApp

@Suite("Configuration Backup & Reset Tests")
@MainActor
struct PurahConfigBackupTests {

    @Test("PurahConfigValue codable round-trip")
    func testConfigValueCodable() throws {
        let stringVal = PurahConfigValue.string("Purah Pad")
        let intVal = PurahConfigValue.int(42)
        let doubleVal = PurahConfigValue.double(3.14159)
        let boolVal = PurahConfigValue.bool(true)
        let arrVal = PurahConfigValue.stringArray(["ai", "vitals", "shelf"])
        let dataVal = PurahConfigValue.dataBase64("SGVsbG8gV29ybGQ=")

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let encoded = try encoder.encode([stringVal, intVal, doubleVal, boolVal, arrVal, dataVal])
        let decoded = try decoder.decode([PurahConfigValue].self, from: encoded)

        #expect(decoded.count == 6)
        #expect(decoded[0] == stringVal)
        #expect(decoded[1] == intVal)
        #expect(decoded[2] == doubleVal)
        #expect(decoded[3] == boolVal)
        #expect(decoded[4] == arrVal)
        #expect(decoded[5] == dataVal)
    }

    @Test("Export backup contains purah settings and valid metadata")
    func testExportBackup() throws {
        let suite = "test_export_\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = PurahWorkspaceStore(userDefaults: defaults)

        store.fixedDrawerWidth = 320.0
        store.railBarWidth = 10.0
        store.savePersistentState()

        let data = try PurahConfigBackupManager.exportBackupData(from: store, defaults: defaults)
        #expect(!data.isEmpty)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(PurahConfigurationBackup.self, from: data)

        #expect(backup.schemaVersion == PurahConfigBackupManager.currentSchemaVersion)
        // Metadata must track the shipping version, not a stale literal.
        #expect(backup.appVersion == PurahCore.version)
        #expect(backup.settings["purah.fixedDrawerWidth"] == .double(320.0))
        #expect(backup.settings["purah.railBarWidth"] == .double(10.0))
    }

    @Test("Import backup round-trip restores store state and settings")
    func testImportBackupRoundTrip() throws {
        let suiteA = "test_import_src_\(UUID().uuidString)"
        let defaultsA = UserDefaults(suiteName: suiteA)!
        let storeA = PurahWorkspaceStore(userDefaults: defaultsA)

        storeA.fixedDrawerWidth = 350.0
        storeA.railBarWidth = 12.0
        defaultsA.set("zh-Hans", forKey: "purah.appLanguage")
        storeA.savePersistentState()

        let exportedData = try PurahConfigBackupManager.exportBackupData(from: storeA, defaults: defaultsA)

        let suiteB = "test_import_dst_\(UUID().uuidString)"
        let defaultsB = UserDefaults(suiteName: suiteB)!
        let storeB = PurahWorkspaceStore(userDefaults: defaultsB)

        try PurahConfigBackupManager.importBackupData(exportedData, into: storeB, defaults: defaultsB)

        #expect(storeB.fixedDrawerWidth == 350.0)
        #expect(storeB.railBarWidth == 12.0)
        #expect(defaultsB.string(forKey: "purah.appLanguage") == "zh-Hans")
    }

    @Test("Reset to factory defaults restores defaults and sets didAutoInstallAIPlugin")
    func testResetToFactoryDefaults() {
        let suite = "test_reset_\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = PurahWorkspaceStore(userDefaults: defaults)

        store.fixedDrawerWidth = 400.0
        store.railBarWidth = 16.0
        store.drawerWidthMode = .adaptive
        store.leftRailPage = 2
        defaults.set("custom_val", forKey: "purah.customKey")
        store.savePersistentState()

        PurahConfigBackupManager.resetToFactoryDefaults(store: store, defaults: defaults)

        #expect(store.fixedDrawerWidth == 290.0)
        #expect(store.railBarWidth == 8.0)
        // A factory reset returns the user to a fresh install, and a fresh
        // install starts on Adaptive so each plugin's declared width wins.
        #expect(store.drawerWidthMode == .adaptive)
        #expect(store.leftRailPage == 0)
        #expect(defaults.string(forKey: "purah.customKey") == nil)
        #expect(defaults.bool(forKey: "purah.didAutoInstallAIPlugin") == true)
        #expect(store.pods.contains(where: { $0.id == "ai" && $0.isEnabled }))
    }

    @Test("A factory reset resets the settings nobody remembered to set by hand")
    func testResetClearsEveryPersistedSetting() {
        let suite = "test_reset_full_\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = PurahWorkspaceStore(userDefaults: defaults)

        // Settings that live outside the handful the old reset assigned. The
        // reset used to clear the keys and then save, so `savePersistentState`
        // wrote these straight back from the live store — a reset that undid
        // almost nothing.
        store.quietHours = QuietHours(isEnabled: true, startMinute: 22 * 60, endMinute: 7 * 60)
        store.alertStyleOverride = .sonarWave
        store.isAppProfileSwitchingEnabled = true
        store.isToastSoundEnabled = false
        store.setAlertChannel(.toast, isEnabled: false, forPodId: "ai")
        store.customExitGraceMs = 500.0
        store.isTrackpadHapticsEnabled = false
        store.savePersistentState()

        PurahConfigBackupManager.resetToFactoryDefaults(store: store, defaults: defaults)

        #expect(store.quietHours.isEnabled == false, "quiet hours survived the reset")
        #expect(store.alertStyleOverride == nil)
        #expect(store.podAlertChannels.isEmpty)
        #expect(store.isAppProfileSwitchingEnabled == false)
        #expect(store.isToastSoundEnabled == true)
        #expect(store.customExitGraceMs == 280.0)
        #expect(store.isTrackpadHapticsEnabled == true)

        // And it must be the value on disk too, not just in memory: reloading
        // from the same defaults has to produce the same fresh install.
        let reloaded = PurahWorkspaceStore(userDefaults: defaults)
        #expect(reloaded.quietHours.isEnabled == false)
        #expect(reloaded.alertStyleOverride == nil)
        #expect(reloaded.podAlertChannels.isEmpty)
        #expect(reloaded.customExitGraceMs == 280.0)
    }

    @Test("Auto-installs and enables AI plugin for existing users lacking it in saved pods")
    func testAIPluginMigrationForExistingUsers() {
        let suite = "test_ai_migration_\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!

        // Simulate legacy user who saved pods before AI plugin was added
        let legacyPods = [
            SlotPod(id: "vitals", name: "Vitals", systemIcon: "bolt", edge: .left, range: .init(start: 0.1, length: 0.2), ambientStyle: .progressTimeline, preferredZone: .glance, ergonomicWeight: 30),
            SlotPod(id: "music", name: "Music", systemIcon: "music.note", edge: .right, range: .init(start: 0.1, length: 0.2), ambientStyle: .waveLevelMeter, preferredZone: .quickFlick, ergonomicWeight: 25)
        ]
        let encodedPods = try! JSONEncoder().encode(legacyPods)
        defaults.set(encodedPods, forKey: "purah.pods")
        defaults.set(["vitals", "music"], forKey: "purah.installedPluginIds")
        #expect(defaults.bool(forKey: "purah.didAutoInstallAIPlugin") == false)

        // Loading workspace store should add AI pod and keep it enabled
        let store = PurahWorkspaceStore(userDefaults: defaults)
        let aiPod = store.pods.first(where: { $0.id == "ai" })
        #expect(aiPod != nil)
        #expect(aiPod?.isEnabled == true)

        // PluginMarketManager should auto-install AI
        let market = PluginMarketManager(store: store, userDefaults: defaults)
        #expect(market.isInstalled(id: "ai"))
        #expect(market.isEnabled(id: "ai"))
        #expect(defaults.bool(forKey: "purah.didAutoInstallAIPlugin") == true)
    }
}

@Suite("Onboarding & Launch At Login Tests")
@MainActor
struct OnboardingAndLaunchAtLoginTests {

    @Test("startInteractiveOnboarding disables all pods and enters live editing")
    func testStartInteractiveOnboarding() {
        let suite = "test_onboarding_start_\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = PurahWorkspaceStore(userDefaults: defaults)

        #expect(store.pods.contains(where: { $0.isEnabled }))

        store.startInteractiveOnboarding(clearAllPods: true)

        #expect(store.isOnboardingGuideActive == true)
        #expect(store.isLiveRailEditingMode == true)
        #expect(store.onboardingStep == .firstPod)
        #expect(store.pods.allSatisfy { !$0.isEnabled })
        #expect(store.leftRailPage == 0)
        #expect(store.rightRailPage == 0)
    }

    @Test("Step navigation and rehearsal mechanisms")
    func testStepNavigationAndRehearsals() {
        let suite = "test_onboarding_nav_\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = PurahWorkspaceStore(userDefaults: defaults)

        store.startInteractiveOnboarding(clearAllPods: true)
        #expect(store.onboardingStep == .firstPod)

        store.nextOnboardingStep()
        #expect(store.onboardingStep == .edgeUse)

        store.nextOnboardingStep()
        #expect(store.onboardingStep == .stack)

        store.nextOnboardingStep()
        #expect(store.onboardingStep == .decomposeDemo)

        store.previousOnboardingStep()
        #expect(store.onboardingStep == .stack)

        store.skipCurrentOnboardingStep()
        #expect(store.onboardingStep == .decomposeDemo)

        // Test sample pods mounting rehearsal
        store.rehearseMountSamplePods()
        #expect(store.pods.contains(where: { $0.id == "vitals" && $0.isEnabled && $0.edge == .left }))
        #expect(store.pods.contains(where: { $0.id == "shelf" && $0.isEnabled && $0.edge == .left }))
        #expect(store.pods.contains(where: { $0.id == "calendar" && $0.isEnabled && $0.edge == .right }))
        #expect(store.pods.contains(where: { $0.id == "scripts" && $0.isEnabled && $0.edge == .right }))

        // Test stack merge rehearsal
        store.rehearseStackMerge()
        let leftPods = store.pods.filter { $0.edge == .left && $0.isEnabled }
        #expect(leftPods.count >= 2)
        let groupIds = leftPods.compactMap(\.majorGroupId)
        #expect(!groupIds.isEmpty)

        // The hand step uses the real rail, not the sculptor strip.
        store.selectOnboardingStep(.handAndPermissions)
        #expect(store.onboardingStep == .handAndPermissions)
        #expect(store.isOnboardingGuideShowingAmbientRail == true)

        // Complete onboarding
        store.finishOnboarding(useRecommendedLayout: true)
        #expect(store.hasCompletedOnboarding == true)
        #expect(store.isOnboardingGuideActive == false)
        #expect(store.isLiveRailEditingMode == false)
        #expect(store.isRehearsingBreathingInSculptor == false)
        #expect(store.pods.contains(where: { $0.isEnabled }))
    }

    @Test("Skip all onboarding restores defaults and completes onboarding")
    func testSkipAllOnboardingAndLoadDefaults() {
        let suite = "test_onboarding_skip_\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = PurahWorkspaceStore(userDefaults: defaults)

        store.startInteractiveOnboarding(clearAllPods: true)
        #expect(store.isOnboardingGuideActive == true)

        store.skipAllOnboardingAndLoadDefaults()
        #expect(store.hasCompletedOnboarding == true)
        #expect(store.isOnboardingGuideActive == false)
        #expect(store.isLiveRailEditingMode == false)
        #expect(store.pods.contains(where: { $0.id == "vitals" && $0.isEnabled }))
    }

    @Test("Reset to factory defaults with triggerOnboarding enters onboarding")
    func testResetToFactoryDefaultsWithOnboarding() {
        let suite = "test_reset_onboarding_\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = PurahWorkspaceStore(userDefaults: defaults)

        PurahConfigBackupManager.resetToFactoryDefaults(store: store, defaults: defaults, triggerOnboarding: true)

        #expect(store.isOnboardingGuideActive == true)
        #expect(store.isLiveRailEditingMode == true)
        #expect(store.onboardingStep == .firstPod)
        #expect(store.pods.allSatisfy { !$0.isEnabled })
    }

    @Test("LaunchAtLoginService sets and saves preference")
    func testLaunchAtLoginService() {
        let service = LaunchAtLoginService.shared

        service.setEnabled(true)
        #expect(service.isEnabled == true)
        #expect(UserDefaults.standard.bool(forKey: "purah.launchAtLogin") == true)

        service.setEnabled(false)
        #expect(service.isEnabled == false)
        #expect(UserDefaults.standard.bool(forKey: "purah.launchAtLogin") == false)
    }

    @Test("Hands-on interactive mission completion flags and prerequisite staging")
    func testHandsOnMissionCompletionAndPrerequisiteStaging() {
        let suite = "test_onboarding_missions_\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = PurahWorkspaceStore(userDefaults: defaults)

        store.startInteractiveOnboarding(clearAllPods: true)
        #expect(store.onboardingStep == .firstPod)
        #expect(store.isCurrentOnboardingMissionCompleted == false)

        // Step 0: one pod completes the mount task.
        store.mountPod(id: "vitals", to: .left)
        #expect(store.isCurrentOnboardingMissionCompleted == true)

        // Step 1: one edge open completes the door task; a programmatic open does not.
        store.selectOnboardingStep(.edgeUse)
        #expect(store.isCurrentOnboardingMissionCompleted == false)
        store.activateDrawer(podId: "vitals")
        #expect(store.isCurrentOnboardingMissionCompleted == false)
        store.activateDrawer(podId: "vitals", openedByEdge: true)
        #expect(store.onboardingDidTriggerEdgeDrawer == true)
        #expect(store.isCurrentOnboardingMissionCompleted == true)
        store.dismissActiveDrawer()

        // Step 2: one stack completes the group task.
        store.selectOnboardingStep(.stack)
        let leftPods = store.pods.filter { $0.edge == .left && $0.isEnabled }
        #expect(leftPods.count >= 2)

        store.addPodToMajorGroup(podId: leftPods[1].id, targetPodId: leftPods[0].id)
        #expect(store.onboardingDidCreateStack == true)
        #expect(store.isCurrentOnboardingMissionCompleted == true)

        // Step 3: one toggle completes the shape task.
        store.selectOnboardingStep(.decomposeDemo)
        #expect(store.isPodDecomposed("vitals") == false)
        #expect(store.isCurrentOnboardingMissionCompleted == false)
        store.togglePodDecomposedInSculptor(podId: "vitals")
        #expect(store.onboardingDidToggleDecompose == true)
        #expect(store.isCurrentOnboardingMissionCompleted == true)

        // Step 4: the last step offers choices and is complete immediately.
        store.selectOnboardingStep(.handAndPermissions)
        #expect(store.isCurrentOnboardingMissionCompleted == true)
    }

    @Test("EdgeMouseMonitor's edge path completes the edge-use step")
    func testEdgeMouseMonitorCompletesEdgeUse() {
        let store = PurahWorkspaceStore()
        store.startInteractiveOnboarding(clearAllPods: false)
        #expect(store.isOnboardingGuideActive == true)
        #expect(store.isLiveRailEditingMode == true)

        store.edgeTriggerMode = .hoverDwell
        store.edgeTriggerSensitivity = .agile // 0ms instant hover

        let monitor = EdgeMouseMonitor(store: store, coordinator: nil)
        let visibleRect = NSRect(x: 0, y: 0, width: 1440, height: 900)
        monitor.customTargetVisibleRect = visibleRect

        store.selectOnboardingStep(.edgeUse)
        #expect(store.isOnboardingGuideShowingAmbientRail == true)
        #expect(store.onboardingDidTriggerEdgeDrawer == false)

        let leftLayout = store.resolvedPhysicalLayout(for: .left, totalHeight: 900.0)
        guard let firstLeftPod = leftLayout.first else {
            #expect(Bool(false), "Left rail should have a pod in the edge step")
            return
        }
        let targetY = visibleRect.maxY - CGFloat(firstLeftPod.startY + firstLeftPod.spanH * 0.5)
        let edgePoint = NSPoint(x: 1.0, y: targetY)
        monitor.customCurrentMouseLocation = edgePoint

        monitor.processMouse(point: edgePoint, now: Date(), customVelocity: .zero)
        #expect(store.activeDrawerPodId != nil, "Active drawer should be opened by the edge")
        #expect(store.onboardingDidTriggerEdgeDrawer == true)
        #expect(store.isCurrentOnboardingMissionCompleted == true)
    }

    @Test("toggleTemporaryBreathingSandbox snapshots user pods and restores exact layout")
    func testTemporaryBreathingSandboxSnapshotAndRestore() {
        let store = PurahWorkspaceStore()
        store.startInteractiveOnboarding(clearAllPods: true)

        store.mountPod(id: "terminal", to: .left, announce: false)
        store.mountPod(id: "notes", to: .left, announce: false)
        store.mountPod(id: "music", to: .right, announce: false)
        store.isDynamicBreathingEnabled = false

        // Toggle on the 10-pod sandbox
        store.toggleTemporaryBreathingSandbox()
        #expect(store.isUsingTemporaryDemoSandbox == true)
        #expect(store.isDynamicBreathingEnabled == true)
        let sandboxLeft = store.pods.filter { $0.edge == .left && $0.isEnabled }
        #expect(sandboxLeft.count == 10)

        // Toggle off / restore the snapshot taken at sandbox entry
        store.toggleTemporaryBreathingSandbox()
        #expect(store.isUsingTemporaryDemoSandbox == false)
        // The sandbox turns Dynamic on for the demo and the snapshot puts the
        // person's own setting back, which was off before entry.
        #expect(store.isDynamicBreathingEnabled == false)
        let restoredLeft = store.pods.filter { $0.edge == .left && $0.isEnabled }
        let restoredRight = store.pods.filter { $0.edge == .right && $0.isEnabled }
        #expect(restoredLeft.map(\.id).contains("terminal"))
        #expect(restoredLeft.map(\.id).contains("notes"))
        #expect(restoredLeft.count == 2)
        #expect(restoredRight.map(\.id).contains("music"))
        #expect(restoredRight.count == 1)

        // Also test: opening sandbox then advancing a step auto-restores
        store.toggleTemporaryBreathingSandbox()
        #expect(store.isUsingTemporaryDemoSandbox == true)
        store.selectOnboardingStep(.handAndPermissions)
        #expect(store.isUsingTemporaryDemoSandbox == false)
        let afterEdgeStepLeft = store.pods.filter { $0.edge == .left && $0.isEnabled }
        #expect(afterEdgeStepLeft.map(\.id).contains("terminal"))
        #expect(afterEdgeStepLeft.map(\.id).contains("notes"))
    }

    @Test("isGateTelemetryTrackingEnabled evaluates onboarding calibration and interaction settings telemetry")
    func testGateTelemetryTrackingEvaluation() {
        let store = PurahWorkspaceStore()
        store.isOnboardingGuideActive = false
        store.isInteractionSettingsTelemetryActive = false
        #expect(store.isGateTelemetryTrackingEnabled == false)

        store.isInteractionSettingsTelemetryActive = true
        #expect(store.isGateTelemetryTrackingEnabled == true)

        store.isInteractionSettingsTelemetryActive = false
        store.isOnboardingGuideActive = true
        store.onboardingStep = .handAndPermissions
        #expect(store.isGateTelemetryTrackingEnabled == true)

        store.onboardingStep = .firstPod
        #expect(store.isGateTelemetryTrackingEnabled == false)
    }
}
