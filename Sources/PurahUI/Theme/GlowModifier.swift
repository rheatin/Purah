// Sources/PurahUI/Theme/GlowModifier.swift
import SwiftUI

public struct PurahGlowModifier: ViewModifier {
    public var color: Color
    public var radius: CGFloat

    public func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(0.8), radius: radius / 2)
            .shadow(color: color.opacity(0.4), radius: radius)
    }
}

public extension View {
    func purahGlow(color: Color = PurahTheme.cyanGlow, radius: CGFloat = 8) -> some View {
        modifier(PurahGlowModifier(color: color, radius: radius))
    }
}
