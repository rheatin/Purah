// Tests/PurahCoreTests/AppFocusRuleTests.swift
import Testing
import Foundation
@testable import PurahCore

/// Focus rules may only move a pod between rail pages. These tests pin that
/// boundary, and pin that applying and then clearing a rule is a round trip —
/// a rule that rearranges the rail and does not put it back would be worse than
/// no feature at all.
@Suite("App Focus Rules")
@MainActor
struct AppFocusRuleTests {

    private func makeStore() -> PurahWorkspaceStore {
        let defaults = UserDefaults(suiteName: "purah.focus.tests.\(UUID().uuidString)")!
        return PurahWorkspaceStore(userDefaults: defaults)
    }

    @Test("A rule moves a surfaced pod to page 0")
    func testSurfacesToFirstPage() {
        let store = makeStore()
        guard let pod = store.pods.first(where: { $0.isEnabled }) else {
            Issue.record("expected at least one enabled pod")
            return
        }
        store.setPodPage(id: pod.id, pageIndex: 2)

        store.applyFocusRule(AppFocusRule(bundleId: "com.test.app", surfacedPodIds: [pod.id]))

        let updated = store.pods.first { $0.id == pod.id }
        #expect(updated?.pageIndex == 0)
    }

    @Test("A rule pushes a hidden pod off the first page")
    func testHidesFromFirstPage() {
        let store = makeStore()
        guard let pod = store.pods.first(where: { $0.isEnabled }) else {
            Issue.record("expected at least one enabled pod")
            return
        }
        store.setPodPage(id: pod.id, pageIndex: 0)

        store.applyFocusRule(AppFocusRule(bundleId: "com.test.app", hiddenPodIds: [pod.id]))

        let updated = store.pods.first { $0.id == pod.id }
        #expect(updated?.pageIndex == 1)
    }

    @Test("Clearing a rule restores the original page assignments")
    func testClearRestoresOriginalPages() {
        let store = makeStore()
        guard let pod = store.pods.first(where: { $0.isEnabled }) else {
            Issue.record("expected at least one enabled pod")
            return
        }
        // Move it away first, then record. `setPodPage` re-solves the rail, so
        // the baseline has to be taken after it, not before.
        store.setPodPage(id: pod.id, pageIndex: 1)
        let originals = Dictionary(uniqueKeysWithValues: store.pods.map { ($0.id, $0.pageIndex) })

        store.applyFocusRule(AppFocusRule(bundleId: "com.test.app", surfacedPodIds: [pod.id]))
        #expect(store.pods.first { $0.id == pod.id }?.pageIndex == 0)

        store.clearFocusRule()

        for (id, originalPage) in originals {
            #expect(
                store.pods.first { $0.id == id }?.pageIndex == originalPage,
                "pod \(id) did not return to page \(originalPage)"
            )
        }
    }

    /// A rule may only change which page a pod is on. If it also touched the
    /// vertical range, a hand-sculpted layout would deform every time the user
    /// switched apps.
    @Test("A rule does not change a pod's vertical range")
    func testRuleDoesNotTouchRanges() {
        let store = makeStore()
        let before = Dictionary(uniqueKeysWithValues: store.pods.map { ($0.id, $0.range) })
        let ids = Array(before.keys.prefix(2))
        guard !ids.isEmpty else {
            Issue.record("expected pods")
            return
        }

        store.applyFocusRule(AppFocusRule(bundleId: "com.test.app", surfacedPodIds: ids))

        for (id, range) in before {
            let current = store.pods.first { $0.id == id }?.range
            #expect(current?.start == range.start, "pod \(id) start moved")
            #expect(current?.length == range.length, "pod \(id) length changed")
        }
    }

    /// Switching Xcode → Terminal applies the second rule on top of the first.
    /// The snapshot must still be the one taken before *any* rule, or clearing
    /// would restore the intermediate state instead of the user's layout.
    @Test("The snapshot survives a chain of rules")
    func testSnapshotTakenOnceAcrossRules() {
        let store = makeStore()
        guard store.pods.count >= 2 else {
            Issue.record("expected at least two pods")
            return
        }
        let first = store.pods[0]
        let second = store.pods[1]

        // Both start on page 0 so the originals are unambiguous.
        store.setPodPage(id: first.id, pageIndex: 0)
        store.setPodPage(id: second.id, pageIndex: 0)
        // `setPodPage` re-solves the rail, so re-read the baseline after it.
        #expect(store.pods.first { $0.id == first.id }?.pageIndex == 0)
        #expect(store.pods.first { $0.id == second.id }?.pageIndex == 0)

        store.applyFocusRule(AppFocusRule(bundleId: "com.a", hiddenPodIds: [first.id]))
        store.applyFocusRule(AppFocusRule(bundleId: "com.b", hiddenPodIds: [second.id]))
        #expect(store.pods.first { $0.id == first.id }?.pageIndex == 1)
        #expect(store.pods.first { $0.id == second.id }?.pageIndex == 1)

        store.clearFocusRule()

        #expect(store.pods.first { $0.id == first.id }?.pageIndex == 0)
        #expect(store.pods.first { $0.id == second.id }?.pageIndex == 0)
    }

    @Test("An inert rule changes nothing")
    func testInertRuleIsANoOp() {
        let store = makeStore()
        let before = store.pods.map(\.pageIndex)

        store.applyFocusRule(AppFocusRule(bundleId: "com.test.app"))

        #expect(store.pods.map(\.pageIndex) == before)
        #expect(store.focusRuleSnapshot == nil, "an inert rule should not arm a snapshot")
    }

    @Test("Unknown pod ids are ignored rather than trapping")
    func testUnknownPodIdsIgnored() {
        let store = makeStore()
        let before = store.pods.map(\.pageIndex)

        store.applyFocusRule(AppFocusRule(
            bundleId: "com.test.app",
            surfacedPodIds: ["does-not-exist"],
            hiddenPodIds: ["also-missing"]
        ))

        #expect(store.pods.map(\.pageIndex) == before)
    }

    @Test("Disabling the feature clears any applied rule")
    func testDisablingClearsRule() {
        let store = makeStore()
        guard let pod = store.pods.first(where: { $0.isEnabled }) else {
            Issue.record("expected an enabled pod")
            return
        }
        store.setPodPage(id: pod.id, pageIndex: 0)

        var settings = AppFocusSettings(
            isEnabled: true,
            rules: ["com.test.app": AppFocusRule(bundleId: "com.test.app", hiddenPodIds: [pod.id])]
        )
        store.appFocusSettings = settings

        store.applyFocusRule(settings.rules["com.test.app"]!)
        #expect(store.pods.first { $0.id == pod.id }?.pageIndex == 1)

        settings.isEnabled = false
        store.appFocusSettings = settings

        #expect(store.pods.first { $0.id == pod.id }?.pageIndex == 0)
        #expect(store.focusRuleSnapshot == nil)
    }

    // MARK: - Rule model

    @Test("A rule with no pod lists is inert")
    func testInertDetection() {
        #expect(AppFocusRule(bundleId: "a").isInert)
        #expect(!AppFocusRule(bundleId: "a", surfacedPodIds: ["x"]).isInert)
        #expect(!AppFocusRule(bundleId: "a", hiddenPodIds: ["x"]).isInert)
    }

    @Test("A rule with no display name falls back to its bundle id")
    func testDisplayNameFallback() {
        #expect(AppFocusRule(bundleId: "com.test.app").displayName == "com.test.app")
        #expect(AppFocusRule(bundleId: "com.test.app", displayName: "Test").displayName == "Test")
    }

    @Test("Rules round-trip through JSON")
    func testSettingsRoundTrip() throws {
        let original = AppFocusSettings(
            isEnabled: true,
            rules: [
                "com.apple.dt.Xcode": AppFocusRule(
                    bundleId: "com.apple.dt.Xcode",
                    displayName: "Xcode",
                    surfacedPodIds: ["terminal", "vitals"],
                    hiddenPodIds: ["music"]
                )
            ]
        )
        let restored = try JSONDecoder().decode(
            AppFocusSettings.self,
            from: try JSONEncoder().encode(original)
        )
        #expect(restored == original)
    }

    @Test("A blob with no rules decodes as disabled with an empty set")
    func testEmptyBlobDecodes() throws {
        let settings = try JSONDecoder().decode(AppFocusSettings.self, from: Data("{}".utf8))
        #expect(!settings.isEnabled)
        #expect(settings.rules.isEmpty)
    }

    // MARK: - The service end of the feature

    /// The store tests above prove `applyFocusRule` works when it is called.
    /// This proves something calls it: an app switch, arriving through
    /// `evaluate`, actually moves the rail.
    @Test("Evaluating a frontmost app applies its rule")
    func testEvaluateAppliesRule() {
        let store = makeStore()
        guard let pod = store.pods.first(where: { $0.isEnabled }) else {
            Issue.record("expected at least one enabled pod")
            return
        }
        store.appFocusSettings = AppFocusSettings(
            isEnabled: true,
            rules: ["com.test.editor": AppFocusRule(bundleId: "com.test.editor", hiddenPodIds: [pod.id])]
        )

        let service = AppFocusAwarenessService(debounceMilliseconds: 0)
        service.bindStore(store)
        service.evaluate(bundleId: "com.test.editor", name: "Editor")

        #expect(
            store.pods.first { $0.id == pod.id }?.pageIndex == 1,
            "switching to an app with a rule must move its pods"
        )
        #expect(service.activeBundleId == "com.test.editor")
        #expect(service.lastExternalBundleId == "com.test.editor")
    }

    @Test("Leaving a ruled app restores the original pages")
    func testEvaluateRevertsOnLeave() {
        let store = makeStore()
        guard let pod = store.pods.first(where: { $0.isEnabled }) else {
            Issue.record("expected at least one enabled pod")
            return
        }
        let originalPage = pod.pageIndex
        store.appFocusSettings = AppFocusSettings(
            isEnabled: true,
            rules: ["com.test.editor": AppFocusRule(bundleId: "com.test.editor", hiddenPodIds: [pod.id])]
        )

        let service = AppFocusAwarenessService(debounceMilliseconds: 0)
        service.bindStore(store)
        service.evaluate(bundleId: "com.test.editor", name: "Editor")
        service.evaluate(bundleId: "com.test.other", name: "Other")

        #expect(store.pods.first { $0.id == pod.id }?.pageIndex == originalPage)
    }

    /// The settings window makes Purah frontmost. Evaluating it must not undo
    /// the user's arrangement while they are configuring the feature.
    @Test("Purah activating itself is ignored")
    func testSelfActivationIsIgnored() {
        let store = makeStore()
        guard let pod = store.pods.first(where: { $0.isEnabled }) else {
            Issue.record("expected at least one enabled pod")
            return
        }
        store.appFocusSettings = AppFocusSettings(
            isEnabled: true,
            rules: [Bundle.main.bundleIdentifier ?? "self": AppFocusRule(
                bundleId: Bundle.main.bundleIdentifier ?? "self",
                hiddenPodIds: [pod.id]
            )]
        )

        let service = AppFocusAwarenessService(debounceMilliseconds: 0)
        service.bindStore(store)
        service.evaluate(bundleId: Bundle.main.bundleIdentifier, name: "Purah")

        #expect(store.pods.first { $0.id == pod.id }?.pageIndex == 0)
    }

    @Test("A rule is inert while the feature is switched off")
    func testDisabledFeatureDoesNotMovePods() {
        let store = makeStore()
        guard let pod = store.pods.first(where: { $0.isEnabled }) else {
            Issue.record("expected at least one enabled pod")
            return
        }
        store.appFocusSettings = AppFocusSettings(
            isEnabled: false,
            rules: ["com.test.editor": AppFocusRule(bundleId: "com.test.editor", hiddenPodIds: [pod.id])]
        )

        let service = AppFocusAwarenessService(debounceMilliseconds: 0)
        service.bindStore(store)
        service.evaluate(bundleId: "com.test.editor", name: "Editor")

        #expect(store.pods.first { $0.id == pod.id }?.pageIndex == 0)
    }

    /// Quitting inside a ruled app skips the undo. The temporary pages must not
    /// survive the relaunch, or the user is left with a layout no rule explains.
    @Test("Pages left behind by an interrupted rule are restored on launch")
    func testInterruptedRuleIsRestoredOnLaunch() {
        let suiteName = "purah.focus.interrupt.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = PurahWorkspaceStore(userDefaults: defaults)
        guard let pod = store.pods.first(where: { $0.isEnabled }) else {
            Issue.record("expected at least one enabled pod")
            return
        }
        let originalPage = pod.pageIndex
        store.appFocusSettings = AppFocusSettings(
            isEnabled: true,
            rules: ["com.test.editor": AppFocusRule(bundleId: "com.test.editor", hiddenPodIds: [pod.id])]
        )

        let service = AppFocusAwarenessService(debounceMilliseconds: 0)
        service.bindStore(store)
        service.evaluate(bundleId: "com.test.editor", name: "Editor")
        #expect(store.pods.first { $0.id == pod.id }?.pageIndex == 1)
        // Simulate the quit: persist exactly as the app would, without undoing.
        store.savePersistentState()

        let relaunched = PurahWorkspaceStore(userDefaults: defaults)
        relaunched.loadPersistentState()

        #expect(
            relaunched.pods.first { $0.id == pod.id }?.pageIndex == originalPage,
            "the temporary page must not survive a relaunch"
        )
    }
}
