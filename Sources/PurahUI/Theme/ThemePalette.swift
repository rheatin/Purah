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

    public func podColor(for podId: String) -> Color {
        switch podId {
        case "calendar":
            return Color(red: 1.0, green: 0.35, blue: 0.38) // 日程珊瑚红橙
        case "todo":
            return Color(red: 1.0, green: 0.62, blue: 0.04) // 待办活力琥珀金
        case "music":
            return Color(red: 1.0, green: 0.18, blue: 0.45) // 音乐霓虹品红
        case "shelf":
            return Color(red: 0.18, green: 0.82, blue: 0.55) // 暂存架极客薄荷绿
        case "notes":
            return Color(red: 1.0, green: 0.82, blue: 0.15) // 便签暖阳金黄
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
