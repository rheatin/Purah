// Tests/PurahCoreTests/PerPodAlertToggleTests.swift
import Testing
import Foundation
@testable import PurahCore
@testable import PurahUI

@MainActor
@Suite("Per-pod alert toggle")
struct PerPodAlertToggleTests {

    private func makeStore() throws -> (store: PurahWorkspaceStore, defaults: UserDefaults, suite: String) {
        let suite = "per_pod_alert_\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        return (PurahWorkspaceStore(userDefaults: defaults), defaults, suite)
    }

    @Test("A pod alerts by default while the master switch is on")
    func testDefaultAlerting() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(store.isAlertMasterEnabled)
        store.triggerAlert(id: "ai")
        #expect(store.isPodAlerting(podId: "ai"))
    }

    @Test("Disabling one pod leaves every other pod alerting")
    func testDisablingOnePodSilencesOnlyThatPod() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        store.triggerAlert(id: "ai")
        store.triggerAlert(id: "terminal")
        store.setAlertEnabled(false, forPodId: "ai")

        #expect(!store.isPodAlerting(podId: "ai"))
        #expect(store.isPodAlerting(podId: "terminal"))
        #expect(store.isAnyRailAlerting)
    }

    @Test("The master switch wins over every per-pod switch")
    func testMasterSwitchWins() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        store.triggerAlert(id: "ai")
        store.triggerAlert(id: "terminal")
        store.setAlertEnabled(false, forPodId: "terminal")
        store.isAlertMasterEnabled = false

        #expect(!store.isAlertEnabled(forPodId: "ai"))
        #expect(!store.isAlertEnabled(forPodId: "terminal"))
        #expect(!store.isPodAlerting(podId: "ai"))
        #expect(!store.isPodAlerting(podId: "terminal"))
        #expect(!store.isAnyRailAlerting)
    }

    @Test("Re-enabling does not replay an alert raised while disabled")
    func testReenableDoesNotReplayPendingAlert() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        store.triggerAlert(id: "ai")
        store.setAlertEnabled(false, forPodId: "ai")

        // Arrives while the pod is silenced. Turning the switch back on must
        // not surface it; only a fresh event may alert.
        store.triggerAlert(id: "ai")
        store.setAlertEnabled(true, forPodId: "ai")
        #expect(!store.isPodAlerting(podId: "ai"))

        store.triggerAlert(id: "ai")
        #expect(store.isPodAlerting(podId: "ai"))
    }

    @Test("Turning a pod on with no channels restores all three, while off keeps choices")
    func testEmptyChannelSetRestoresOnEnable() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        store.podAlertChannels["ai"] = []
        store.setAlertEnabled(true, forPodId: "ai")
        #expect(store.allowedChannels(forPodId: "ai") == Set(AlertChannel.allCases))

        store.podAlertChannels["ai"] = [.toast]
        store.setAlertEnabled(false, forPodId: "ai")
        #expect(store.allowedChannels(forPodId: "ai") == [.toast])
    }

    @Test("Disabled pod ids survive persistence and global style changes")
    func testPersistence() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        store.setAlertEnabled(false, forPodId: "ai")
        store.setAlertEnabled(false, forPodId: "terminal")
        store.savePersistentState()

        let restored = PurahWorkspaceStore(userDefaults: defaults)
        #expect(restored.disabledAlertPodIds == ["ai", "terminal"])

        restored.isAlertMasterEnabled = false
        restored.isAlertMasterEnabled = true
        #expect(restored.disabledAlertPodIds == ["ai", "terminal"])
    }

    @Test("Style resolution prefers an override, then the plugin, then subtle glow")
    func testStyleResolution() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        store.alertStyleOverride = nil
        #expect(store.resolvedAlertStyle(declared: .breathingBeacon, podId: "vitals") == .breathingBeacon)
        #expect(store.resolvedAlertStyle(declared: nil, podId: "vitals") == .subtleGlow)

        store.alertStyleOverride = .sonarWave
        #expect(store.resolvedAlertStyle(declared: .breathingBeacon, podId: "vitals") == .sonarWave)
        #expect(store.resolvedAlertStyle(declared: nil, podId: "vitals") == .sonarWave)
    }

    @Test("Built-in plugins declare their own edge voices")
    func testBuiltInStyles() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(HardwareVitalsPlugin().alertStyle(store: store) == .breathingBeacon)
        let calendarState = CalendarPluginState(
            storage: ScopedPluginStorage(pluginId: "calendar", defaults: defaults)
        )
        #expect(CalendarPlugin(state: calendarState).alertStyle(store: store) == .sonarWave)
        #expect(AIAssistantPlugin().alertStyle(store: store) == .subtleGlow)
        #expect(TerminalPlugin().alertStyle(store: store) == .subtleGlow)

        let catalog = Dictionary(
            uniqueKeysWithValues: PurahPluginManifest.builtInCatalog.map { ($0.id, $0.alertStyle) }
        )
        #expect(catalog["vitals"] == .breathingBeacon)
        #expect(catalog["calendar"] == .sonarWave)
        #expect(catalog["ai"] == .subtleGlow)
        #expect(catalog["terminal"] == .subtleGlow)
    }

    @Test("A pod with its edge channel off does not draw a rail alert")
    func testEdgeChannelOffDrawsNothing() throws {
        let (store, defaults, suite) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }

        store.setAlertChannel(.railEffect, isEnabled: false, forPodId: "ai")
        store.triggerAlert(id: "ai")

        #expect(!store.isPodAlerting(podId: "ai"))
        #expect(store.isAlertChannelEnabled(.railEffect, forPodId: "ai") == false)
    }

    @Test("supportsAlerts decodes as false when absent and true when declared")
    func testManifestDecoding() throws {
        let base: [String: Any] = [
            "id": "com.example.test",
            "displayName": "Test Pod",
            "systemIcon": "bell",
            "author": "Test",
            "version": "1.0.0",
            "description": "A manifest used by the per-pod alert tests.",
            "defaultEdge": "left",
            "preferredZone": "glance",
            "ergonomicWeight": 35.0,
            "minLengthRatio": 0.1,
            "defaultColorHex": "#FFFFFF"
        ]

        func decode(_ extra: [String: Any]) throws -> PurahPluginManifest {
            var payload = base
            payload.merge(extra) { _, new in new }
            let data = try JSONSerialization.data(withJSONObject: payload)
            return try JSONDecoder().decode(PurahPluginManifest.self, from: data)
        }

        let withoutDeclaration = try decode([:])
        #expect(!withoutDeclaration.supportsAlerts)

        let withDeclaration = try decode(["supportsAlerts": true])
        #expect(withDeclaration.supportsAlerts)

        #expect(withoutDeclaration.alertStyle == nil)
        let offDeclaration = try decode(["alertStyle": "off"])
        let sonarDeclaration = try decode(["alertStyle": "sonarWave"])
        let invalidDeclaration = try decode(["alertStyle": "not-a-style"])
        #expect(offDeclaration.alertStyle == nil)
        #expect(sonarDeclaration.alertStyle == .sonarWave)
        #expect(invalidDeclaration.alertStyle == nil)
    }

    @Test("Exactly the four alerting built-ins declare support")
    func testBuiltInAlertDeclarations() {
        let alerting = PurahPluginManifest.builtInCatalog
            .filter(\.supportsAlerts)
            .map(\.id)
            .sorted()
        #expect(alerting == ["ai", "calendar", "terminal", "vitals"])

        #expect(HardwareVitalsPlugin().manifest.supportsAlerts)
        #expect(TerminalPlugin().manifest.supportsAlerts)
        #expect(CalendarPlugin().manifest.supportsAlerts)
        #expect(AIAssistantPlugin().manifest.supportsAlerts)
    }
}
