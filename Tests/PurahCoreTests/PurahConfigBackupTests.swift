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

        #expect(backup.schemaVersion == 1)
        #expect(backup.appVersion == "0.2.0")
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
        #expect(store.drawerWidthMode == .fixed)
        #expect(store.leftRailPage == 0)
        #expect(defaults.string(forKey: "purah.customKey") == nil)
        #expect(defaults.bool(forKey: "purah.didAutoInstallAIPlugin") == true)
        #expect(store.pods.contains(where: { $0.id == "ai" && $0.isEnabled }))
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
        #expect(store.onboardingStep == .mountPods)
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
        #expect(store.onboardingStep == .mountPods)

        store.nextOnboardingStep()
        #expect(store.onboardingStep == .decomposeDemo)

        store.nextOnboardingStep()
        #expect(store.onboardingStep == .stackDemo)

        store.previousOnboardingStep()
        #expect(store.onboardingStep == .decomposeDemo)

        store.skipCurrentOnboardingStep()
        #expect(store.onboardingStep == .stackDemo)

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

        // Test pagination flip rehearsal
        store.rehearsePaginationFlip()
        #expect(store.isRightTopPortalRevealed == true)
        #expect(store.isRightBottomPortalRevealed == true)

        // Step 6 anti-touch calibration sets rehearsal breathing flag for live testing
        store.selectOnboardingStep(.antiTouchCalibration)
        #expect(store.onboardingStep == .antiTouchCalibration)
        #expect(store.isRehearsingBreathingInSculptor == true)

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
        #expect(store.onboardingStep == .mountPods)
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
        #expect(store.onboardingStep == .mountPods)
        #expect(store.isCurrentOnboardingMissionCompleted == false)

        // Step 1: Mount pods on both sides
        store.mountPod(id: "vitals", to: .left)
        #expect(store.isCurrentOnboardingMissionCompleted == false)
        store.mountPod(id: "calendar", to: .right)
        #expect(store.isCurrentOnboardingMissionCompleted == true)

        // Step 2: Decompose demo
        store.selectOnboardingStep(.decomposeDemo)
        #expect(store.pods.contains(where: { $0.id == "vitals" && $0.isEnabled && $0.edge == .left }))
        #expect(store.pods.contains(where: { $0.id == "scripts" && $0.isEnabled && $0.edge == .right }))
        #expect(store.isPodDecomposed("vitals") == false)
        #expect(store.isCurrentOnboardingMissionCompleted == false)

        store.togglePodDecomposedInSculptor(podId: "vitals")
        #expect(store.onboardingDidToggleDecompose == true)
        #expect(store.isCurrentOnboardingMissionCompleted == true)

        // Step 3: Stack demo
        store.selectOnboardingStep(.stackDemo)
        let leftPods = store.pods.filter { $0.edge == .left && $0.isEnabled }
        #expect(leftPods.count >= 2)
        #expect(store.onboardingDidCreateStack == false)

        store.addPodToMajorGroup(podId: leftPods[1].id, targetPodId: leftPods[0].id)
        #expect(store.onboardingDidCreateStack == true)
        #expect(store.isCurrentOnboardingMissionCompleted == true)

        // Step 4: Page demo
        store.selectOnboardingStep(.pageDemo)
        let rightPods = store.pods.filter { $0.edge == .right && $0.isEnabled }
        #expect(rightPods.count >= 2)
        #expect(store.isCurrentOnboardingMissionCompleted == false)

        store.setPodPage(id: rightPods[0].id, pageIndex: 1)
        #expect(store.onboardingDidCreatePage == true)
        #expect(store.isCurrentOnboardingMissionCompleted == false)

        store.setRailPage(1, for: .right)
        #expect(store.onboardingDidSwitchPage == true)
        #expect(store.isCurrentOnboardingMissionCompleted == true)

        // Step 5: Breathing demo
        store.selectOnboardingStep(.breathingDemo)
        #expect(store.isDynamicBreathingEnabled == true)
        #expect(store.isAlwaysCompactBreathing == false)
        #expect(store.isRehearsingBreathingInSculptor == true)
        #expect(store.isCurrentOnboardingMissionCompleted == false)

        store.activateDrawer(podId: "vitals")
        #expect(store.onboardingBreathingHoveredPods.count == 1)
        #expect(store.isCurrentOnboardingMissionCompleted == false)
        store.activateDrawer(podId: "shelf")
        #expect(store.onboardingBreathingHoveredPods.count >= 2)
        #expect(store.isCurrentOnboardingMissionCompleted == true)

        // Step 6: Anti-touch calibration
        store.selectOnboardingStep(.antiTouchCalibration)
        #expect(store.isAlwaysCompactBreathing == false)
        #expect(store.isRehearsingBreathingInSculptor == true)
        #expect(store.isCurrentOnboardingMissionCompleted == false)

        store.activateDrawer(podId: "vitals")
        #expect(store.onboardingDidTriggerEdgeDrawer == true)
        #expect(store.isCurrentOnboardingMissionCompleted == true)
    }

    @Test("EdgeMouseMonitor responds to live edge hover during onboarding rehearsals (Step 5 & Step 6)")
    func testEdgeMouseMonitorDuringOnboardingRehearsals() {
        let store = PurahWorkspaceStore()
        store.startInteractiveOnboarding(clearAllPods: false)
        #expect(store.isOnboardingGuideActive == true)
        #expect(store.isLiveRailEditingMode == true)

        store.edgeTriggerMode = .hoverDwell
        store.edgeTriggerSensitivity = .agile // 0ms instant hover

        let monitor = EdgeMouseMonitor(store: store, coordinator: nil)
        let visibleRect = NSRect(x: 0, y: 0, width: 1440, height: 900)
        monitor.customTargetVisibleRect = visibleRect

        // Step 5: Breathing Demo
        store.selectOnboardingStep(.breathingDemo)
        #expect(store.isRehearsingBreathingInSculptor == true)
        #expect(store.onboardingBreathingHoveredPods.isEmpty == true)

        let leftLayout = store.resolvedPhysicalLayout(for: .left, totalHeight: 900.0)
        guard let firstLeftPod = leftLayout.first else {
            #expect(Bool(false), "Left rail should have pods in breathing demo")
            return
        }
        let targetY = visibleRect.maxY - CGFloat(firstLeftPod.startY + firstLeftPod.spanH * 0.5)
        let edgePoint = NSPoint(x: 1.0, y: targetY)
        monitor.customCurrentMouseLocation = edgePoint

        monitor.processMouse(point: edgePoint, now: Date(), customVelocity: .zero)
        #expect(store.activeDrawerPodId != nil, "Active drawer should be opened by edge hover in breathing demo")
        #expect(store.onboardingBreathingHoveredPods.count >= 1, "Hovered pod should be recorded in onboardingBreathingHoveredPods")

        // Step 6: Anti-touch Calibration
        store.dismissActiveDrawer()
        store.selectOnboardingStep(.antiTouchCalibration)
        #expect(store.isRehearsingBreathingInSculptor == true)
        #expect(store.onboardingDidTriggerEdgeDrawer == false)

        let t0 = Date()
        monitor.processMouse(point: edgePoint, now: t0, customVelocity: .zero)
        monitor.processMouse(point: edgePoint, now: t0.addingTimeInterval(0.18), customVelocity: .zero)
        #expect(store.activeDrawerPodId != nil, "Active drawer should be opened by edge hover in anti-touch calibration")
        #expect(store.onboardingDidTriggerEdgeDrawer == true, "onboardingDidTriggerEdgeDrawer should be set to true")
    }
}
