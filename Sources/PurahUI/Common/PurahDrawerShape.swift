// Sources/PurahUI/Common/PurahDrawerShape.swift
import SwiftUI
import PurahCore

/// The edge-flush card outline every drawer uses.
///
/// A drawer is an extrusion of the screen bezel, so its bezel-facing corners
/// are square while the floating edge is rounded. Every card used to spell this
/// out by hand — seven copies, with the radius drifting between 8 and 10
/// depending on which file it was in. One factory keeps the geometry honest and
/// makes the radius a deliberate choice instead of a copy-paste artefact.
public enum PurahDrawerShape {
    /// Composite pod drawers (Music, Vitals, Clipboard, …).
    public static let compositeRadius: CGFloat = 10.0
    /// Stepped sub-item cards and chips, which are smaller and read better with
    /// a slightly tighter corner.
    public static let steppedRadius: CGFloat = 8.0

    /// Rounded on the floating edge, square against the bezel.
    public static func cornerRadii(edge: MountEdge, radius: CGFloat) -> CornerRadii {
        switch edge {
        case .right:
            // Floating edge is on the left; the right side sits flush on the bezel.
            return CornerRadii(
                topLeading: radius,
                bottomLeading: radius,
                bottomTrailing: 0,
                topTrailing: 0
            )
        case .left:
            return CornerRadii(
                topLeading: 0,
                bottomLeading: 0,
                bottomTrailing: radius,
                topTrailing: radius
            )
        }
    }

    public struct CornerRadii: Equatable, Sendable {
        public var topLeading: CGFloat
        public var bottomLeading: CGFloat
        public var bottomTrailing: CGFloat
        public var topTrailing: CGFloat
    }

    /// Rounded on the floating edge, square against the bezel.
    public static func edgeFlush(edge: MountEdge, radius: CGFloat) -> UnevenRoundedRectangle {
        let radii = cornerRadii(edge: edge, radius: radius)
        return UnevenRoundedRectangle(
            topLeadingRadius: radii.topLeading,
            bottomLeadingRadius: radii.bottomLeading,
            bottomTrailingRadius: radii.bottomTrailing,
            topTrailingRadius: radii.topTrailing,
            style: .continuous
        )
    }

    public static func composite(edge: MountEdge) -> UnevenRoundedRectangle {
        edgeFlush(edge: edge, radius: compositeRadius)
    }

    public static func stepped(edge: MountEdge) -> UnevenRoundedRectangle {
        edgeFlush(edge: edge, radius: steppedRadius)
    }
}
