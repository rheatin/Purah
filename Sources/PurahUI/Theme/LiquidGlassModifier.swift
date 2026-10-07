// Sources/PurahUI/Theme/LiquidGlassModifier.swift
import SwiftUI
import AppKit

// MARK: - Native macOS Behind-Window Visual Effect View
public struct NativeVisualEffectView: NSViewRepresentable {
    public let material: NSVisualEffectView.Material
    public let blendingMode: NSVisualEffectView.BlendingMode
    public let state: NSVisualEffectView.State

    public init(
        material: NSVisualEffectView.Material = .hudWindow,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
        state: NSVisualEffectView.State = .active
    ) {
        self.material = material
        self.blendingMode = blendingMode
        self.state = state
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.wantsLayer = true
        return view
    }

    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

// MARK: - Chromatic Harmony Color Helper
private final class ColorHarmonicCache: @unchecked Sendable {
    static let shared = ColorHarmonicCache()
    private var cache: [Color: Color] = [:]
    private let lock = NSLock()

    func harmonic(for color: Color) -> Color {
        lock.lock()
        defer { lock.unlock() }
        if let existing = cache[color] {
            return existing
        }
        let nsColor = NSColor(color)
        guard let rgb = nsColor.usingColorSpace(.sRGB) else {
            let fallback = color.opacity(0.85)
            cache[color] = fallback
            return fallback
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

        let result = Color(
            hue: Double(shiftedHue),
            saturation: Double(adjustedSat),
            brightness: Double(adjustedBri),
            opacity: Double(a)
        )
        cache[color] = result
        return result
    }
}

public extension Color {
    /// 计算基于 HSB 色域空间谐振偏移 (+35°) 的 Apple Music 极光次级渗透色 (带缓存极速路径)
    func harmonicSecondary() -> Color {
        ColorHarmonicCache.shared.harmonic(for: self)
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
                // 极简微弱折射微边框 (0.8pt，纯净自然)
                shape
                    .strokeBorder(
                        Color.white.opacity(colorScheme == .dark ? 0.16 : 0.28),
                        lineWidth: 0.8
                    )
            )
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.12),
                radius: 16,
                x: 0,
                y: 5
            )
    }

    @ViewBuilder
    private var auroraBackground: some View {
        let secondary = accentColor.harmonicSecondary()

        ZStack {
            // 1. macOS 核心硬件级 Behind-Window 模糊：100% 实时穿透并模糊底层活动窗口、照片或桌面！
            NativeVisualEffectView(material: .hudWindow, blendingMode: .behindWindow)

            // 2. Apple Music 极光氛围微晕 (透光率极高，仅 8%~14% 浓度，绝不遮蔽底层画面)
            LinearGradient(
                stops: [
                    .init(color: accentColor.opacity(colorScheme == .dark ? 0.14 : 0.08), location: 0.0),
                    .init(color: secondary.opacity(colorScheme == .dark ? 0.09 : 0.05), location: 0.65),
                    .init(color: Color.clear, location: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
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
            NativeVisualEffectView(material: .hudWindow, blendingMode: .behindWindow)

            LinearGradient(
                stops: [
                    .init(color: accent.opacity(colorScheme == .dark ? 0.12 : 0.06), location: 0.0),
                    .init(color: secondary.opacity(colorScheme == .dark ? 0.08 : 0.04), location: 0.70),
                    .init(color: Color.clear, location: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
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
