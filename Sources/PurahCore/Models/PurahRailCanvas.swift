// Sources/PurahCore/Models/PurahRailCanvas.swift
import CoreGraphics

/// The rail panel's horizontal canvas budget.
///
/// The docked canvas normally stays at its compact width. It widens only far
/// enough for the alert halo, then returns without changing the rail's
/// screen-edge anchor.
public enum PurahRailCanvas {
    public static let compactWidth: CGFloat = 28
    public static let alertWidth: CGFloat = 48
    public static let maxWidth: CGFloat = 580

    public static func width(isExpanded: Bool, isAlerting: Bool) -> CGFloat {
        if isExpanded { return maxWidth }
        return isAlerting ? alertWidth : compactWidth
    }

    /// How far a halo may extend inward past its base rail width.
    public static func haloLimit(baseWidth: CGFloat) -> CGFloat {
        max(alertWidth - max(baseWidth, 0), 0)
    }
}
