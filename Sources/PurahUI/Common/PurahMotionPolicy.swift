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

    // MARK: - Named springs
    //
    // These are names for the curves the UI already uses, not new tuning.
    // Values are byte-for-byte what the call sites had before, so adopting one
    // cannot change how anything feels — it only says which *kind* of motion a
    // transition is. A curve that appears once stays inline rather than
    // earning a name; see AGENTS.md §4 for the entrance/exit pair.

    /// Drawer entrance: a natural deceleration onto the bezel.
    public static let drawerEntrance = Animation.spring(response: 0.30, dampingFraction: 0.80)
    /// Drawer retraction: fast and crisp so dismissal never feels sluggish.
    public static let drawerExit = Animation.spring(response: 0.20, dampingFraction: 0.92)

    /// Hover, selection and reflow inside a panel.
    public static let surface = Animation.spring(response: 0.28, dampingFraction: 0.82)
    /// Press-and-release feedback that should land slightly softer.
    public static let surfaceSoft = Animation.spring(response: 0.25, dampingFraction: 0.82)
    /// A small element arriving or leaving.
    public static let micro = Animation.spring(response: 0.22, dampingFraction: 0.82)
    /// The lightest touch: toggles, ticks, inline badges.
    public static let microLight = Animation.spring(response: 0.24, dampingFraction: 0.85)

    /// A pin being tacked into the board — deliberately springy.
    public static let pin = Animation.spring(response: 0.28, dampingFraction: 0.65)
    /// A button popping back after a press.
    public static let buttonPop = Animation.spring(response: 0.26, dampingFraction: 0.55)

    /// Rail reflow while pods are mounted, stacked or resized. Carries a
    /// `blendDuration` so two consecutive layout solves do not fight; it is the
    /// same curve as `drawerEntrance` with a settle window on top.
    public static let railReflow = Animation.spring(response: 0.30, dampingFraction: 0.80, blendDuration: 0.08)

    /// A quick confirm/deny state flip (a copy tick, a metric toggled off).
    public static let confirm = Animation.spring(response: 0.20, dampingFraction: 0.80)

    /// Press-down feedback. Fast and tight so the button feels touched, not
    /// animated. `TactileButtonStyle` and the Music vinyl transport both use it,
    /// so the two never drift apart.
    public static let press = Animation.spring(response: 0.16, dampingFraction: 0.65)

    /// Flipping between rail pages: a touch longer than a drawer move because
    /// the whole rail travels.
    public static let pageFlip = Animation.spring(response: 0.32, dampingFraction: 0.82)

    /// Hover highlight on a row or card. Undamped enough to feel immediate, and
    /// short so it never lags behind the cursor.
    public static let hover = Animation.spring(response: 0.25, dampingFraction: 0.70)

    /// Hover on a large preview card, where a slightly softer settle reads
    /// better than the tight row highlight.
    public static let hoverSoft = Animation.spring(response: 0.28, dampingFraction: 0.70)

    /// Hover/drag state on a shelf row, which carries a thumbnail and a
    /// selection ring and needs a little more body than a text row.
    public static let shelfRow = Animation.spring(response: 0.24, dampingFraction: 0.78)

    /// A chip lifting under the cursor in the live sculptor.
    public static let chipLift = Animation.spring(response: 0.32, dampingFraction: 0.75)

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
