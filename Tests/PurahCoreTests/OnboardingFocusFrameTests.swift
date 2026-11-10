import Testing
import Foundation
@testable import PurahUI
import PurahCore

@MainActor
@Suite("Onboarding Focus Frame Geometry")
struct OnboardingFocusFrameTests {

    private let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let label = CGSize(width: 88, height: 20)

    private func layout(
        target: CGRect,
        visible: CGRect? = nil,
        label: CGSize? = nil,
        preferred: OnboardingCalloutSide? = nil,
        arrow: OnboardingCalloutArrow = .towardTarget
    ) -> OnboardingFocusLayout {
        OnboardingFocusFrameGeometry.layout(
            targetScreenRect: target,
            visibleScreenRect: visible ?? self.visible,
            labelSize: label ?? self.label,
            preferredSide: preferred,
            arrow: arrow
        )
    }

    @Test("The frame is drawn 2pt outside the target")
    func frameOutset() {
        let target = CGRect(x: 300, y: 300, width: 60, height: 20)
        let result = layout(target: target)
        #expect(abs(result.frameRect.minX - (result.targetRect.minX - 2)) < 0.001)
        #expect(abs(result.frameRect.minY - (result.targetRect.minY - 2)) < 0.001)
        #expect(abs(result.frameRect.width - 64) < 0.001)
        #expect(abs(result.frameRect.height - 24) < 0.001)
    }

    @Test("The side with the most room wins at 1x and 2x")
    func sideWithMostRoom() {
        for scale in [1.0, 2.0] as [CGFloat] {
            let size = CGSize(width: visible.width * scale, height: visible.height * scale)
            let rect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
            let labelSize = CGSize(width: label.width * scale, height: label.height * scale)

            let left = layout(
                target: CGRect(x: 8 * scale, y: 400 * scale, width: 60 * scale, height: 20 * scale),
                visible: rect,
                label: labelSize
            )
            #expect(left.side == .trailing)

            let right = layout(
                target: CGRect(x: (1440 - 68) * scale, y: 400 * scale, width: 60 * scale, height: 20 * scale),
                visible: rect,
                label: labelSize
            )
            #expect(right.side == .leading)

            let top = layout(
                target: CGRect(x: 690 * scale, y: (900 - 28) * scale, width: 60 * scale, height: 20 * scale),
                visible: rect,
                label: labelSize
            )
            #expect(top.side == .below)

            let bottom = layout(
                target: CGRect(x: 690 * scale, y: 8 * scale, width: 60 * scale, height: 20 * scale),
                visible: rect,
                label: labelSize
            )
            #expect(bottom.side == .above)
        }
    }

    @Test("A preferred side is honoured when it fits and skipped when it cannot")
    func preferredSide() {
        let centred = CGRect(x: 690, y: 400, width: 60, height: 20)
        for side in OnboardingCalloutSide.allCases {
            let result = layout(target: centred, preferred: side)
            #expect(result.side == side)
        }

        let atLeftEdge = CGRect(x: 4, y: 400, width: 60, height: 20)
        let forced = layout(target: atLeftEdge, preferred: .leading)
        #expect(forced.side != .leading)
    }

    @Test("The label never intersects the target on any side at 1x and 2x")
    func labelNeverOverlapsTarget() {
        for scale in [1.0, 2.0] as [CGFloat] {
            let size = CGSize(width: visible.width * scale, height: visible.height * scale)
            let rect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
            let labelSize = CGSize(width: label.width * scale, height: label.height * scale)
            let target = CGRect(
                x: 690 * scale,
                y: 400 * scale,
                width: 60 * scale,
                height: 20 * scale
            )

            for side in OnboardingCalloutSide.allCases {
                let result = layout(
                    target: target,
                    visible: rect,
                    label: labelSize,
                    preferred: side
                )
                #expect(!result.labelRect.intersects(result.targetRect),
                        "label \(result.labelRect) overlapped target on \(side) at \(scale)x")
                #expect(rect.contains(result.labelRect))
                #expect(rect.contains(result.arrowRect))
            }
        }
    }

    @Test("Corner targets keep the pill and arrow on screen")
    func clampedInsideVisible() {
        let corners = [
            CGRect(x: 2, y: 2, width: 60, height: 20),
            CGRect(x: 1378, y: 2, width: 60, height: 20),
            CGRect(x: 2, y: 878, width: 60, height: 20),
            CGRect(x: 1378, y: 878, width: 60, height: 20),
        ]
        for target in corners {
            let result = layout(target: target)
            #expect(visible.contains(result.labelRect))
            #expect(visible.contains(result.arrowRect))
            #expect(!result.labelRect.intersects(result.targetRect))
        }
    }

    @Test("The callout window bounds contain the frame, pill and arrow")
    func boundsContainAllParts() {
        let target = CGRect(x: 200, y: 300, width: 120, height: 40)
        let result = layout(target: target)
        #expect(result.calloutBounds.contains(result.frameRect))
        #expect(result.calloutBounds.contains(result.labelRect))
        #expect(result.calloutBounds.contains(result.arrowRect))
        #expect(visible.contains(result.calloutBounds))
    }

    @Test("A full-height edge band labels into the screen, never over the band")
    func edgeBandTarget() {
        let band = CGRect(x: 0, y: 0, width: 8, height: 900)
        let result = layout(
            target: band,
            label: CGSize(width: 78, height: 20),
            preferred: .trailing
        )
        #expect(result.side == .trailing)
        #expect(!result.labelRect.intersects(result.targetRect))
        #expect(visible.contains(result.labelRect))
        #expect(result.calloutBounds.contains(result.frameRect))
    }

    @Test("One owner publishes at a time and stale clears cannot erase it")
    func calloutOwnerHandoff() {
        let suite = "focus_owner_\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = PurahWorkspaceStore(userDefaults: defaults)
        defer { defaults.removePersistentDomain(forName: suite) }
        store.startInteractiveOnboarding(clearAllPods: true)

        let first = OnboardingCalloutTarget(
            screenRect: CGRect(x: 10, y: 10, width: 20, height: 20),
            labelKey: "onboarding.callout.clickHere"
        )
        let second = OnboardingCalloutTarget(
            screenRect: CGRect(x: 40, y: 40, width: 20, height: 20),
            labelKey: "onboarding.callout.dragToStack"
        )

        store.publishOnboardingCalloutTarget(first, owner: "dock", step: .firstPod)
        #expect(store.onboardingCalloutTarget == first)

        store.publishOnboardingCalloutTarget(second, owner: "rail", step: .firstPod)
        #expect(store.onboardingCalloutTarget == second)

        // The dock's view disappearing after the handoff must not clear the rail.
        store.publishOnboardingCalloutTarget(nil, owner: "dock", step: .firstPod)
        #expect(store.onboardingCalloutTarget == second)

        store.publishOnboardingCalloutTarget(nil, owner: "rail", step: .firstPod)
        #expect(store.onboardingCalloutTarget == nil)
    }

    @Test("Step changes clear the callout, and the permissions step can publish its own")
    func calloutClearedOutsideItsStep() {
        let suite = "focus_steps_\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = PurahWorkspaceStore(userDefaults: defaults)
        defer { defaults.removePersistentDomain(forName: suite) }
        store.startInteractiveOnboarding(clearAllPods: true)

        let target = OnboardingCalloutTarget(
            screenRect: CGRect(x: 10, y: 10, width: 20, height: 20),
            labelKey: "onboarding.callout.clickHere"
        )
        store.publishOnboardingCalloutTarget(target, owner: "dock", step: .firstPod)
        #expect(store.onboardingCalloutTarget == target)

        store.selectOnboardingStep(.decomposeDemo)
        #expect(store.onboardingCalloutTarget == nil)

        // A view from the step just left can still deliver a late geometry
        // callback; it must not frame a control that is no longer on screen.
        store.publishOnboardingCalloutTarget(target, owner: "dock", step: .firstPod)
        #expect(store.onboardingCalloutTarget == nil)

        store.selectOnboardingStep(.handAndPermissions)
        #expect(store.onboardingCalloutTarget == nil)

        // The permissions step's Next Step frame appears as soon as the step
        // opens, so that step is allowed to publish like any other.
        store.publishOnboardingCalloutTarget(target, owner: "dock-next-step", step: .handAndPermissions)
        #expect(store.onboardingCalloutTarget == target)
    }
}
