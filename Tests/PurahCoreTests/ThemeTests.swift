// Tests/PurahCoreTests/ThemeTests.swift
import Testing
import SwiftUI
import AppKit
@testable import PurahCore
@testable import PurahUI

@Suite("Theme System Tests")
@MainActor
struct ThemeTests {
    @Test("Defaults to macOS Liquid Native theme with continuous curvature")
    @MainActor
    func testLiquidNativeTheme() {
        let suite = UserDefaults(suiteName: "test.theme.native.\(UUID().uuidString)")!
        let theme = ThemeManager(defaults: suite)
        #expect(theme.currentStyle == .native)
        #expect(!theme.palette.useGlow)
        #expect(!theme.palette.useRuneCorners)
        #expect(theme.palette.cornerRadius == 12.0)
    }

    @Test("AppThemeStyle has single unified Liquid Native style")
    func testSingleUnifiedStyle() {
        #expect(AppThemeStyle.allCases.count == 1)
        #expect(AppThemeStyle.native.displayName.contains("Liquid"))
    }

    @Test("adaptiveInk preserves neon accents in Dark mode and guarantees >=4.5 contrast in Light mode")
    func testAdaptiveInkLightModeContrast() throws {
        let neonHexes = ["#00F5D4", "#FFD60A", "#00E5A3", "#2ED573", "#A78BFA", "#FF9F0A"]
        for hex in neonHexes {
            let base = Color(hex: hex)
            let darkAdapted = base.adaptiveInk(for: .dark)
            #expect(darkAdapted.toHex() == base.toHex(), "Dark mode must keep \(hex) verbatim")

            let lightAdapted = base.adaptiveInk(for: .light)
            let adaptedHex = try #require(lightAdapted.toHex())
            let fg = try #require(HexColor.parse(adaptedHex))
            let ratio = TagTintContrast.contrastRatio(foreground: fg, background: TagTintContrast.lightGlassReference)
            #expect(ratio >= 4.5, "\(hex) adapted to \(adaptedHex) must reach >= 4.5 contrast on light glass, got \(ratio)")
        }
    }

    @Test("PurahSurfaceTokens distinguishes Dark and Light polarity")
    func testSurfaceTokensPolarity() {
        let dark = ThemePalette.surfaceTokens(for: .dark)
        let light = ThemePalette.surfaceTokens(for: .light)
        #expect(dark.isDark == true)
        #expect(light.isDark == false)
    }

    @Test("AppAppearanceMode persists across ThemeManager instances and resolves NSAppearance")
    func testAppearanceModePersistenceAndResolution() {
        let suiteName = "test.theme.appearance.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = ThemeManager(defaults: defaults)
        #expect(first.appearanceMode == .system)
        #expect(first.resolvedNSAppearance == nil)

        first.appearanceMode = .dark
        #expect(first.resolvedNSAppearance?.name == .darkAqua)

        let second = ThemeManager(defaults: defaults)
        #expect(second.appearanceMode == .dark)

        second.appearanceMode = .light
        #expect(second.resolvedNSAppearance?.name == .aqua)

        let third = ThemeManager(defaults: defaults)
        #expect(third.appearanceMode == .light)
    }
}
