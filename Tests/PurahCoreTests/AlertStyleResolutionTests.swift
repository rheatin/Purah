// Tests/PurahCoreTests/AlertStyleResolutionTests.swift
import Testing
import Foundation
@testable import PurahCore
@testable import PurahUI

@MainActor
@Suite("Per-pod edge style")
struct AlertStyleResolutionTests {

    private func makeStore() throws -> (store: PurahWorkspaceStore, defaults: UserDefaults, suite: String) {
        let suite = "pod_alert_style_\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        return (PurahWorkspaceStore(userDefaults: defaults), defaults, suite)
    }

    @Test("Resolution is the pod's pick, then the default, then the declaration, then subtle glow")
    func resolutionOrder() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        // Nothing chosen: the plugin's own declaration answers.
        #expect(store.resolvedAlertStyle(declared: .breathingBeacon, podId: "calendar") == .breathingBeacon)
        #expect(store.resolvedAlertStyle(declared: nil, podId: "calendar") == .subtleGlow)

        // The global default beats the declaration…
        store.alertStyleOverride = .sonarWave
        #expect(store.resolvedAlertStyle(declared: .breathingBeacon, podId: "calendar") == .sonarWave)

        // …and the pod's own choice beats both.
        store.setAlertStyle(.subtleGlow, forPodId: "calendar")
        #expect(store.resolvedAlertStyle(declared: .breathingBeacon, podId: "calendar") == .subtleGlow)
        // A choice is per pod: the neighbour still follows the default.
        #expect(store.resolvedAlertStyle(declared: .breathingBeacon, podId: "vitals") == .sonarWave)
    }

    @Test("Choosing Follow default removes the pod's override")
    func clearingTheOverrideFallsBack() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        store.setAlertStyle(.sonarWave, forPodId: "calendar")
        #expect(store.podAlertStyles["calendar"] == .sonarWave)

        store.setAlertStyle(nil, forPodId: "calendar")
        #expect(store.podAlertStyles["calendar"] == nil)
        #expect(store.resolvedAlertStyle(declared: .breathingBeacon, podId: "calendar") == .breathingBeacon)
    }

    @Test("Per-pod styles round-trip through defaults and a bad name is dropped")
    func persistenceRoundTrip() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        store.setAlertStyle(.sonarWave, forPodId: "calendar")
        store.savePersistentState()

        let reloaded = PurahWorkspaceStore(userDefaults: defaults)
        #expect(reloaded.podAlertStyles["calendar"] == .sonarWave)

        // A style this build no longer knows is ignored, not fatal.
        defaults.set(
            ["calendar": "hologram", "vitals": "breathingBeacon"],
            forKey: "purah.podAlertStyles"
        )
        let tolerant = PurahWorkspaceStore(userDefaults: defaults)
        #expect(tolerant.podAlertStyles["vitals"] == .breathingBeacon)
        #expect(tolerant.podAlertStyles["calendar"] == nil)
    }

    @Test("Calendar's old plugin-scoped style migrates once and never overwrites a newer choice")
    func calendarMigratesLegacyStyle() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        let storage = ScopedPluginStorage(pluginId: "calendar_legacy_test", defaults: defaults)
        storage.setCodable(PluginAlertStyle.sonarWave, forKey: "alertStyle")

        let state = CalendarPluginState(storage: storage, permissionStatus: { .denied })
        state.mount(store: store)

        #expect(store.podAlertStyles["calendar"] == .sonarWave)
        #expect(storage.codable(forKey: "alertStyle", as: PluginAlertStyle.self) == nil)

        // The person then picks something else in the Alerts card. A second
        // mount must not resurrect the migrated legacy value.
        state.unmount(store: store)
        store.setAlertStyle(.breathingBeacon, forPodId: "calendar")
        state.mount(store: store)

        #expect(store.podAlertStyles["calendar"] == .breathingBeacon)
    }
}
