// Tests/PurahCoreTests/AlertChannelTests.swift
import Testing
import Foundation
@testable import PurahCore

@MainActor
@Suite("Alert channels")
struct AlertChannelTests {

    private func setPod(_ podId: String, enabled: Bool, in store: PurahWorkspaceStore) throws {
        if let index = store.pods.firstIndex(where: { $0.id == podId }) {
            store.pods[index].isEnabled = enabled
            return
        }
        let manifest = try #require(PurahPluginManifest.builtInCatalog.first { $0.id == podId })
        store.pods.append(manifest.makeDefaultSlotPod(isEnabled: enabled))
    }

    private func makeStore() throws -> (store: PurahWorkspaceStore, defaults: UserDefaults, suite: String) {
        let suite = "alert_channels_\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let store = PurahWorkspaceStore(userDefaults: defaults)
        for podId in ["ai", "terminal", "calendar", "vitals"] {
            try setPod(podId, enabled: true, in: store)
        }
        // Keep delivery assertions about this test only: the sample calendar
        // and the developer machine's vitals must not add their own events.
        store._calendarEvents = []
        store._vitalsEnabledMetrics = []
        store._vitalsThresholds = VitalsColorThresholds(
            cpuDanger: 1.0,
            gpuDanger: 1.0,
            ramDanger: 1.0,
            diskDanger: 1.0,
            batteryLow: 0.0,
            networkDangerMB: 200.0
        )
        return (store, defaults, suite)
    }

    @Test("Master off silences every channel and the rail")
    func testMasterOff() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        var toastCount = 0
        var soundCount = 0
        store.onAlertToast = { _, _ in toastCount += 1 }
        store.onAlertSound = { soundCount += 1 }

        store.isAlertMasterEnabled = false
        store.alertChannels = Set(AlertChannel.allCases)
        store.triggerAlert(id: "ai")

        #expect(!store.isPodAlerting(podId: "ai"))

        store.evaluateAlertDeliveries()
        #expect(toastCount == 0)
        #expect(soundCount == 0)

        // The event was consumed while the master was off. Turning it back on
        // must not replay an alert the person never saw.
        store.isAlertMasterEnabled = true
        store.evaluateAlertDeliveries()
        #expect(toastCount == 0)
        #expect(soundCount == 0)
    }

    @Test("Channels combine independently")
    func testChannelsAreIndependent() throws {
        let toastOnly = try makeStore()
        defer { toastOnly.defaults.removePersistentDomain(forName: toastOnly.suite) }
        var toastCount = 0
        var soundCount = 0
        toastOnly.store.alertChannels = [.toast]
        toastOnly.store.onAlertToast = { _, _ in toastCount += 1 }
        toastOnly.store.onAlertSound = { soundCount += 1 }
        toastOnly.store.triggerAlert(id: "ai")

        #expect(!toastOnly.store.isPodAlerting(podId: "ai"))
        toastOnly.store.evaluateAlertDeliveries()
        #expect(toastCount == 1)
        #expect(soundCount == 0)

        let soundOnly = try makeStore()
        defer { soundOnly.defaults.removePersistentDomain(forName: soundOnly.suite) }
        toastCount = 0
        soundCount = 0
        soundOnly.store.alertChannels = [.sound]
        soundOnly.store.onAlertToast = { _, _ in toastCount += 1 }
        soundOnly.store.onAlertSound = { soundCount += 1 }
        soundOnly.store.triggerAlert(id: "ai")

        #expect(!soundOnly.store.isPodAlerting(podId: "ai"))
        soundOnly.store.evaluateAlertDeliveries()
        #expect(toastCount == 0)
        #expect(soundCount == 1)

        let railOnly = try makeStore()
        defer { railOnly.defaults.removePersistentDomain(forName: railOnly.suite) }
        toastCount = 0
        soundCount = 0
        railOnly.store.alertChannels = [.railEffect]
        railOnly.store.onAlertToast = { _, _ in toastCount += 1 }
        railOnly.store.onAlertSound = { soundCount += 1 }
        railOnly.store.triggerAlert(id: "ai")

        #expect(railOnly.store.isPodAlerting(podId: "ai"))
        railOnly.store.evaluateAlertDeliveries()
        #expect(toastCount == 0)
        #expect(soundCount == 0)
    }

    @Test("Every global channel subset drives exactly its spies and rail effect")
    func testChannelMatrix() throws {
        for mask in 0..<(1 << AlertChannel.allCases.count) {
            let (store, defaults, suite) = try makeStore()
            defer { defaults.removePersistentDomain(forName: suite) }

            let channels = Set(
                AlertChannel.allCases.enumerated().compactMap { index, channel in
                    (mask & (1 << index)) == 0 ? nil : channel
                }
            )
            store.alertChannels = channels

            var toastCount = 0
            var soundCount = 0
            store.onAlertToast = { _, _ in toastCount += 1 }
            store.onAlertSound = { soundCount += 1 }
            store.triggerAlert(id: "ai")

            #expect(store.isPodAlerting(podId: "ai") == channels.contains(.railEffect))
            store.evaluateAlertDeliveries()
            #expect(toastCount == (channels.contains(.toast) ? 1 : 0))
            #expect(soundCount == (channels.contains(.sound) ? 1 : 0))
        }
    }

    @Test("The global channel set is a hard cap over a pod's choices")
    func testGlobalCapWinsOverPodChoice() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        var toastCount = 0
        var soundCount = 0
        store.onAlertToast = { _, _ in toastCount += 1 }
        store.onAlertSound = { soundCount += 1 }

        store.alertChannels = [.toast]
        store.setAlertChannel(.sound, isEnabled: true, forPodId: "ai")
        store.setAlertChannel(.toast, isEnabled: false, forPodId: "ai")
        store.triggerAlert(id: "ai")
        store.evaluateAlertDeliveries()

        #expect(toastCount == 0)
        #expect(soundCount == 0)
    }

    @Test("Per-pod subtraction leaves another pod's toast intact")
    func testPerPodToastSubtraction() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        var messages: [String] = []
        store.onAlertToast = { message, _ in messages.append(message) }
        store.alertChannels = [.toast]
        store.setAlertChannel(.toast, isEnabled: false, forPodId: "ai")

        store.deliverAlert(forPodId: "ai", id: "ai-message", message: "AI")
        store.deliverAlert(forPodId: "terminal", id: "terminal-message", message: "Terminal")

        #expect(messages == ["Terminal"])
    }

    @Test("A silenced pod delivers nothing while another pod still does")
    func testPerPodSilence() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        var toasts: [String] = []
        var soundCount = 0
        store.onAlertToast = { message, _ in toasts.append(message) }
        store.onAlertSound = { soundCount += 1 }

        store.alertChannels = Set(AlertChannel.allCases)
        store.setAlertEnabled(false, forPodId: "ai")
        store.triggerAlert(id: "ai")
        store.triggerAlert(id: "terminal")

        store.evaluateAlertDeliveries()

        #expect(!store.isPodAlerting(podId: "ai"))
        #expect(store.isPodAlerting(podId: "terminal"))
        #expect(toasts.count == 1)
        #expect(soundCount == 1)
    }

    @Test("A sustained event alerts once, then again after it clears and re-enters")
    func testEdgeDetection() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        var toastCount = 0
        var soundCount = 0
        store.onAlertToast = { _, _ in toastCount += 1 }
        store.onAlertSound = { soundCount += 1 }
        store.alertChannels = Set(AlertChannel.allCases)

        store.setPluginAlert(id: "ai", isAlerting: true)
        store.evaluateAlertDeliveries()
        store.evaluateAlertDeliveries()
        #expect(toastCount == 1)
        #expect(soundCount == 1)

        store.acknowledgeAllAlerts(forPodId: "ai")
        store.evaluateAlertDeliveries()
        #expect(toastCount == 1)

        store.setPluginAlert(id: "ai", isAlerting: false)
        store.evaluateAlertDeliveries()

        store.setPluginAlert(id: "ai", isAlerting: true)
        store.evaluateAlertDeliveries()
        #expect(toastCount == 2)
        #expect(soundCount == 2)
    }

    @Test("Quiet hours consume the event instead of replaying it later")
    func testQuietHours() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        var toastCount = 0
        var soundCount = 0
        store.onAlertToast = { _, _ in toastCount += 1 }
        store.onAlertSound = { soundCount += 1 }
        store.alertChannels = Set(AlertChannel.allCases)

        let now = Date()
        let calendar = Calendar.current
        let minute = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        store.quietHours = QuietHours(
            isEnabled: true,
            startMinute: (minute + 1_440 - 60) % 1_440,
            endMinute: (minute + 60) % 1_440
        )
        store.triggerAlert(id: "ai")

        store.evaluateAlertDeliveries(now: now)
        #expect(toastCount == 0)
        #expect(soundCount == 0)

        store.quietHours = QuietHours(isEnabled: false)
        store.evaluateAlertDeliveries(now: now)
        #expect(toastCount == 0)
        #expect(soundCount == 0)
    }

    @Test("A disabled calendar pod delivers no toast or sound")
    func testDisabledCalendarPodDoesNotDeliver() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        try setPod("calendar", enabled: false, in: store)
        let now = Date()
        store._calendarEvents = [
            CalendarEventItem(
                id: "disabled-calendar-event",
                title: "Hidden Meeting",
                startTime: now.addingTimeInterval(5 * 60),
                endTime: now.addingTimeInterval(65 * 60)
            )
        ]
        store.calendarAlertLeadTime = .fifteenMinutes
        store.alertChannels = [.toast, .sound]

        var toastCount = 0
        var soundCount = 0
        store.onAlertToast = { _, _ in toastCount += 1 }
        store.onAlertSound = { soundCount += 1 }

        store.evaluateAlertDeliveries(now: now)

        #expect(toastCount == 0)
        #expect(soundCount == 0)
    }

    @Test("A disabled vitals pod delivers no toast or sound")
    func testDisabledVitalsPodDoesNotDeliver() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        try setPod("vitals", enabled: false, in: store)
        store._vitalsEnabledMetrics = [.cpu]
        store._vitalsThresholds = VitalsColorThresholds(cpuDanger: 0.80)
        store._vitalsMetricsOverride = HardwareVitalsInfo(cpuUsage: 0.99)
        store.alertChannels = [.toast, .sound]

        var toastCount = 0
        var soundCount = 0
        store.onAlertToast = { _, _ in toastCount += 1 }
        store.onAlertSound = { soundCount += 1 }

        store.evaluateAlertDeliveries()

        #expect(toastCount == 0)
        #expect(soundCount == 0)
    }

    @Test("Enabled source pods deliver their active calendar and vitals alerts")
    func testEnabledSourcePodsDeliver() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        let now = Date()
        store._calendarEvents = [
            CalendarEventItem(
                id: "enabled-calendar-event",
                title: "Visible Meeting",
                startTime: now.addingTimeInterval(5 * 60),
                endTime: now.addingTimeInterval(65 * 60)
            )
        ]
        store.calendarAlertLeadTime = .fifteenMinutes
        store._vitalsEnabledMetrics = [.cpu]
        store._vitalsThresholds = VitalsColorThresholds(cpuDanger: 0.80)
        store._vitalsMetricsOverride = HardwareVitalsInfo(cpuUsage: 0.99)
        store.alertChannels = [.toast, .sound]

        var messages: [String] = []
        var soundCount = 0
        store.onAlertToast = { message, _ in messages.append(message) }
        store.onAlertSound = { soundCount += 1 }

        store.evaluateAlertDeliveries(now: now)

        #expect(messages.contains { $0.contains("Visible Meeting") })
        #expect(messages.contains { $0.contains("CPU") })
        #expect(soundCount == 2)
    }

    @Test("Legacy calendar switches migrate to pod channels")
    func testLegacyCalendarSwitchesMigrateToPodChannels() throws {
        let suite = "alert_calendar_legacy_migration_\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let calendarStorage = ScopedPluginStorage(pluginId: "calendar", defaults: defaults)
        calendarStorage.setCodable(false, forKey: "isEventGlowAlertEnabled")
        defaults.set(false, forKey: "purah.isEventToastAlertEnabled")

        let store = PurahWorkspaceStore(userDefaults: defaults)
        #expect(store.allowedChannels(forPodId: "calendar") == [.sound])

        // Once purah.alertChannels exists, upgrading must not re-read the old
        // switches over a choice made in the per-pod card.
        calendarStorage.setCodable(true, forKey: "isEventGlowAlertEnabled")
        defaults.set(true, forKey: "purah.isEventToastAlertEnabled")
        store.savePersistentState()

        let restored = PurahWorkspaceStore(userDefaults: defaults)
        #expect(restored.allowedChannels(forPodId: "calendar") == [.sound])
    }

    @Test("Calendar pod channels are the only gate")
    func testCalendarPodChannelsAreTheOnlyGate() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        var messages: [String] = []
        store.onAlertToast = { message, _ in messages.append(message) }
        store.alertChannels = [.toast]

        let now = Date()
        store._calendarEvents = [
            CalendarEventItem(
                id: "calendar-channel-gate-first",
                title: "First Meeting",
                startTime: now.addingTimeInterval(5 * 60),
                endTime: now.addingTimeInterval(65 * 60)
            )
        ]
        defaults.set(false, forKey: "purah.isEventToastAlertEnabled")
        store.evaluateAlertDeliveries(now: now)

        #expect(messages.count == 1)
        #expect(messages.first?.contains("First Meeting") == true)

        store.setAlertChannel(.toast, isEnabled: false, forPodId: "calendar")
        defaults.set(true, forKey: "purah.isEventToastAlertEnabled")
        store._calendarEvents = [
            CalendarEventItem(
                id: "calendar-channel-gate-second",
                title: "Second Meeting",
                startTime: now.addingTimeInterval(10 * 60),
                endTime: now.addingTimeInterval(70 * 60)
            )
        ]
        store.evaluateAlertDeliveries(now: now)

        #expect(messages.count == 1)
    }

    @Test("An acknowledgment before the next tick consumes the alert")
    func testAcknowledgmentBeforeTickConsumesAlert() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        var toastCount = 0
        var soundCount = 0
        store.alertChannels = [.toast, .sound]
        store.onAlertToast = { _, _ in toastCount += 1 }
        store.onAlertSound = { soundCount += 1 }

        store.triggerAlert(id: "ai")
        store.acknowledgeAllAlerts(forPodId: "ai")
        store.evaluateAlertDeliveries()
        #expect(toastCount == 0)
        #expect(soundCount == 0)

        store.triggerAlert(id: "ai")
        store.evaluateAlertDeliveries()
        #expect(toastCount == 1)
        #expect(soundCount == 1)
    }

    @Test("Priming consumes active conditions without delivering them")
    func testPrimeConsumesActiveConditions() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        store._vitalsEnabledMetrics = [.cpu]
        store._vitalsThresholds = VitalsColorThresholds(cpuDanger: 0.80)
        store._vitalsMetricsOverride = HardwareVitalsInfo(cpuUsage: 0.99)
        store.alertChannels = [.toast, .sound]

        var messages: [String] = []
        var soundCount = 0
        store.onAlertToast = { message, _ in messages.append(message) }
        store.onAlertSound = { soundCount += 1 }

        store.primeAlertDeliveries()
        store.evaluateAlertDeliveries()
        #expect(messages.isEmpty)
        #expect(soundCount == 0)

        store.triggerAlert(id: "ai")
        store.evaluateAlertDeliveries()
        #expect(messages == ["alert.message.generic".localized])
        #expect(soundCount == 1)
    }

    @Test("Migration maps legacy global styles into master and override")
    func testMigration() throws {
        let offSuite = "alert_migration_off_\(UUID().uuidString)"
        let offDefaults = try #require(UserDefaults(suiteName: offSuite))
        defer { offDefaults.removePersistentDomain(forName: offSuite) }
        offDefaults.set("off", forKey: "purah.alertStyle")

        let offStore = PurahWorkspaceStore(userDefaults: offDefaults)
        #expect(!offStore.isAlertMasterEnabled)
        #expect(offDefaults.string(forKey: "purah.alertStyle") == "off")

        let soundSuite = "alert_migration_sound_\(UUID().uuidString)"
        let soundDefaults = try #require(UserDefaults(suiteName: soundSuite))
        defer { soundDefaults.removePersistentDomain(forName: soundSuite) }
        soundDefaults.set("sonarWave", forKey: "purah.alertStyle")
        soundDefaults.set(false, forKey: "purah.isToastSoundEnabled")

        let soundStore = PurahWorkspaceStore(userDefaults: soundDefaults)
        #expect(soundStore.isAlertMasterEnabled)
        #expect(soundStore.alertStyleOverride == .sonarWave)
        #expect(soundStore.alertChannels == [.railEffect, .toast])

        let glowSuite = "alert_migration_glow_\(UUID().uuidString)"
        let glowDefaults = try #require(UserDefaults(suiteName: glowSuite))
        defer { glowDefaults.removePersistentDomain(forName: glowSuite) }
        glowDefaults.set("subtleGlow", forKey: "purah.alertStyle")
        let glowStore = PurahWorkspaceStore(userDefaults: glowDefaults)
        #expect(glowStore.alertStyleOverride == .subtleGlow)

        let breatheSuite = "alert_migration_breathe_\(UUID().uuidString)"
        let breatheDefaults = try #require(UserDefaults(suiteName: breatheSuite))
        defer { breatheDefaults.removePersistentDomain(forName: breatheSuite) }
        breatheDefaults.set("breathingBeacon", forKey: "purah.alertStyle")
        let breatheStore = PurahWorkspaceStore(userDefaults: breatheDefaults)
        #expect(breatheStore.alertStyleOverride == nil)

        let inconsistentSuite = "alert_migration_inconsistent_\(UUID().uuidString)"
        let inconsistentDefaults = try #require(UserDefaults(suiteName: inconsistentSuite))
        defer { inconsistentDefaults.removePersistentDomain(forName: inconsistentSuite) }
        inconsistentDefaults.set("off", forKey: "purah.alertStyle")
        inconsistentDefaults.set(true, forKey: "purah.alertMasterEnabled")

        let inconsistentStore = PurahWorkspaceStore(userDefaults: inconsistentDefaults)
        #expect(inconsistentStore.isAlertMasterEnabled)
        #expect(inconsistentStore.alertStyleOverride == nil)
    }

    @Test("Master, channels, pod channels, override, and disabled pods round-trip")
    func testPersistence() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        store.isAlertMasterEnabled = false
        store.alertChannels = [.toast]
        store.alertStyleOverride = .sonarWave
        store.setAlertChannel(.toast, isEnabled: false, forPodId: "ai")
        store.setAlertEnabled(false, forPodId: "ai")
        store.setAlertEnabled(false, forPodId: "terminal")
        store.savePersistentState()

        let restored = PurahWorkspaceStore(userDefaults: defaults)
        #expect(!restored.isAlertMasterEnabled)
        #expect(restored.alertChannels == [.toast])
        #expect(restored.alertStyleOverride == .sonarWave)
        #expect(restored.allowedChannels(forPodId: "ai") == [.railEffect, .sound])
        #expect(restored.disabledAlertPodIds == ["ai", "terminal"])
        #expect(!restored.isToastSoundEnabled)
    }

    @Test("The old toast sound property is an alias for the sound channel")
    func testToastSoundAlias() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        store.alertChannels = Set(AlertChannel.allCases)
        #expect(store.isToastSoundEnabled)

        store.isToastSoundEnabled = false
        #expect(!store.alertChannels.contains(.sound))
        #expect(!store.isAlertChannelEnabled(.sound))

        store.isToastSoundEnabled = true
        #expect(store.alertChannels.contains(.sound))
        #expect(store.isAlertChannelEnabled(.sound))
    }
}
