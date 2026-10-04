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

    public func podColor(for podId: String, store: PurahWorkspaceStore? = nil) -> Color {
        if let store = store, let customHex = store.customPodColors[podId] {
            return Color(hex: customHex)
        }
        switch podId {
        case "calendar":
            return Color(red: 1.0, green: 0.35, blue: 0.38) // Coral Red
        case "todo":
            return Color(red: 1.0, green: 0.62, blue: 0.04) // Amber Gold
        case "music":
            return Color(red: 1.0, green: 0.18, blue: 0.45) // Neon Magenta
        case "shelf":
            return Color(red: 0.18, green: 0.82, blue: 0.55) // Mint Green
        case "notes":
            return Color(red: 1.0, green: 0.82, blue: 0.15) // Warm Gold
        case "vitals":
            // Hardware Vitals: Dynamic Green -> Orange -> Red based on CPU load
            let cpu = HardwareVitalsService.shared.metrics.cpuUsage
            if cpu > 0.80 {
                return Color(red: 1.0, green: 0.23, blue: 0.19) // High Load Red
            } else if cpu > 0.50 {
                return Color(red: 1.0, green: 0.58, blue: 0.0) // Medium Load Orange
            } else {
                return Color(red: 0.20, green: 0.78, blue: 0.35) // Healthy Green
            }
        case "scripts":
            return Color(red: 0.42, green: 0.36, blue: 0.91) // Obsidian Purple
        default:
            return primaryAccent
        }
    }

    public static func palette(for style: AppThemeStyle) -> ThemePalette {
        switch style {
        case .native:
            return ThemePalette(
                style: .native,
                primaryAccent: Color.accentColor,
                secondaryAccent: Color.secondary,
                background: Color(nsColor: .windowBackgroundColor),
                surfaceBackground: Color(nsColor: .controlBackgroundColor),
                glassBackground: Color(nsColor: .windowBackgroundColor).opacity(0.88),
                solidDrawerBackground: Color(red: 0.12, green: 0.14, blue: 0.17),
                railBackground: Color(nsColor: .windowBackgroundColor),
                borderColor: Color(nsColor: .separatorColor),
                highlightBorderColor: Color.accentColor.opacity(0.7),
                warningAccent: Color.orange,
                dangerAccent: Color.red,
                successAccent: Color.green,
                useGlow: false,
                useRuneCorners: false,
                cornerRadius: 10.0,
                fontTitle: Font.system(.headline, design: .default).weight(.semibold),
                fontMono: Font.system(.caption, design: .default)
            )
        case .purahPad:
            return ThemePalette(
                style: .purahPad,
                primaryAccent: PurahTheme.cyanGlow,
                secondaryAccent: PurahTheme.electricBlue,
                background: PurahTheme.darkSlate,
                surfaceBackground: PurahTheme.slateSurface,
                glassBackground: PurahTheme.glassBackground,
                solidDrawerBackground: Color(red: 0.05, green: 0.09, blue: 0.12),
                railBackground: PurahTheme.darkSlate,
                borderColor: PurahTheme.mutedBorder,
                highlightBorderColor: PurahTheme.cyanGlow,
                warningAccent: PurahTheme.amberAccent,
                dangerAccent: PurahTheme.sheikahRed,
                successAccent: PurahTheme.energyActive,
                useGlow: true,
                useRuneCorners: true,
                cornerRadius: 14.0,
                fontTitle: PurahTheme.titleFont,
                fontMono: PurahTheme.monoFont
            )
        }
    }
}

public extension Color {
    init(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch clean.count {
        case 6:
            (r, g, b, a) = (int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF, 255)
        case 8:
            (r, g, b, a) = (int >> 24 & 0xFF, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (r, g, b, a) = (0, 245, 212, 255)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255.0,
            green: Double(g) / 255.0,
            blue: Double(b) / 255.0,
            opacity: Double(a) / 255.0
        )
    }

    func toHex() -> String? {
        let nsColor = NSColor(self)
        guard let rgbColor = nsColor.usingColorSpace(.sRGB) else { return nil }
        let r = Int(round(rgbColor.redComponent * 255))
        let g = Int(round(rgbColor.greenComponent * 255))
        let b = Int(round(rgbColor.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
