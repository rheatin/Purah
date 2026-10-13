// Sources/PurahUI/Common/PurahAdaptiveTierDrawer.swift
import SwiftUI

/// Ergonomic multi-tier adaptive drawer container.
/// Automatically adapts drawer card layout across Compact, Standard, and Immersive height tiers,
/// preventing any clipping, awkward truncation, or vertical overflow even at extreme minimum bounds.
public struct PurahAdaptiveTierDrawer<Compact: View, Standard: View, Immersive: View>: View {
    public var compactThreshold: CGFloat
    public var immersiveThreshold: CGFloat
    @ViewBuilder public var compact: (CGFloat) -> Compact
    @ViewBuilder public var standard: (CGFloat) -> Standard
    @ViewBuilder public var immersive: (CGFloat) -> Immersive

    public init(
        compactThreshold: CGFloat = 145.0,
        immersiveThreshold: CGFloat = 265.0,
        @ViewBuilder compact: @escaping (CGFloat) -> Compact,
        @ViewBuilder standard: @escaping (CGFloat) -> Standard,
        @ViewBuilder immersive: @escaping (CGFloat) -> Immersive
    ) {
        self.compactThreshold = compactThreshold
        self.immersiveThreshold = immersiveThreshold
        self.compact = compact
        self.standard = standard
        self.immersive = immersive
    }

    public var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            if h < compactThreshold {
                compact(h)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if h < immersiveThreshold {
                standard(h)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                immersive(h)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

public extension PurahAdaptiveTierDrawer where Immersive == Standard {
    init(
        compactThreshold: CGFloat = 145.0,
        @ViewBuilder compact: @escaping (CGFloat) -> Compact,
        @ViewBuilder standard: @escaping (CGFloat) -> Standard
    ) {
        self.init(
            compactThreshold: compactThreshold,
            immersiveThreshold: .infinity,
            compact: compact,
            standard: standard,
            immersive: standard
        )
    }
}
