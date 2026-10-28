// Tests/PurahCoreTests/AppProfileSwitchTests.swift
import Testing
import Foundation
@testable import PurahCore

/// The frontmost app chooses *which profile is in force*. These tests pin the
/// whitelist resolution, the default-profile fallback, and the two properties
/// that make automatic switching safe: an edit made under a profile belongs to
/// that profile, and a switch never lands while the user is reading a drawer.
@Suite("App Profile Switching")
@MainActor
struct AppProfileSwitchTests {

    private func makeStore() -> PurahWorkspaceStore {
        let defaults = UserDefaults(suiteName: "purah.appprofile.tests.\(UUID().uuidString)")!
        return PurahWorkspaceStore(userDefaults: defaults)
    }

    /// Two profiles that genuinely differ, so "which one is in force" is
    /// observable through the pods and not only through an id.
    ///
    /// Both are captured with nothing active: while a profile is in force, an
    /// edit is written back into it, which would make the second capture a copy
    /// of the first one.
    private func makeTwoProfiles(
        _ store: PurahWorkspaceStore
    ) -> (editor: ContextProfile, fallback: ContextProfile, movedPodId: String) {
        guard let pod = store.pods.first(where: { $0.isEnabled }) else {
            Issue.record("expected at least one enabled pod")
            return (
                ContextProfile(name: "Editor", pods: []),
                ContextProfile(name: "Default", pods: []),
                ""
            )
        }
        let editor = store.captureProfile(named: "Editor")
        store.setPodPage(id: pod.id, pageIndex: 1)
        let fallback = store.captureProfile(named: "Default")
        var profileStore = ContextProfileStore()
        profileStore.profiles = [editor, fallback]
        store.contextProfiles = profileStore
        return (editor, fallback, pod.id)
    }

    @Test("An app on a whitelist gets its profile")
    func testWhitelistedAppSwitchesProfile() {
        let store = makeStore()
        let (editor, fallback, movedPodId) = makeTwoProfiles(store)
        store.isAppProfileSwitchingEnabled = true
        store.setDefaultProfile(id: fallback.id)
        store.assignApp(bundleId: "com.test.editor", to: editor.id)
        // Start from the fallback so the switch has somewhere to go.
        store.applyProfile(id: fallback.id)
        #expect(store.contextProfiles.activeProfileId == fallback.id)

        let service = AppProfileSwitchService(debounceMilliseconds: 0)
        service.bindStore(store)
        service.evaluate(bundleId: "com.test.editor", name: "Editor")

        #expect(store.contextProfiles.activeProfileId == editor.id)
        #expect(
            store.pods.first { $0.id == movedPodId }?.pageIndex == 0,
            "the whitelisted app's profile must be the layout in force"
        )
    }

    @Test("An app that is not listed gets the default profile")
    func testUnlistedAppGetsDefaultProfile() {
        let store = makeStore()
        let (editor, fallback, movedPodId) = makeTwoProfiles(store)
        store.isAppProfileSwitchingEnabled = true
        store.setDefaultProfile(id: fallback.id)
        store.assignApp(bundleId: "com.test.editor", to: editor.id)
        store.applyProfile(id: editor.id)

        let service = AppProfileSwitchService(debounceMilliseconds: 0)
        service.bindStore(store)
        service.evaluate(bundleId: "com.test.mail", name: "Mail")

        #expect(store.contextProfiles.activeProfileId == fallback.id)
        #expect(store.pods.first { $0.id == movedPodId }?.pageIndex == 1)
    }

    /// Guessing a fallback would rearrange the rails for every app the person
    /// never thought about. With none chosen, the feature does nothing.
    @Test("With no default profile an unlisted app changes nothing")
    func testNoDefaultLeavesLayoutAlone() {
        let store = makeStore()
        let (editor, _, _) = makeTwoProfiles(store)
        store.isAppProfileSwitchingEnabled = true
        store.assignApp(bundleId: "com.test.editor", to: editor.id)
        store.applyProfile(id: editor.id)

        let service = AppProfileSwitchService(debounceMilliseconds: 0)
        service.bindStore(store)
        service.evaluate(bundleId: "com.test.mail", name: "Mail")

        #expect(store.contextProfiles.activeProfileId == editor.id)
    }

    @Test("A disabled feature does not switch profiles")
    func testDisabledFeatureDoesNotSwitch() {
        let store = makeStore()
        let (editor, fallback, _) = makeTwoProfiles(store)
        store.isAppProfileSwitchingEnabled = false
        store.setDefaultProfile(id: fallback.id)
        store.assignApp(bundleId: "com.test.editor", to: editor.id)
        store.applyProfile(id: fallback.id)

        let service = AppProfileSwitchService(debounceMilliseconds: 0)
        service.bindStore(store)
        service.evaluate(bundleId: "com.test.editor", name: "Editor")

        #expect(store.contextProfiles.activeProfileId == fallback.id)
    }

    /// The settings window makes Purah frontmost. Activating it must not hand
    /// the rail to whatever "Purah" resolves to while the person is editing.
    @Test("Purah activating itself is ignored")
    func testSelfActivationIsIgnored() {
        let store = makeStore()
        let (editor, fallback, _) = makeTwoProfiles(store)
        store.isAppProfileSwitchingEnabled = true
        store.setDefaultProfile(id: fallback.id)
        store.assignApp(bundleId: Bundle.main.bundleIdentifier ?? "self", to: editor.id)
        store.applyProfile(id: fallback.id)

        let service = AppProfileSwitchService(debounceMilliseconds: 0)
        service.bindStore(store)
        service.evaluate(bundleId: Bundle.main.bundleIdentifier, name: "Purah")

        #expect(store.contextProfiles.activeProfileId == fallback.id)
    }

    @Test("An app belongs to at most one profile")
    func testAppMovesBetweenWhitelists() {
        let store = makeStore()
        let (editor, fallback, _) = makeTwoProfiles(store)

        store.assignApp(bundleId: "com.test.editor", to: editor.id)
        store.assignApp(bundleId: "com.test.editor", to: fallback.id)

        let profiles = store.contextProfiles
        #expect(profiles.profileId(forApp: "com.test.editor") == fallback.id)
        #expect(profiles.appBundleIds(for: editor.id).isEmpty)
        #expect(profiles.appBundleIds(for: fallback.id) == ["com.test.editor"])
    }

    // MARK: - Write-back

    /// Automatic switching replaces the whole layout, so an edit has to be
    /// carried into the profile before the switch that displaces it.
    @Test("Edits made under a profile are carried into it when it is left")
    func testEditsAreWrittenBackToActiveProfile() {
        let store = makeStore()
        let (editor, fallback, movedPodId) = makeTwoProfiles(store)
        store.isAppProfileSwitchingEnabled = true
        store.setDefaultProfile(id: fallback.id)
        store.assignApp(bundleId: "com.test.editor", to: editor.id)
        store.applyProfile(id: editor.id)

        store.setPodPage(id: movedPodId, pageIndex: 1)

        let service = AppProfileSwitchService(debounceMilliseconds: 0)
        service.bindStore(store)
        service.evaluate(bundleId: "com.test.mail", name: "Mail")
        #expect(store.contextProfiles.activeProfileId == fallback.id)

        let saved = store.contextProfiles.profiles.first { $0.id == editor.id }
        #expect(saved?.pods.first { $0.id == movedPodId }?.pageIndex == 1)
    }

    /// Re-applying the active profile is the user asking for its saved
    /// arrangement back. Absorbing the drift first would make Apply a no-op and
    /// the saved layout unrecoverable.
    @Test("Applying the active profile still restores its saved layout")
    func testReapplyingRestoresSavedLayout() {
        let store = makeStore()
        let (editor, _, movedPodId) = makeTwoProfiles(store)
        store.applyProfile(id: editor.id)

        store.setPodPage(id: movedPodId, pageIndex: 1)
        store.applyProfile(id: editor.id)

        #expect(store.pods.first { $0.id == movedPodId }?.pageIndex == 0)
    }

    /// The edit must survive a round trip through another profile — that is the
    /// path automatic switching takes every time the person changes apps.
    @Test("An edit survives switching away and back")
    func testEditSurvivesSwitchRoundTrip() {
        let store = makeStore()
        let (editor, fallback, movedPodId) = makeTwoProfiles(store)
        store.isAppProfileSwitchingEnabled = true
        store.setDefaultProfile(id: fallback.id)
        store.assignApp(bundleId: "com.test.editor", to: editor.id)
        store.applyProfile(id: editor.id)

        store.setPodPage(id: movedPodId, pageIndex: 1)

        let service = AppProfileSwitchService(debounceMilliseconds: 0)
        service.bindStore(store)
        service.evaluate(bundleId: "com.test.mail", name: "Mail")
        #expect(store.contextProfiles.activeProfileId == fallback.id)

        service.evaluate(bundleId: "com.test.editor", name: "Editor")
        #expect(store.contextProfiles.activeProfileId == editor.id)
        #expect(
            store.pods.first { $0.id == movedPodId }?.pageIndex == 1,
            "the edit made in the editor profile must come back with it"
        )
    }

    // MARK: - Deferral

    /// Replacing the layout under an open drawer makes the drawer vanish
    /// mid-read, so the switch waits for the drawer to close.
    @Test("A switch waits for an open drawer to close")
    func testSwitchDefersWhileDrawerOpen() {
        let store = makeStore()
        let (editor, fallback, _) = makeTwoProfiles(store)
        store.isAppProfileSwitchingEnabled = true
        store.setDefaultProfile(id: fallback.id)
        store.assignApp(bundleId: "com.test.editor", to: editor.id)
        store.applyProfile(id: fallback.id)
        store.activeDrawerPodId = "music"

        let service = AppProfileSwitchService(debounceMilliseconds: 0)
        service.bindStore(store)
        service.evaluate(bundleId: "com.test.editor", name: "Editor")

        #expect(store.contextProfiles.activeProfileId == fallback.id)
        #expect(store.pendingProfileId == editor.id)

        store.dismissActiveDrawer()

        #expect(store.contextProfiles.activeProfileId == editor.id)
        #expect(store.pendingProfileId == nil)
    }

    @Test("The latest app wins while a switch is held")
    func testHeldSwitchIsReplacedByTheNewest() {
        let store = makeStore()
        let (editor, fallback, _) = makeTwoProfiles(store)
        store.isAppProfileSwitchingEnabled = true
        store.setDefaultProfile(id: fallback.id)
        store.assignApp(bundleId: "com.test.editor", to: editor.id)
        store.applyProfile(id: fallback.id)
        store.activeDrawerPodId = "music"

        let service = AppProfileSwitchService(debounceMilliseconds: 0)
        service.bindStore(store)
        service.evaluate(bundleId: "com.test.editor", name: "Editor")
        #expect(store.pendingProfileId == editor.id)

        // Back to an app that resolves to the profile already in force: the
        // held switch is stale and must be dropped, not applied later.
        service.evaluate(bundleId: "com.test.mail", name: "Mail")
        store.dismissActiveDrawer()

        #expect(store.contextProfiles.activeProfileId == fallback.id)
        #expect(store.pendingProfileId == nil)
    }

    // MARK: - Store plumbing

    @Test("Deleting a profile clears the default and its whitelist")
    func testDeletingProfileClearsReferences() {
        let store = makeStore()
        let (editor, fallback, _) = makeTwoProfiles(store)
        store.setDefaultProfile(id: fallback.id)
        store.assignApp(bundleId: "com.test.editor", to: editor.id)

        store.deleteProfile(id: editor.id)

        #expect(store.contextProfiles.profileId(forApp: "com.test.editor") == nil)
        store.deleteProfile(id: fallback.id)
        #expect(store.contextProfiles.defaultProfileId == nil)
        #expect(store.contextProfiles.defaultProfile == nil)
    }

    @Test("Only profiles with a whitelist entry are listed")
    func testProfilesWithAppTriggers() {
        let store = makeStore()
        let (editor, fallback, _) = makeTwoProfiles(store)
        store.assignApp(bundleId: "com.test.editor", to: editor.id)

        let listed = store.contextProfiles.profilesWithAppTriggers.map(\.id)
        #expect(listed == [editor.id])
        #expect(!listed.contains(fallback.id))
    }

    @Test("App triggers and the default survive JSON")
    func testStoreRoundTrip() throws {
        let store = makeStore()
        let (editor, fallback, _) = makeTwoProfiles(store)
        store.setDefaultProfile(id: fallback.id)
        store.assignApp(bundleId: "com.test.editor", to: editor.id)

        let data = try JSONEncoder().encode(store.contextProfiles)
        let restored = try JSONDecoder().decode(ContextProfileStore.self, from: data)

        #expect(restored == store.contextProfiles)
        #expect(restored.profileId(forApp: "com.test.editor") == editor.id)
        #expect(restored.defaultProfileId == fallback.id)
    }

    /// Profiles saved by a build without whitelists must still load, with no
    /// default and no app triggers rather than failing to decode.
    @Test("A profile blob from before whitelists still decodes")
    func testLegacyBlobDecodes() throws {
        let json = """
        {"profiles":[],"activeProfileId":null,"triggers":{}}
        """
        let decoded = try JSONDecoder().decode(ContextProfileStore.self, from: Data(json.utf8))
        #expect(decoded.defaultProfileId == nil)
        #expect(decoded.triggers.isEmpty)
    }

    @Test("An app trigger encodes as a readable key")
    func testAppTriggerCodingKey() {
        let trigger = ProfileTrigger.app(bundleId: "com.test.editor")
        #expect(trigger.codingKey.stringValue == "app:com.test.editor")
        #expect(ProfileTrigger(codingKey: trigger.codingKey) == trigger)
        #expect(ProfileTrigger(codingKey: ProfileTrigger.StringKey("app:")) == nil)
    }
}
