// Tests/PurahCoreTests/SensoryFeedbackTests.swift
import Testing
import AppKit
import Foundation
@testable import PurahCore
@testable import PurahApp

@Suite("Sensory Feedback & Haptics Tests", .serialized)
struct SensoryFeedbackTests {

    @Test("ToastNotificationSound enum properties and localization")
    @MainActor
    func testToastNotificationSoundEnum() {
        let sounds = ToastNotificationSound.allCases
        #expect(sounds.count == 6)
        #expect(ToastNotificationSound.glass.rawValue == "Glass")
        #expect(ToastNotificationSound.tink.rawValue == "Tink")
        #expect(ToastNotificationSound.hero.rawValue == "Hero")
        #expect(ToastNotificationSound.submarine.rawValue == "Submarine")
        #expect(ToastNotificationSound.purr.rawValue == "Purr")
        #expect(ToastNotificationSound.funk.rawValue == "Funk")

        #expect(ToastNotificationSound.glass.displayName == "Glass")
        #expect(ToastNotificationSound.glass.id == "Glass")

        // Test localized names resolve
        LocalizationManager.shared.currentLanguage = .english
        #expect(ToastNotificationSound.glass.localizedName == "Glass (Crystal)")
        #expect(ToastNotificationSound.tink.localizedName == "Tink (Subtle)")
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
        let defaults = UserDefaults.standard
        let store = PurahWorkspaceStore()

        store.isToastSoundEnabled = false
        store.toastNotificationSound = .purr
        store.isTrackpadHapticsEnabled = false
        store.isDrawerPopHapticEnabled = false
        store.isControlHapticEnabled = false
        store.savePersistentState()

        let reloaded = PurahWorkspaceStore()
        #expect(reloaded.isToastSoundEnabled == false)
        #expect(reloaded.toastNotificationSound == .purr)
        #expect(reloaded.isTrackpadHapticsEnabled == false)
        #expect(reloaded.isDrawerPopHapticEnabled == false)
        #expect(reloaded.isControlHapticEnabled == false)

        // Restore to defaults and save
        store.isToastSoundEnabled = true
        store.toastNotificationSound = .glass
        store.isTrackpadHapticsEnabled = true
        store.isDrawerPopHapticEnabled = true
        store.isControlHapticEnabled = true
        store.savePersistentState()

        // Cleanup
        defaults.removeObject(forKey: "purah.isToastSoundEnabled")
        defaults.removeObject(forKey: "purah.toastNotificationSound")
        defaults.removeObject(forKey: "purah.isTrackpadHapticsEnabled")
        defaults.removeObject(forKey: "purah.isDrawerPopHapticEnabled")
        defaults.removeObject(forKey: "purah.isControlHapticEnabled")
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

    @Test("TransientHUDController warning triggers toast sound and freeze triggers levelChange haptic")
    @MainActor
    func testTransientHUDControllerSensoryIntegration() {
        let store = PurahWorkspaceStore()
        let service = SensoryFeedbackService.shared
        service.resetForTesting()

        store.isToastSoundEnabled = true
        store.toastNotificationSound = .tink
        store.isTrackpadHapticsEnabled = true
        store.isControlHapticEnabled = true

        let hud = TransientHUDController.shared
        hud.store = store

        // showWarning triggers toast sound
        hud.showWarning(message: "Test Warning")
        #expect(service.lastPlayedSoundName == "Tink")

        // show(isFrozen:) triggers levelChange control haptic
        hud.show(isFrozen: true)
        #expect(service.lastHapticType == .levelChange)

        hud.dismissImmediate()
    }
}
