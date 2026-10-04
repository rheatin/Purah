// Sources/PurahUI/Theme/PurahTheme.swift
import SwiftUI

public enum PurahTheme {
    // 经典左纳乌/希卡青绿微光
    public static let cyanGlow = Color(red: 0.0, green: 0.96, blue: 0.83) // #00F5D4
    public static let electricBlue = Color(red: 0.08, green: 1.0, blue: 0.93) // #14FFEC
    public static let darkSlate = Color(red: 0.04, green: 0.07, blue: 0.10) // #0B1218
    public static let slateSurface = Color(red: 0.06, green: 0.11, blue: 0.15) // #0F1C26
    public static let glassBackground = Color(red: 0.05, green: 0.11, blue: 0.14).opacity(0.90)
    public static let amberAccent = Color(red: 1.0, green: 0.72, blue: 0.01) // #FFB703
    public static let sheikahRed = Color(red: 1.0, green: 0.35, blue: 0.37) // #FF5A5F
    public static let mutedBorder = Color(red: 0.11, green: 0.25, blue: 0.30)
    public static let energyActive = Color(red: 0.0, green: 0.90, blue: 0.65) // #00E5A3

    public static let monoFont = Font.system(.caption, design: .monospaced)
    public static let monoLarge = Font.system(.subheadline, design: .monospaced).weight(.semibold)
    public static let titleFont = Font.system(.headline, design: .rounded).weight(.bold)
    public static let displayFont = Font.system(.title3, design: .rounded).weight(.heavy)
}
