// Tests/PurahCoreTests/ContextProfileTests.swift
import Testing
import Foundation
@testable import PurahCore

/// A profile is only useful if applying it reproduces the arrangement it
/// captured. These tests take a layout, disturb it, restore the profile, and
/// compare — the round trip is the whole contract.
@Suite("Context Profiles")
@MainActor
struct ContextProfileTests {

    private func makeStore() -> PurahWorkspaceStore {
        let defaults = UserDefaults(suiteName: "purah.profiles.tests.\(UUID().uuidString)")!
        return PurahWorkspaceStore(userDefaults: defaults)
    }

    // MARK: - Round trip

    @Test("Applying a profile restores pod placement and geometry")
    func testApplyRestoresLayout() {
        let store = makeStore()
        guard let pod = store.pods.first(where: { $0.isEnabled }) else {
            Issue.record("expected an enabled pod")
            return
        }

        // Capture the arrangement as it stands.
        store.setPodPage(id: pod.id, pageIndex: 1)
        let expected = store.pods.first { $0.id == pod.id }!
        let profile = store.saveProfile(named: "Desk")

        // Disturb it: different page, different height, disabled.
        store.setPodPage(id: pod.id, pageIndex: 0)
        if let idx = store.pods.firstIndex(where: { $0.id == pod.id }) {
            store.pods[idx].range = NormalizedRange(start: 0.5, length: 0.1)
            store.pods[idx].isEnabled = false
        }

        store.applyProfile(id: profile.id)

        let restored = store.pods.first { $0.id == pod.id }!
        #expect(restored.pageIndex == expected.pageIndex)
        #expect(restored.range.start == expected.range.start)
        #expect(restored.range.length == expected.range.length)
        #expect(restored.isEnabled == expected.isEnabled)
        #expect(restored.edge == expected.edge)
        #expect(restored.majorGroupId == expected.majorGroupId)
    }

    @Test("Applying a profile restores colours, pins and drawer width")
    func testApplyRestoresAncillaryState() {
        let store = makeStore()
        guard let pod = store.pods.first(where: { $0.isEnabled }) else {
            Issue.record("expected an enabled pod")
            return
        }

        store.customPodColors[pod.id] = "#FF0000"
        store.pinnedDrawerItemIds = ["clipboard-1", "todo-2"]
        store.drawerWidthMode = .fixed
        store.fixedDrawerWidth = 340
        let profile = store.saveProfile(named: "Desk")

        store.customPodColors[pod.id] = "#00FF00"
        store.pinnedDrawerItemIds = []
        store.drawerWidthMode = .adaptive
        store.fixedDrawerWidth = 260

        store.applyProfile(id: profile.id)

        #expect(store.customPodColors[pod.id] == "#FF0000")
        #expect(store.pinnedDrawerItemIds == ["clipboard-1", "todo-2"])
        #expect(store.drawerWidthMode == .fixed)
        #expect(store.fixedDrawerWidth == 340)
    }

    @Test("Applying a profile marks it active")
    func testApplySetsActiveProfile() {
        let store = makeStore()
        let profile = store.saveProfile(named: "Desk")
        #expect(store.contextProfiles.activeProfileId == profile.id)

        store.applyProfile(id: profile.id)
        #expect(store.contextProfiles.activeProfile?.id == profile.id)
    }

    // MARK: - Apply must stay reachable

    /// The bug this covers: `saveProfile` marks the new profile active, the row
    /// disabled "Apply" while active, and so a freshly saved profile could never
    /// be re-applied after the layout was changed. `layoutMatches` is the only
    /// predicate that may drive a completed-looking state.
    @Test("A freshly saved profile matches the live layout")
    func testFreshProfileMatchesLayout() {
        let store = makeStore()
        let profile = store.saveProfile(named: "Desk")
        #expect(store.layoutMatches(profile: profile))
    }

    @Test("Changing the layout makes the profile no longer match")
    func testLayoutDriftBreaksMatch() {
        let store = makeStore()
        let profile = store.saveProfile(named: "Desk")
        guard let pod = store.pods.first(where: { $0.isEnabled }) else {
            Issue.record("expected an enabled pod")
            return
        }

        store.setPodPage(id: pod.id, pageIndex: 1)

        #expect(
            !store.layoutMatches(profile: profile),
            "the layout moved, so Apply has work to do and must not look complete"
        )
    }

    /// The exact user-facing sequence: save, rearrange, apply, and the original
    /// arrangement must come back.
    @Test("Applying after drift restores the saved arrangement")
    func testApplyAfterDriftRestores() {
        let store = makeStore()
        guard let pod = store.pods.first(where: { $0.isEnabled }) else {
            Issue.record("expected an enabled pod")
            return
        }
        store.setPodPage(id: pod.id, pageIndex: 0)
        let saved = store.pods.first { $0.id == pod.id }!
        let profile = store.saveProfile(named: "Desk")

        // Rearrange, which is what makes the user reach for Apply.
        store.setPodPage(id: pod.id, pageIndex: 1)
        #expect(!store.layoutMatches(profile: profile))

        store.applyProfile(id: profile.id)

        #expect(store.layoutMatches(profile: profile))
        let restored = store.pods.first { $0.id == pod.id }!
        #expect(restored.pageIndex == saved.pageIndex)
        #expect(restored.range.start == saved.range.start)
        #expect(restored.range.length == saved.range.length)
    }

    @Test("Applying a profile twice is idempotent")
    func testApplyTwiceIsStable() {
        let store = makeStore()
        let profile = store.saveProfile(named: "Desk")
        store.applyProfile(id: profile.id)
        let afterFirst = store.pods
        store.applyProfile(id: profile.id)
        #expect(store.pods == afterFirst)
    }

    @Test("A colour change alone counts as drift")
    func testColourDriftBreaksMatch() {
        let store = makeStore()
        guard let pod = store.pods.first(where: { $0.isEnabled }) else {
            Issue.record("expected an enabled pod")
            return
        }
        let profile = store.saveProfile(named: "Desk")
        store.customPodColors[pod.id] = "#123456"
        #expect(!store.layoutMatches(profile: profile))
    }

    @Test("Applying an unknown profile id changes nothing")
    func testUnknownProfileIsANoOp() {
        let store = makeStore()
        let before = store.pods
        store.applyProfile(id: UUID())
        #expect(store.pods == before)
    }

    // MARK: - Naming

    @Test("Duplicate names are disambiguated rather than allowed")
    func testUniqueNames() {
        let store = makeStore()
        let first = store.saveProfile(named: "Desk")
        #expect(first.name == "Desk")

        let second = store.saveProfile(named: "Desk")
        #expect(second.name == "Desk 2")

        let third = store.saveProfile(named: "Desk")
        #expect(third.name == "Desk 3")
    }

    /// Case and accents are not a meaningful distinction to a person, so
    /// "Cafe" and "Café" must not become two profiles.
    @Test("Names that differ only by case or accent are treated as the same")
    func testNameComparisonIgnoresCaseAndAccents() {
        let profile = ContextProfile(name: "Café", pods: [])
        #expect(profile.nameMatches("cafe"))
        #expect(profile.nameMatches("CAFÉ"))
        #expect(!profile.nameMatches("Desk"))
    }

    @Test("Renaming to a name another profile uses is rejected")
    func testRenameRejectsCollision() {
        let store = makeStore()
        let a = store.saveProfile(named: "Desk")
        _ = store.saveProfile(named: "Cafe")

        store.renameProfile(id: a.id, to: "Cafe")
        #expect(store.contextProfiles.profiles.first { $0.id == a.id }?.name == "Desk")

        store.renameProfile(id: a.id, to: "Studio")
        #expect(store.contextProfiles.profiles.first { $0.id == a.id }?.name == "Studio")
    }

    @Test("Renaming to an empty name is rejected")
    func testRenameRejectsEmpty() {
        let store = makeStore()
        let profile = store.saveProfile(named: "Desk")
        store.renameProfile(id: profile.id, to: "   ")
        #expect(store.contextProfiles.profiles.first { $0.id == profile.id }?.name == "Desk")
    }

    // MARK: - Updating and deleting

    @Test("Updating a profile keeps its identity and creation date")
    func testUpdateKeepsIdentity() {
        let store = makeStore()
        let original = store.saveProfile(named: "Desk")

        guard let pod = store.pods.first(where: { $0.isEnabled }) else {
            Issue.record("expected an enabled pod")
            return
        }
        store.setPodPage(id: pod.id, pageIndex: 1)
        let movedPage = store.pods.first { $0.id == pod.id }?.pageIndex

        store.updateProfile(id: original.id)

        let updated = store.contextProfiles.profiles.first { $0.id == original.id }
        #expect(updated != nil, "the profile must not be replaced by a new one")
        #expect(updated?.createdAt == original.createdAt)
        #expect(updated?.name == original.name)
        #expect(updated?.pods.first { $0.id == pod.id }?.pageIndex == movedPage)
    }

    @Test("Deleting a profile drops its triggers and clears the active mark")
    func testDeleteCleansReferences() {
        let store = makeStore()
        let profile = store.saveProfile(named: "Desk")
        store.assignTrigger(.wifi(ssid: "Office"), to: profile.id)

        store.deleteProfile(id: profile.id)

        #expect(store.contextProfiles.profiles.isEmpty)
        #expect(store.contextProfiles.triggers.isEmpty)
        #expect(store.contextProfiles.activeProfileId == nil)
    }

    // MARK: - Triggers

    @Test("A trigger resolves to its profile, and to nothing once deleted")
    func testTriggerResolution() {
        let store = makeStore()
        let profile = store.saveProfile(named: "Office")
        store.assignTrigger(.wifi(ssid: "OfficeNet"), to: profile.id)

        #expect(store.contextProfiles.profileId(for: .wifi(ssid: "OfficeNet")) == profile.id)
        #expect(store.contextProfiles.profileId(for: .wifi(ssid: "Other")) == nil)

        store.deleteProfile(id: profile.id)
        #expect(store.contextProfiles.profileId(for: .wifi(ssid: "OfficeNet")) == nil)
    }

    @Test("Triggers survive a JSON round trip")
    func testTriggerRoundTrip() throws {
        let store = ContextProfileStore(
            profiles: [ContextProfile(name: "Desk", pods: [])],
            triggers: [
                .manual: UUID(),
                .wifi(ssid: "Office Net"): UUID(),
                .externalDisplay(minimumCount: 2): UUID()
            ]
        )
        let decoded = try JSONDecoder().decode(
            ContextProfileStore.self,
            from: try JSONEncoder().encode(store)
        )
        #expect(decoded.triggers == store.triggers)
    }

    // MARK: - Persistence

    @Test("Profiles survive a store round trip")
    func testProfilesPersist() {
        let suiteName = "purah.profiles.persist.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = PurahWorkspaceStore(userDefaults: defaults)
        let profile = store.saveProfile(named: "Desk")
        store.assignTrigger(.wifi(ssid: "Office"), to: profile.id)
        store.savePersistentState()

        let reloaded = PurahWorkspaceStore(userDefaults: defaults)
        reloaded.loadPersistentState()

        #expect(reloaded.contextProfiles.profiles.count == 1)
        #expect(reloaded.contextProfiles.profiles.first?.name == "Desk")
        #expect(reloaded.contextProfiles.profileId(for: .wifi(ssid: "Office")) == profile.id)
    }

    @Test("A malformed profile blob does not stop the store loading")
    func testMalformedBlobIgnored() {
        let suiteName = "purah.profiles.bad.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(Data("not json".utf8), forKey: "purah.contextProfiles")
        let store = PurahWorkspaceStore(userDefaults: defaults)
        store.loadPersistentState()

        #expect(store.contextProfiles.profiles.isEmpty)
    }

    // MARK: - Interaction with held app switches

    /// A switch that arrived while a drawer was open belongs to the app that
    /// asked for it. Applying a profile by hand says "stop waiting, this is the
    /// layout I want" — letting the held switch land afterwards would undo the
    /// user's own choice a moment later.
    @Test("Applying a profile by hand drops a held app switch")
    func testApplyClearsHeldSwitch() {
        let store = makeStore()
        let profile = store.saveProfile(named: "Desk")
        let other = store.saveProfile(named: "Other")
        store.applyProfile(id: profile.id)
        store.activeDrawerPodId = "music"

        store.switchProfile(id: other.id)
        #expect(store.pendingProfileId != nil)

        store.switchProfile(id: profile.id, deferWhileBusy: false)
        #expect(store.pendingProfileId == nil)
        #expect(store.contextProfiles.activeProfileId == profile.id)
    }

    // MARK: - Summary

    @Test("The summary counts enabled pods per rail")
    func testSummary() {
        let left = SlotPod(
            id: "a", nameKey: "a", defaultName: "A", systemIcon: "circle",
            edge: .left, range: NormalizedRange(start: 0.1, length: 0.2),
            ambientStyle: .ghostDot, preferredZone: .goldenAction,
            ergonomicWeight: 30, minLength: 0.1, isEnabled: true,
            drawerWidth: 300, defaultColorHex: "#FFFFFF", pageIndex: 0
        )
        var right = SlotPod(
            id: "b", nameKey: "b", defaultName: "B", systemIcon: "circle",
            edge: MountEdge.right, range: NormalizedRange(start: 0.5, length: 0.2),
            ambientStyle: .ghostDot, preferredZone: .goldenAction,
            ergonomicWeight: 30, minLength: 0.1, isEnabled: false,
            drawerWidth: 300, defaultColorHex: "#FFFFFF", pageIndex: 0
        )

        let profile = ContextProfile(name: "Test", pods: [left, right])
        #expect(profile.summary.contains("L1"))
        #expect(profile.summary.contains("R0"), "disabled pods are not counted")
    }
}
