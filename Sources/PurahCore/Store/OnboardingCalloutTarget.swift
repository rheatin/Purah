import CoreGraphics

/// The one place the onboarding focus frame should be drawn.
///
/// Views measure the control the person is meant to press and publish its
/// screen rect. The callout window is owned by the app shell, so a frame near
/// a rail edge is never clipped by that rail's own narrow window.
public enum OnboardingCalloutSide: String, CaseIterable, Codable, Sendable {
    case leading
    case trailing
    case above
    case below
}

/// Which direction the callout's arrow points.
public enum OnboardingCalloutArrow: String, Codable, Sendable {
    /// Point at the framed control itself.
    case towardTarget
    case up
    case down
    case leading
    case trailing
}

public struct OnboardingCalloutTarget: Equatable, Sendable {
    /// The control's rect in AppKit screen coordinates (origin bottom-left).
    public var screenRect: CGRect
    /// Optional preferred label side; the geometry still prefers the side with
    /// the most room when this one cannot fit.
    public var sideCandidate: OnboardingCalloutSide?
    public var labelKey: String
    /// The target pod's accent, or nil for dock controls (primary accent).
    public var accentHex: String?
    public var arrow: OnboardingCalloutArrow

    public init(
        screenRect: CGRect,
        sideCandidate: OnboardingCalloutSide? = nil,
        labelKey: String,
        accentHex: String? = nil,
        arrow: OnboardingCalloutArrow = .towardTarget
    ) {
        self.screenRect = screenRect
        self.sideCandidate = sideCandidate
        self.labelKey = labelKey
        self.accentHex = accentHex
        self.arrow = arrow
    }
}
