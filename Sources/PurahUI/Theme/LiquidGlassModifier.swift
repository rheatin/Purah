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
                ZStack {
                    // 1. Crystal translucent base tint
                    shape
                        .fill(Color(nsColor: .windowBackgroundColor).opacity(colorScheme == .dark ? 0.30 : 0.45))
                    // 2. High-translucency native ultra-thin material
                    shape
                        .fill(.ultraThinMaterial.opacity(0.82))
                    // 3. Top-down meniscus specular light reflection
                    shape
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(colorScheme == .dark ? 0.12 : 0.24),
                                    Color.white.opacity(colorScheme == .dark ? 0.02 : 0.06),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                }
            )
            .clipShape(shape)
            .contentShape(shape)
            .overlay(
                // Liquid Specular Highlight Rim + Accent Stroke
                shape
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(colorScheme == .dark ? 0.38 : 0.65), location: 0.0),
                                .init(color: accentColor.opacity(0.45), location: 0.35),
                                .init(color: Color.white.opacity(colorScheme == .dark ? 0.12 : 0.22), location: 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.2
                    )
            )
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.12),
                radius: 16,
                x: 0,
                y: 5
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
                ZStack {
                    shape
                        .fill(Color(nsColor: .windowBackgroundColor).opacity(colorScheme == .dark ? 0.25 : 0.40))
                    shape
                        .fill(.ultraThinMaterial.opacity(0.85))
                    shape
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(colorScheme == .dark ? 0.10 : 0.20),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                }
            )
            .clipShape(shape)
            .overlay(
                shape
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(colorScheme == .dark ? 0.30 : 0.55), location: 0.0),
                                .init(color: (strokeColor ?? Color(nsColor: .separatorColor)).opacity(0.40), location: 0.5),
                                .init(color: Color.white.opacity(colorScheme == .dark ? 0.08 : 0.16), location: 1.0)
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
