// Sources/PurahUI/Theme/LiquidGlassModifier.swift
import SwiftUI
import AppKit

// MARK: - Chromatic Harmony Color Helper
public extension Color {
    /// 计算基于 HSB 色域空间谐振偏移 (+35°) 的 Apple Music 极光次级渗透色
    func harmonicSecondary() -> Color {
        let nsColor = NSColor(self)
        guard let rgb = nsColor.usingColorSpace(.sRGB) else {
            return self.opacity(0.85)
        }
        var h: CGFloat = 0
        var s: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        rgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)

        // 色相顺时针自然偏移约 35 度 (0.097 in 0.0~1.0 range)
        let shiftedHue = (h + 0.10).truncatingRemainder(dividingBy: 1.0)
        let adjustedSat = min(max(s * 0.90, 0.45), 0.95)
        let adjustedBri = min(max(b * 0.95, 0.55), 1.0)

        return Color(
            hue: Double(shiftedHue),
            saturation: Double(adjustedSat),
            brightness: Double(adjustedBri),
            opacity: Double(a)
        )
    }
}

// MARK: - Apple Music Live Lyrics Aurora Background Modifier for Drawers
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
                auroraBackground
            )
            .clipShape(shape)
            .contentShape(shape)
            .overlay(
                // 极简微弱折射微边框 (0.8pt，告别生硬粗白框)
                shape
                    .strokeBorder(
                        Color.white.opacity(colorScheme == .dark ? 0.16 : 0.28),
                        lineWidth: 0.8
                    )
            )
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.38 : 0.14),
                radius: 16,
                x: 0,
                y: 5
            )
            .compositingGroup()
    }

    @ViewBuilder
    private var auroraBackground: some View {
        let secondary = accentColor.harmonicSecondary()

        ZStack {
            // 1. 半透明微透底板
            Color.black.opacity(colorScheme == .dark ? 0.45 : 0.20)

            // 2. 双点高斯色斑极光网格 (Chromatic Aurora Mesh)
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height

                ZStack {
                    // 主强调色气泡 (右上)
                    Circle()
                        .fill(accentColor.opacity(colorScheme == .dark ? 0.36 : 0.28))
                        .frame(width: max(w * 0.85, 120), height: max(w * 0.85, 120))
                        .offset(x: w * 0.22, y: -h * 0.15)
                        .blur(radius: 45)

                    // 次级谐振色气泡 (左下)
                    Circle()
                        .fill(secondary.opacity(colorScheme == .dark ? 0.32 : 0.24))
                        .frame(width: max(w * 0.95, 130), height: max(w * 0.95, 130))
                        .offset(x: -w * 0.25, y: h * 0.25)
                        .blur(radius: 50)
                }
            }

            // 3. Apple 原生 Ultra-Thin 磨砂面罩 (柔化融合底层极光)
            Rectangle()
                .fill(.ultraThinMaterial.opacity(0.85))
        }
    }
}

// MARK: - Apple Music Aurora Card Modifier
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
        let accent = strokeColor ?? Color.accentColor

        content
            .background(
                auroraCardBackground(accent: accent)
            )
            .clipShape(shape)
            .overlay(
                shape
                    .strokeBorder(
                        Color.white.opacity(colorScheme == .dark ? 0.16 : 0.28),
                        lineWidth: 0.8
                    )
            )
    }

    @ViewBuilder
    private func auroraCardBackground(accent: Color) -> some View {
        let secondary = accent.harmonicSecondary()

        ZStack {
            Color.black.opacity(colorScheme == .dark ? 0.35 : 0.15)

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height

                ZStack {
                    Circle()
                        .fill(accent.opacity(colorScheme == .dark ? 0.32 : 0.22))
                        .frame(width: max(w * 0.75, 80), height: max(w * 0.75, 80))
                        .offset(x: w * 0.20, y: -h * 0.10)
                        .blur(radius: 35)

                    Circle()
                        .fill(secondary.opacity(colorScheme == .dark ? 0.28 : 0.18))
                        .frame(width: max(w * 0.85, 90), height: max(w * 0.85, 90))
                        .offset(x: -w * 0.20, y: h * 0.15)
                        .blur(radius: 40)
                }
            }

            Rectangle()
                .fill(.ultraThinMaterial.opacity(0.85))
        }
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
