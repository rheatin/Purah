// Sources/PurahUI/Common/PurahMotionPolicy.swift
import SwiftUI

/// Single source of truth for "may this view animate continuously?".
///
/// Ambient Purah views lean on `repeatForever` animations and
/// `TimelineView(.animation)` clocks. Both keep the render loop awake forever,
/// so every one of them has to honour `accessibilityReduceMotion`. Guarding
/// each site ad hoc meant a handful were missed; routing them through this
/// policy keeps the decision in one place.
public enum PurahMotionPolicy {
    /// Whether a decorative, always-on animation may run.
    public static func allowsAmbientAnimation(reduceMotion: Bool) -> Bool {
        !reduceMotion
    }

    /// Whether a one-shot (non-repeating) transition should keep its spring.
    /// Reduce Motion collapses these to a cross-fade rather than removing them.
    public static func animation(
        _ animation: Animation,
        reduceMotion: Bool
    ) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.16) : animation
    }

    /// `TimelineView` schedule for a continuously animating view. When motion
    /// is reduced the clock is paused, so the view renders one static frame.
    public static func timelineSchedule(
        reduceMotion: Bool,
        minimumInterval: TimeInterval? = nil
    ) -> AnimationTimelineSchedule {
        guard let minimumInterval else {
            return .animation(paused: reduceMotion)
        }
        return .animation(minimumInterval: minimumInterval, paused: reduceMotion)
    }
}

// MARK: - View helper

public extension View {
    /// Runs `body` only when ambient animation is allowed; otherwise renders
    /// `staticBody`. Keeps the reduce-motion branch next to the animation it
    /// disables instead of scattering `if !reduceMotion` through the tree.
    @ViewBuilder
    func ambientMotion<Animated: View, Static: View>(
        reduceMotion: Bool,
        @ViewBuilder animated body: () -> Animated,
        @ViewBuilder otherwise staticBody: () -> Static
    ) -> some View {
        if PurahMotionPolicy.allowsAmbientAnimation(reduceMotion: reduceMotion) {
            body()
        } else {
            staticBody()
        }
    }
}
