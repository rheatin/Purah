// Tests/PurahCoreTests/OnboardingPermissionTests.swift
import Testing
import Foundation
@testable import PurahUI
@testable import PurahCore

/// The permission step is the last one before finish, and it lists exactly the
/// permissions an installed plugin asked for — no more, no less.
@Suite("Onboarding Permission Step Tests")
@MainActor
struct OnboardingPermissionTests {

    private func manifest(
        id: String,
        name: String,
        permissions: [PluginPermission]
    ) -> PurahPluginManifest {
        PurahPluginManifest(
            id: id,
            displayName: name,
            systemIcon: "square",
            description: "test",
            defaultEdge: .left,
            preferredZone: .glance,
            defaultColorHex: "#FFFFFF",
            permissions: permissions
        )
    }

    @Test("The permission panel is the last onboarding step")
    func permissionStepIsLast() {
        // The footer swaps "Next" for "Finish" on the last step, and
        // `nextOnboardingStep` falls through to `finishOnboarding` when there is
        // no `rawValue + 1`. A step appended after this one would silently take
        // the finish buttons away from the panel that ends the tour.
        #expect(OnboardingGuideStep.allCases.last == .permissions)
        #expect(OnboardingGuideStep.allCases.count == 7)
        #expect(OnboardingGuideStep.permissions.rawValue == 6)
    }

    @Test("Grouping is driven by plugin declarations, not a hardcoded list")
    func groupingFollowsDeclarations() {
        let groups = PermissionInventory.groups(manifests: [
            manifest(id: "calendar", name: "Calendar", permissions: [.calendar]),
            manifest(id: "todo", name: "Todo", permissions: [.reminders]),
        ])
        #expect(groups.map(\.permission) == [.calendar, .reminders])
        #expect(groups.first?.pluginNames == "Calendar")
    }

    @Test("A permission no plugin declares is not shown")
    func undeclaredPermissionsAreAbsent() {
        let groups = PermissionInventory.groups(manifests: [
            manifest(id: "todo", name: "Todo", permissions: [.reminders]),
        ])
        #expect(!groups.contains { $0.permission == .calendar })
        #expect(!groups.contains { $0.permission == .microphone })
    }

    @Test("A permission two plugins share lists both, once")
    func sharedPermissionIsGroupedOnce() {
        let groups = PermissionInventory.groups(manifests: [
            manifest(id: "clipboard", name: "Clipboard", permissions: [.fileSystem]),
            manifest(id: "shelf", name: "Shelf", permissions: [.fileSystem]),
        ])
        #expect(groups.count == 1)
        #expect(groups.first?.manifests.count == 2)
        #expect(groups.first?.pluginNames == "Clipboard, Shelf")
    }

    @Test("Privacy permissions sort ahead of ambient ones")
    func tccPermissionsComeFirst() {
        let groups = PermissionInventory.groups(manifests: [
            manifest(id: "music", name: "Music", permissions: [.appleMusic]),
            manifest(id: "todo", name: "Todo", permissions: [.reminders]),
        ])
        #expect(groups.first?.permission == .reminders)
        #expect(groups.last?.permission == .appleMusic)
    }
}
