// Sources/PurahUI/Theme/ThemePalette.swift
import SwiftUI
import AppKit
import PurahCore

public struct ThemePalette: Sendable {
    public let style: AppThemeStyle
    public let primaryAccent: Color
    public let secondaryAccent: Color
    public let background: Color
    public let surfaceBackground: Color
    public let glassBackground: Color
    public let solidDrawerBackground: Color
    public let railBackground: Color
    public let borderColor: Color
    public let highlightBorderColor: Color
    public let warningAccent: Color
    public let dangerAccent: Color
    public let successAccent: Color
    public let useGlow: Bool
    public let useRuneCorners: Bool
    public let cornerRadius: CGFloat
    public let fontTitle: Font
    public let fontMono: Font

    @MainActor
    public func podColor(for podId: String, store: PurahWorkspaceStore? = nil) -> Color {
        // 1. Plugin-provided dynamic real-time accent color (e.g. telemetry load color)
        if let dynamicColor = PluginRegistry.shared.catalogPlugin(for: podId)?.dynamicAccentColor(store: store) {
            return dynamicColor
        }

        // 2. Custom user color override
        if let store, let customHex = store.customPodColors[podId] {
            return Color(hex: customHex)
        }

        // 3. Plugin manifest default color hex
        if let manifest = PluginRegistry.shared.catalogPlugin(for: podId)?.manifest {
            return Color(hex: manifest.defaultColorHex)
        }

        // 4. SlotPod default color hex
        if let pod = store?.pods.first(where: { $0.id == podId }) {
            return Color(hex: pod.defaultColorHex)
        }

        // 5. Fallback primary accent
        return primaryAccent
    }

    public static func palette(for style: AppThemeStyle = .native) -> ThemePalette {
        ThemePalette(
            style: .native,
            primaryAccent: Color.accentColor,
            secondaryAccent: Color.secondary,
            background: Color(nsColor: .windowBackgroundColor),
            surfaceBackground: Color(nsColor: .controlBackgroundColor),
            glassBackground: Color(nsColor: .windowBackgroundColor).opacity(0.85),
            solidDrawerBackground: Color(nsColor: .windowBackgroundColor).opacity(0.75),
            railBackground: Color(nsColor: .windowBackgroundColor),
            borderColor: Color(nsColor: .separatorColor).opacity(0.6),
            highlightBorderColor: Color.accentColor.opacity(0.8),
            warningAccent: Color.orange,
            dangerAccent: Color.red,
            successAccent: Color.green,
            useGlow: false,
            useRuneCorners: false,
            cornerRadius: 12.0,
            fontTitle: Font.system(.headline, design: .rounded).weight(.semibold),
            fontMono: Font.system(.caption, design: .monospaced)
        )
    }
}

public extension Color {
    @MainActor
    static func readableTagTint(hex: String) -> Color {
        let background = NSColor(ThemeManager.shared.palette.surfaceBackground)
            .usingColorSpace(.sRGB)
        let components = background.map {
            HexColor.Components(
                red: Double($0.redComponent),
                green: Double($0.greenComponent),
                blue: Double($0.blueComponent),
                alpha: Double($0.alphaComponent)
            )
        } ?? HexColor.Components(red: 1, green: 1, blue: 1, alpha: 1)
        return Color(hex: TagTintContrast.adjustedHex(hex: hex, background: components))
    }

    init(hex: String) {
        let components = HexColor.parse(hex)
            ?? HexColor.Components(red: 0, green: 245.0 / 255.0, blue: 212.0 / 255.0, alpha: 1.0)
        self.init(
            .sRGB,
            red: components.red,
            green: components.green,
            blue: components.blue,
            opacity: components.alpha
        )
    }

    func toHex() -> String? {
        let nsColor = NSColor(self)
        guard let rgbColor = nsColor.usingColorSpace(.sRGB) else { return nil }
        // Clamped: an extended-range colour can push a component past 1.0, and
        // the table has no entry there.
        let r = Self.byte(rgbColor.redComponent)
        let g = Self.byte(rgbColor.greenComponent)
        let b = Self.byte(rgbColor.blueComponent)
        // A lookup beats `String(format:)` here: this runs once per rail chip
        // per render, and the format path builds an NSString through the CF
        // format parser each time.
        return "#" + Self.hexBytes[r] + Self.hexBytes[g] + Self.hexBytes[b]
    }

    private static let hexBytes: [String] = (0...255).map { String(format: "%02X", $0) }

    private static func byte(_ component: CGFloat) -> Int {
        min(255, max(0, Int((component * 255).rounded())))
    }

    /// Returns deep slate-black (#0F111A) for medium/bright accent fills, or crisp white for very dark fills.
    var highContrastInk: Color {
        if let srgb = NSColor(self).usingColorSpace(.sRGB) {
            let luminance = 0.2126 * srgb.redComponent + 0.7152 * srgb.greenComponent + 0.0722 * srgb.blueComponent
            if luminance < 0.28 {
                return .white
            }
        }
        return Self.slateInk
    }

    /// The slate-black used on light and mid-tone fills (#0F111A).
    ///
    /// `highContrastInk` needs a colour to evaluate; badges drawn on a fixed
    /// fill (orange, green, yellow) always want this value, so it is exposed on
    /// its own rather than spelled out as a literal at every call site.
    static let slateInk = Color(red: 0.059, green: 0.067, blue: 0.102)
}

/// Keeps a tag's identity but gives its text enough contrast on light surfaces.
public enum TagTintContrast {
    public static let minimumRatio = 4.5

    public static func adjustedHex(
        hex: String,
        background: HexColor.Components
    ) -> String {
        guard let original = HexColor.parse(hex) else { return hex }
        let backgroundLuminance = relativeLuminance(background)
        guard backgroundLuminance >= 0.18 else { return hex }
        guard contrastRatio(foreground: original, background: background) < minimumRatio else {
            return hex
        }

        var candidate = original
        for _ in 0..<80 {
            candidate = HexColor.Components(
                red: candidate.red * 0.92,
                green: candidate.green * 0.92,
                blue: candidate.blue * 0.92,
                alpha: candidate.alpha
            )
            let candidateHex = hexString(candidate)
            if let rounded = HexColor.parse(candidateHex),
               contrastRatio(foreground: rounded, background: background) >= minimumRatio {
                return candidateHex
            }
        }
        return "#000000"
    }

    public static func contrastRatio(
        foreground: HexColor.Components,
        background: HexColor.Components
    ) -> Double {
        let first = relativeLuminance(foreground)
        let second = relativeLuminance(background)
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    public static func relativeLuminance(_ color: HexColor.Components) -> Double {
        0.2126 * linear(color.red)
            + 0.7152 * linear(color.green)
            + 0.0722 * linear(color.blue)
    }

    private static func linear(_ component: Double) -> Double {
        component <= 0.04045
            ? component / 12.92
            : pow((component + 0.055) / 1.055, 2.4)
    }

    private static func hexString(_ color: HexColor.Components) -> String {
        let red = byte(color.red)
        let green = byte(color.green)
        let blue = byte(color.blue)
        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    private static func byte(_ component: Double) -> Int {
        min(255, max(0, Int((component * 255).rounded())))
    }
}
