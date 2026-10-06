// Sources/PurahUI/Theme/LiquidGlassModifier.swift
import SwiftUI
import AppKit

public struct LiquidDrawerBackgroundModifier: ViewModifier {
    public let shape: UnevenRoundedRectangle
    public let accentColor: Color
    @Environment(\.colorScheme) private var colorScheme

    public init(shape: UnevenRoundedRectangle, accentColor: Color) {
        self.shape = shape
        self.accentColor = accentColor
    }

    public func body(content: Content) -> some View {
        content
            .background(
                shape
                    .fill(.ultraThinMaterial)
            )
            .clipShape(shape)
            .contentShape(shape)
            .overlay(
                shape
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(colorScheme == .dark ? 0.25 : 0.50), location: 0.0),
                                .init(color: accentColor.opacity(0.45), location: 0.35),
                                .init(color: Color.white.opacity(colorScheme == .dark ? 0.08 : 0.18), location: 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.2
                    )
            )
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.45 : 0.16),
                radius: 12,
                x: 0,
                y: 4
            )
            .compositingGroup()
    }
}

public struct LiquidCardBackgroundModifier: ViewModifier {
    public let cornerRadius: CGFloat
    public let strokeColor: Color?
    @Environment(\.colorScheme) private var colorScheme

    public init(cornerRadius: CGFloat = 10, strokeColor: Color? = nil) {
        self.cornerRadius = cornerRadius
        self.strokeColor = strokeColor
    }

    public func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(
                shape
                    .fill(.ultraThinMaterial)
            )
            .clipShape(shape)
            .overlay(
                shape
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(colorScheme == .dark ? 0.22 : 0.45), location: 0.0),
                                .init(color: (strokeColor ?? Color(nsColor: .separatorColor)).opacity(0.35), location: 0.5),
                                .init(color: Color.white.opacity(colorScheme == .dark ? 0.06 : 0.12), location: 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.0
                    )
            )
    }
}

public extension View {
    func liquidDrawerBackground(shape: UnevenRoundedRectangle, accentColor: Color) -> some View {
        modifier(LiquidDrawerBackgroundModifier(shape: shape, accentColor: accentColor))
    }

    func liquidCardBackground(cornerRadius: CGFloat = 10, strokeColor: Color? = nil) -> some View {
        modifier(LiquidCardBackgroundModifier(cornerRadius: cornerRadius, strokeColor: strokeColor))
    }
}
