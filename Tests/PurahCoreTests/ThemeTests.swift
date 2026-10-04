// Tests/PurahCoreTests/ThemeTests.swift
import Testing
@testable import PurahCore
@testable import PurahUI

@Suite("Theme System Tests")
struct ThemeTests {
    @Test("Defaults to macOS Native theme")
    func testDefaultTheme() {
        let theme = ThemeManager()
        #expect(theme.currentStyle == .native)
        #expect(!theme.palette.useGlow)
        #expect(!theme.palette.useRuneCorners)
    }

    @Test("Can switch to Purah Pad theme")
    func testThemeSwitching() {
        let theme = ThemeManager()
        theme.currentStyle = .purahPad
        #expect(theme.currentStyle == .purahPad)
        #expect(theme.palette.useGlow)
        #expect(theme.palette.useRuneCorners)

        // Switch back to default
        theme.currentStyle = .native
        #expect(theme.currentStyle == .native)
    }
}
