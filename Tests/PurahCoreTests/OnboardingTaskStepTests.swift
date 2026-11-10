import Testing
import Foundation
@testable import PurahCore
@testable import PurahUI

/// The guide is five task steps, each ending in a visible result. These tests
/// name the action each mission waits for.
@Suite("Onboarding Task Steps")
@MainActor
struct OnboardingTaskStepTests {
    private func store() -> (PurahWorkspaceStore, UserDefaults, String) {
        let suite = "onboarding_task_\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (PurahWorkspaceStore(userDefaults: defaults), defaults, suite)
    }

    @Test("Step order is exactly the five tasks, and Next finishes from the last")
    func stepOrder() {
        #expect(OnboardingGuideStep.allCases == [
            .firstPod, .edgeUse, .stack, .decomposeDemo, .handAndPermissions
        ])
        #expect(OnboardingGuideStep.allCases.map(\.rawValue) == [0, 1, 2, 3, 4])

        let (store, defaults, suite) = store()
        defer { defaults.removePersistentDomain(forName: suite) }
        store.startInteractiveOnboarding(clearAllPods: true)
        store.nextOnboardingStep()
        #expect(store.onboardingStep == .edgeUse)
        store.nextOnboardingStep()
        #expect(store.onboardingStep == .stack)
        store.nextOnboardingStep()
        #expect(store.onboardingStep == .decomposeDemo)
        store.nextOnboardingStep()
        #expect(store.onboardingStep == .handAndPermissions)
        store.nextOnboardingStep()
        #expect(store.isOnboardingGuideActive == false)
        #expect(store.hasCompletedOnboarding == true)
    }

    @Test("firstPod completes on one mount")
    func firstPodCompletesOnOneMount() {
        let (store, defaults, suite) = store()
        defer { defaults.removePersistentDomain(forName: suite) }
        store.startInteractiveOnboarding(clearAllPods: true)
        #expect(store.isCurrentOnboardingMissionCompleted == false)
        store.mountPod(id: "calendar", to: .right, announce: false)
        #expect(store.isCurrentOnboardingMissionCompleted == true)
    }

    @Test("edgeUse completes on one edge open, never on the programmatic open")
    func edgeUseCompletesOnEdgeOpen() {
        let (store, defaults, suite) = store()
        defer { defaults.removePersistentDomain(forName: suite) }
        store.startInteractiveOnboarding(clearAllPods: true)
        store.mountPod(id: "vitals", to: .left, announce: false)
        store.selectOnboardingStep(.edgeUse)
        #expect(store.onboardingDidTriggerEdgeDrawer == false)

        // The step-0 payoff opens the same drawer without using the edge.
        store.activateDrawer(podId: "vitals")
        #expect(store.onboardingDidTriggerEdgeDrawer == false)
        #expect(store.isCurrentOnboardingMissionCompleted == false)

        store.activateDrawer(podId: "vitals", openedByEdge: true)
        #expect(store.isCurrentOnboardingMissionCompleted == true)
    }

    @Test("stack completes on one stack")
    func stackCompletesOnOneStack() {
        let (store, defaults, suite) = store()
        defer { defaults.removePersistentDomain(forName: suite) }
        store.startInteractiveOnboarding(clearAllPods: true)
        store.mountPod(id: "vitals", to: .left, announce: false)
        store.mountPod(id: "shelf", to: .left, announce: false)
        store.selectOnboardingStep(.stack)
        #expect(store.isCurrentOnboardingMissionCompleted == false)

        let left = store.pods.filter { $0.edge == .left && $0.isEnabled }
            .sorted { $0.range.start < $1.range.start }
        store.addPodToMajorGroup(podId: left[1].id, targetPodId: left[0].id)
        #expect(store.isCurrentOnboardingMissionCompleted == true)
    }

    @Test("decomposeDemo completes on one toggle")
    func decomposeCompletesOnOneToggle() {
        let (store, defaults, suite) = store()
        defer { defaults.removePersistentDomain(forName: suite) }
        store.startInteractiveOnboarding(clearAllPods: true)
        store.mountPod(id: "vitals", to: .left, announce: false)
        store.selectOnboardingStep(.decomposeDemo)
        #expect(store.isCurrentOnboardingMissionCompleted == false)
        store.togglePodDecomposedInSculptor(podId: "vitals")
        #expect(store.isCurrentOnboardingMissionCompleted == true)
    }

    @Test("handAndPermissions completes immediately")
    func handAndPermissionsCompletesImmediately() {
        let (store, defaults, suite) = store()
        defer { defaults.removePersistentDomain(forName: suite) }
        store.startInteractiveOnboarding(clearAllPods: true)
        store.selectOnboardingStep(.handAndPermissions)
        #expect(store.isCurrentOnboardingMissionCompleted == true)
    }

    @Test("The step-0 drawer opens once for a mount the person made")
    func firstPodDrawerOpensOnceForAUserMount() async {
        let (store, defaults, suite) = store()
        defer { defaults.removePersistentDomain(forName: suite) }
        store.startInteractiveOnboarding(clearAllPods: true)

        store.mountPod(id: "calendar", to: .right)
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        #expect(store.activeDrawerPodId == "calendar")

        store.dismissActiveDrawer()
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        #expect(store.activeDrawerPodId == nil)
    }

    @Test("A rehearsal mount never opens a drawer")
    func rehearsalMountNeverOpensADrawer() async {
        let (store, defaults, suite) = store()
        defer { defaults.removePersistentDomain(forName: suite) }
        store.startInteractiveOnboarding(clearAllPods: true)

        store.rehearseMountSamplePods()
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        #expect(store.activeDrawerPodId == nil)
    }

    @Test("The decompose demo keeps one span across the toggle, and it fits the chips")
    func decomposeDemoKeepsOneSpan() {
        let (store, defaults, suite) = store()
        defer { defaults.removePersistentDomain(forName: suite) }
        store.startInteractiveOnboarding(clearAllPods: true)
        store.mountPod(id: "vitals", to: .left, announce: false)
        store.selectOnboardingStep(.decomposeDemo)

        guard let before = store.pods.first(where: { $0.id == "vitals" }) else {
            Issue.record("Vitals should be the demo pod")
            return
        }
        #expect(store.isPodDecomposed("vitals") == false)

        store.togglePodDecomposedInSculptor(podId: "vitals")
        guard let after = store.pods.first(where: { $0.id == "vitals" }) else {
            Issue.record("Vitals should still be mounted")
            return
        }
        #expect(abs(after.range.length - before.range.length) < 0.001)

        let screenH = Double(store.availableScreenHeight(for: after.edge))
        let spanPoints = after.range.length * screenH
        #expect(spanPoints >= Double(store.minimumDrawerHeight(for: "vitals")) - 0.5)
    }

    @Test("Every completed mission hands the focus frame to Next Step")
    func completedMissionsHandOffToNextStep() {
        struct Mission {
            let name: String
            let prepare: (PurahWorkspaceStore) -> Void
        }

        let missions: [Mission] = [
            Mission(name: "firstPod") { store in
                store.mountPod(id: "calendar", to: .right, announce: false)
            },
            Mission(name: "edgeUse") { store in
                store.mountPod(id: "vitals", to: .left, announce: false)
                store.selectOnboardingStep(.edgeUse)
                store.activateDrawer(podId: "vitals", openedByEdge: true)
            },
            Mission(name: "stack") { store in
                store.mountPod(id: "vitals", to: .left, announce: false)
                store.mountPod(id: "shelf", to: .left, announce: false)
                store.selectOnboardingStep(.stack)
                let left = store.pods
                    .filter { $0.edge == .left && $0.isEnabled }
                    .sorted { $0.range.start < $1.range.start }
                store.addPodToMajorGroup(podId: left[1].id, targetPodId: left[0].id)
            },
            Mission(name: "decomposeDemo") { store in
                store.mountPod(id: "vitals", to: .left, announce: false)
                store.selectOnboardingStep(.decomposeDemo)
                store.togglePodDecomposedInSculptor(podId: "vitals")
            },
            Mission(name: "handAndPermissions") { store in
                store.selectOnboardingStep(.handAndPermissions)
            },
        ]

        for mission in missions {
            let (store, defaults, suite) = store()
            defer { defaults.removePersistentDomain(forName: suite) }
            store.startInteractiveOnboarding(clearAllPods: true)

            #expect(OnboardingCalloutPolicy.mayPublish(
                owner: "dock-mount-left-calendar",
                missionCompleted: store.isCurrentOnboardingMissionCompleted
            ))
            mission.prepare(store)
            #expect(store.isCurrentOnboardingMissionCompleted, "\(mission.name) should complete")
            #expect(!OnboardingCalloutPolicy.mayPublish(
                owner: "dock-mount-left-calendar",
                missionCompleted: store.isCurrentOnboardingMissionCompleted
            ), "\(mission.name) must release its old target")
            #expect(OnboardingCalloutPolicy.mayPublish(
                owner: "dock-next-step",
                missionCompleted: store.isCurrentOnboardingMissionCompleted
            ), "\(mission.name) must hand the frame to Next Step")
        }
    }
}
