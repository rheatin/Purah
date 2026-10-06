// Tests/PurahCoreTests/ThemeTests.swift
import Testing
@testable import PurahCore
@testable import PurahUI

@Suite("Theme System Tests")
@MainActor
struct ThemeTests {
    @Test("Defaults to macOS Liquid Native theme with continuous curvature")
    @MainActor
    func testLiquidNativeTheme() {
        let theme = ThemeManager()
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
}
