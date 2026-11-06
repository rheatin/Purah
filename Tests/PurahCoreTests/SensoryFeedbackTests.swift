// Tests/PurahCoreTests/SensoryFeedbackTests.swift
import Testing
import AppKit
import Foundation
import SwiftUI
@testable import PurahCore
@testable import PurahUI
@testable import PurahApp

@Suite("Sensory Feedback & Haptics Tests", .serialized)
@MainActor
struct SensoryFeedbackTests {

    @Test("ToastNotificationSound enum properties and localization")
    @MainActor
    func testToastNotificationSoundEnum() {
        let sounds = ToastNotificationSound.allCases
        #expect(sounds == [
            .tink, .morse, .pop, .ping, .purr, .frog, .bottle,
            .blow, .basso, .glass, .funk, .sosumi, .hero, .submarine,
        ])
        #expect(ToastNotificationSound.glass.rawValue == "Glass")
        #expect(ToastNotificationSound.tink.rawValue == "Tink")
        #expect(ToastNotificationSound.hero.rawValue == "Hero")
        #expect(ToastNotificationSound.submarine.rawValue == "Submarine")
        #expect(ToastNotificationSound.purr.rawValue == "Purr")
        #expect(ToastNotificationSound.funk.rawValue == "Funk")

        #expect(ToastNotificationSound.glass.displayName == "Glass")
        #expect(ToastNotificationSound.glass.id == "Glass")

        let loc = LocalizationManager.shared
        let savedLanguage = loc.currentLanguage
        defer { loc.currentLanguage = savedLanguage }
        for language in AppLanguage.allCases where language != .system {
            loc.currentLanguage = language
            for sound in sounds {
                #expect(
                    !sound.localizedName.hasPrefix("sound."),
                    "\(sound.rawValue) has no name in \(language.rawValue)"
                )
            }
        }

        loc.currentLanguage = .english
        #expect(ToastNotificationSound.glass.localizedName == "Glass (Crystal)")
        #expect(ToastNotificationSound.tink.localizedName == "Tink (Subtle)")
        #expect(ToastNotificationSound.morse.localizedName == "Morse (Beep)")
        #expect(ToastNotificationSound.pop.localizedName == "Pop (Pop)")
        #expect(ToastNotificationSound.ping.localizedName == "Ping (Ping)")
        #expect(ToastNotificationSound.frog.localizedName == "Frog (Croak)")
        #expect(ToastNotificationSound.bottle.localizedName == "Bottle (Hollow)")
        #expect(ToastNotificationSound.blow.localizedName == "Blow (Breeze)")
        #expect(ToastNotificationSound.basso.localizedName == "Basso (Deep)")
        #expect(ToastNotificationSound.sosumi.localizedName == "Sosumi (Classic)")
        #expect(ToastNotificationSound.hero.localizedName == "Hero (Prominent)")
        #expect(ToastNotificationSound.submarine.localizedName == "Submarine (Sonar)")
        #expect(ToastNotificationSound.purr.localizedName == "Purr (Soft)")
        #expect(ToastNotificationSound.funk.localizedName == "Funk (Pop)")
    }

    @Test("SensoryFeedbackService toast sound playback gating")
    @MainActor
    func testPlayToastSoundGating() {
        let service = SensoryFeedbackService.shared
        service.resetForTesting()

        // Disabled
        let disabledResult = service.playToastSound(.glass, enabled: false)
        #expect(disabledResult == false)
        #expect(service.lastPlayedSoundName == nil)

        // Enabled
        let enabledResult = service.playToastSound(.hero, enabled: true)
        #expect(enabledResult == true)
        #expect(service.lastPlayedSoundName == "Hero")
    }

    @Test("SensoryFeedbackService edge pop haptic cooldown and trigger mode selection")
    @MainActor
    func testEdgePopHapticCooldownAndModeSelection() {
        let service = SensoryFeedbackService.shared
        service.resetForTesting()

        let baseTime = Date()

        // 1. Initial push force pop should use levelChange
        let result1 = service.performEdgePopHaptic(
            triggerMode: .pushForce,
            enabled: true,
            isInitialOpen: true,
            now: baseTime
        )
        #expect(result1 == true)
        #expect(service.lastHapticType == .levelChange)
        #expect(service.hapticTriggerCount == 1)

        // 2. Immediate call within 180ms cooldown should be rejected
        let tooEarlyTime = baseTime.addingTimeInterval(0.10)
        let result2 = service.performEdgePopHaptic(
            triggerMode: .pushForce,
            enabled: true,
            isInitialOpen: true,
            now: tooEarlyTime
        )
        #expect(result2 == false)
        #expect(service.hapticTriggerCount == 1)

        // 3. Call after 180ms cooldown should succeed
        let afterCooldownTime = baseTime.addingTimeInterval(0.20)
        let result3 = service.performEdgePopHaptic(
            triggerMode: .hoverDwell,
            enabled: true,
            isInitialOpen: true,
            now: afterCooldownTime
        )
        #expect(result3 == true)
        #expect(service.lastHapticType == .alignment)
        #expect(service.hapticTriggerCount == 2)

        // 4. Non-initial open with push force should fall back to alignment
        let time4 = afterCooldownTime.addingTimeInterval(0.20)
        let result4 = service.performEdgePopHaptic(
            triggerMode: .pushForce,
            enabled: true,
            isInitialOpen: false,
            now: time4
        )
        #expect(result4 == true)
        #expect(service.lastHapticType == .alignment)
        #expect(service.hapticTriggerCount == 3)
    }

    @Test("SensoryFeedbackService action haptic execution")
    @MainActor
    func testActionHapticExecution() {
        let service = SensoryFeedbackService.shared
        service.resetForTesting()

        #expect(service.performActionHaptic(.alignment, enabled: false) == false)
        #expect(service.hapticTriggerCount == 0)

        #expect(service.performActionHaptic(.generic, enabled: true) == true)
        #expect(service.lastHapticType == .generic)
        #expect(service.hapticTriggerCount == 1)

        #expect(service.performActionHaptic(.levelChange, enabled: true) == true)
        #expect(service.lastHapticType == .levelChange)
        #expect(service.hapticTriggerCount == 2)
    }

    @Test("PurahWorkspaceStore sensory gating and preview helpers")
    @MainActor
    func testWorkspaceStoreSensoryGating() {
        let store = PurahWorkspaceStore()
        let service = SensoryFeedbackService.shared
        service.resetForTesting()

        // Master haptics toggle disabled
        store.isTrackpadHapticsEnabled = false
        store.isDrawerPopHapticEnabled = true
        store.isControlHapticEnabled = true
        #expect(store.triggerEdgePopHaptic() == false)
        #expect(store.triggerControlHaptic(.alignment) == false)

        // Master haptics enabled, drawer pop disabled
        store.isTrackpadHapticsEnabled = true
        store.isDrawerPopHapticEnabled = false
        #expect(store.triggerEdgePopHaptic() == false)

        // Master haptics enabled, control haptics disabled
        store.isControlHapticEnabled = false
        #expect(store.triggerControlHaptic(.alignment) == false)

        // Both enabled
        store.isDrawerPopHapticEnabled = true
        store.isControlHapticEnabled = true
        #expect(store.triggerControlHaptic(.alignment) == true)
        #expect(service.lastHapticType == .alignment)

        // Toast sound gating
        store.isToastSoundEnabled = false
        store.toastNotificationSound = .submarine
        #expect(store.triggerToastSound() == false)

        // Preview sound forces sound even if toast sound is disabled
        #expect(store.previewToastSound() == true)
        #expect(service.lastPlayedSoundName == "Submarine")

        store.isToastSoundEnabled = true
        #expect(store.triggerToastSound() == true)
    }

    @Test("PurahWorkspaceStore sensory properties persistence round-trip")
    @MainActor
    func testSensoryPropertiesPersistence() {
        let suite = "purah.sensory.persistence.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PurahWorkspaceStore(userDefaults: defaults)

        store.isToastSoundEnabled = false
        store.toastNotificationSound = .purr
        store.isTrackpadHapticsEnabled = false
        store.isDrawerPopHapticEnabled = false
        store.isControlHapticEnabled = false
        store.savePersistentState()

        let reloaded = PurahWorkspaceStore(userDefaults: defaults)
        #expect(reloaded.isToastSoundEnabled == false)
        #expect(reloaded.toastNotificationSound == .purr)
        #expect(reloaded.isTrackpadHapticsEnabled == false)
        #expect(reloaded.isDrawerPopHapticEnabled == false)
        #expect(reloaded.isControlHapticEnabled == false)
    }

    @Test("A pod's alert sound follows its override, then the default again")
    @MainActor
    func testPerPodAlertSoundResolution() throws {
        let suite = "purah.pod-alert-sound.resolution.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = PurahWorkspaceStore(userDefaults: defaults)
        store.toastNotificationSound = .purr

        #expect(store.resolvedAlertSound(forPodId: "ai") == .purr)

        store.setAlertSound(.hero, forPodId: "ai")
        #expect(store.resolvedAlertSound(forPodId: "ai") == .hero)
        #expect(store.resolvedAlertSound(forPodId: "terminal") == .purr)

        store.setAlertSound(nil, forPodId: "ai")
        #expect(store.resolvedAlertSound(forPodId: "ai") == .purr)
    }

    @Test("Per-pod alert sounds round-trip through persistence")
    @MainActor
    func testPerPodAlertSoundPersistence() throws {
        let suite = "purah.pod-alert-sound.persistence.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = PurahWorkspaceStore(userDefaults: defaults)
        store.toastNotificationSound = .glass
        store.setAlertSound(.sosumi, forPodId: "ai")
        store.setAlertSound(.frog, forPodId: "calendar")
        store.savePersistentState()

        let restored = PurahWorkspaceStore(userDefaults: defaults)
        #expect(restored.resolvedAlertSound(forPodId: "ai") == .sosumi)
        #expect(restored.resolvedAlertSound(forPodId: "calendar") == .frog)
        #expect(restored.resolvedAlertSound(forPodId: "terminal") == .glass)
    }

    @Test("EdgeMouseMonitor triggers edge pop haptics on drawer activation from docked state")
    @MainActor
    func testEdgeMouseMonitorPopHapticTrigger() {
        let store = PurahWorkspaceStore()
        let service = SensoryFeedbackService.shared
        service.resetForTesting()

        store.activeDrawerPodId = nil
        store.activeDrawerItemId = nil
        store.isTrackpadHapticsEnabled = true
        store.isDrawerPopHapticEnabled = true
        store.edgeTriggerMode = .pushForce

        let monitor = EdgeMouseMonitor(store: store)
        let layoutItems = store.resolvedPhysicalLayout(for: .left, totalHeight: 900.0)
        guard let firstItem = layoutItems.first else {
            Issue.record("No layout item found on left rail")
            return
        }

        // Activate drawer from docked state
        monitor.activatePodDrawer(
            candidate: firstItem.pod,
            matched: firstItem,
            currentWindowY: CGFloat(firstItem.startY + 10.0),
            edge: .left
        )

        #expect(service.hapticTriggerCount == 1)
        #expect(service.lastHapticType == .levelChange)

        // When isDrawerPopHapticEnabled is false, no haptic should fire
        service.resetForTesting()
        store.isDrawerPopHapticEnabled = false
        store.activeDrawerPodId = nil
        store.activeDrawerItemId = nil

        monitor.activatePodDrawer(
            candidate: firstItem.pod,
            matched: firstItem,
            currentWindowY: CGFloat(firstItem.startY + 10.0),
            edge: .left
        )

        #expect(service.hapticTriggerCount == 0)
    }

    @Test("HUD-side feedback reaches toast sound and freeze haptic seams")
    @MainActor
    func testTransientHUDControllerSensoryIntegration() {
        let suite = "purah.sensory.hud.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PurahWorkspaceStore(userDefaults: defaults)
        let service = SensoryFeedbackService.shared
        service.resetForTesting()

        store.isToastSoundEnabled = true
        store.toastNotificationSound = .tink
        store.isTrackpadHapticsEnabled = true
        store.isControlHapticEnabled = true

        // These are the two calls the HUD makes; exercising them directly
        // keeps a real non-activating panel out of the test run.
        #expect(store.triggerToastSound())
        #expect(service.lastPlayedSoundName == "Tink")

        #expect(store.triggerControlHaptic(.levelChange))
        #expect(service.lastHapticType == .levelChange)
    }

    @Test("PurahPluginContext accurately reflects store sensory state properties")
    @MainActor
    func testPurahPluginContextSensoryStateReflection() {
        let store = PurahWorkspaceStore()
        guard let pod = store.pods.first else {
            Issue.record("No default pod in store")
            return
        }

        // 1. Initial defaults reflection
        store.podAlertSounds.removeAll()
        store.isToastSoundEnabled = true
        store.isTrackpadHapticsEnabled = true
        store.isControlHapticEnabled = true
        store.isDrawerPopHapticEnabled = true
        store.toastNotificationSound = .glass

        let context1 = PurahPluginContext(
            pod: pod,
            edge: .right,
            railWidth: 8.0,
            slotHeight: 80.0,
            drawerWidth: 320.0,
            isExpanded: false,
            isPinned: false,
            accentColor: .blue,
            palette: ThemeManager.shared.palette,
            store: store,
            requestExpand: {},
            requestDismiss: {},
            togglePin: {}
        )

        #expect(context1.isSoundEnabled == true)
        #expect(context1.isHapticsEnabled == true)
        #expect(context1.isControlHapticEnabled == true)
        #expect(context1.isDrawerPopHapticEnabled == true)
        #expect(context1.notificationSound == ToastNotificationSound.glass)

        // 2. Custom sensory configuration reflection
        store.isToastSoundEnabled = false
        store.isTrackpadHapticsEnabled = true
        store.isControlHapticEnabled = false
        store.isDrawerPopHapticEnabled = false
        store.podAlertSounds.removeAll()
        store.toastNotificationSound = .submarine

        let context2 = PurahPluginContext(
            pod: pod,
            edge: .right,
            railWidth: 8.0,
            slotHeight: 80.0,
            drawerWidth: 320.0,
            isExpanded: false,
            isPinned: false,
            accentColor: .blue,
            palette: ThemeManager.shared.palette,
            store: store,
            requestExpand: {},
            requestDismiss: {},
            togglePin: {}
        )

        #expect(context2.isSoundEnabled == false)
        #expect(context2.isHapticsEnabled == false)
        #expect(context2.isControlHapticEnabled == false)
        #expect(context2.isDrawerPopHapticEnabled == false)
        #expect(context2.notificationSound == ToastNotificationSound.submarine)

        // 3. Master trackpad haptics disables all derived haptic states
        store.isTrackpadHapticsEnabled = false
        store.isControlHapticEnabled = true
        store.isDrawerPopHapticEnabled = true

        let context3 = PurahPluginContext(
            pod: pod,
            edge: .right,
            railWidth: 8.0,
            slotHeight: 80.0,
            drawerWidth: 320.0,
            isExpanded: false,
            isPinned: false,
            accentColor: .blue,
            palette: ThemeManager.shared.palette,
            store: store,
            requestExpand: {},
            requestDismiss: {},
            togglePin: {}
        )

        #expect(context3.isHapticsEnabled == false)
        #expect(context3.isControlHapticEnabled == false)
        #expect(context3.isDrawerPopHapticEnabled == false)
    }

    @Test("PurahPluginContext playSound triggers configured sound and respects gating")
    @MainActor
    func testPurahPluginContextPlaySound() {
        let store = PurahWorkspaceStore()
        let service = SensoryFeedbackService.shared
        service.resetForTesting()

        guard let pod = store.pods.first else {
            Issue.record("No default pod in store")
            return
        }

        store.isToastSoundEnabled = true
        store.podAlertSounds.removeAll()
        store.toastNotificationSound = .hero

        let context = PurahPluginContext(
            pod: pod,
            edge: .right,
            railWidth: 8.0,
            slotHeight: 80.0,
            drawerWidth: 320.0,
            isExpanded: false,
            isPinned: false,
            accentColor: .blue,
            palette: ThemeManager.shared.palette,
            store: store,
            requestExpand: {},
            requestDismiss: {},
            togglePin: {}
        )

        // Calling playSound() without arguments plays the store default sound (.hero)
        context.playSound()
        #expect(service.lastPlayedSoundName == "Hero")

        store.setAlertSound(.frog, forPodId: pod.id)
        context.playSound()
        #expect(service.lastPlayedSoundName == "Frog")

        // Calling playSound(.submarine) overrides with the specified sound
        context.playSound(.submarine)
        #expect(service.lastPlayedSoundName == "Submarine")

        // Disabling toast sound suppresses playback
        service.resetForTesting()
        store.isToastSoundEnabled = false

        context.playSound()
        #expect(service.lastPlayedSoundName == nil)

        context.playSound(.tink)
        #expect(service.lastPlayedSoundName == nil)
    }

    @Test("PurahPluginContext and SensoryFeedbackService control haptic gating")
    @MainActor
    func testControlHapticGating() {
        let store = PurahWorkspaceStore()
        let service = SensoryFeedbackService.shared
        service.resetForTesting()

        guard let pod = store.pods.first else {
            Issue.record("No default pod in store")
            return
        }

        // 1. When haptics are enabled on store
        store.isTrackpadHapticsEnabled = true
        store.isControlHapticEnabled = true

        let context = PurahPluginContext(
            pod: pod,
            edge: .right,
            railWidth: 8.0,
            slotHeight: 80.0,
            drawerWidth: 320.0,
            isExpanded: false,
            isPinned: false,
            accentColor: .blue,
            palette: ThemeManager.shared.palette,
            store: store,
            requestExpand: {},
            requestDismiss: {},
            togglePin: {}
        )

        context.performHaptic(.alignment)
        #expect(service.hapticTriggerCount == 1)
        #expect(service.lastHapticType == .alignment)

        // 2. When control haptics are disabled on store
        store.isControlHapticEnabled = false
        context.performHaptic(.levelChange)
        #expect(service.hapticTriggerCount == 1) // unchanged

        // 3. Test SensoryFeedbackService.shared.performControlHapticIfEnabled with custom UserDefaults
        let testSuiteName = "com.purah.test.sensory.\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: testSuiteName)!
        defer {
            testDefaults.removePersistentDomain(forName: testSuiteName)
        }

        service.resetForTesting()

        // By default (nil in userDefaults), defaults are true
        let defaultResult = service.performControlHapticIfEnabled(.alignment, defaults: testDefaults)
        #expect(defaultResult == true)
        #expect(service.hapticTriggerCount == 1)
        #expect(service.lastHapticType == .alignment)

        // Explicitly set control haptics to false
        testDefaults.set(false, forKey: "purah.isControlHapticEnabled")
        let disabledControlResult = service.performControlHapticIfEnabled(.levelChange, defaults: testDefaults)
        #expect(disabledControlResult == false)
        #expect(service.hapticTriggerCount == 1)

        // Explicitly set master haptics to false, control to true
        testDefaults.set(true, forKey: "purah.isControlHapticEnabled")
        testDefaults.set(false, forKey: "purah.isTrackpadHapticsEnabled")
        let disabledMasterResult = service.performControlHapticIfEnabled(.levelChange, defaults: testDefaults)
        #expect(disabledMasterResult == false)
        #expect(service.hapticTriggerCount == 1)

        // Both true
        testDefaults.set(true, forKey: "purah.isTrackpadHapticsEnabled")
        testDefaults.set(true, forKey: "purah.isControlHapticEnabled")
        let bothEnabledResult = service.performControlHapticIfEnabled(.levelChange, defaults: testDefaults)
        #expect(bothEnabledResult == true)
        #expect(service.hapticTriggerCount == 2)
        #expect(service.lastHapticType == .levelChange)
    }
}
