// Tests/PurahCoreTests/LocalizationTests.swift
import Testing
@testable import PurahCore

@Suite("Localization Engine Tests")
struct LocalizationTests {
    @Test("Translates keys to English and Chinese correctly")
    func testTranslation() {
        let loc = LocalizationManager()

        loc.currentLanguage = .english
        #expect(loc.localized("app.name") == "Purah Pad")
        #expect(loc.localized("menu.autoLayout") == "Magic Ergonomics Auto-Layout")
        #expect(loc.localized("preset.balanced.title") == "Balanced Ergonomics")

        loc.currentLanguage = .simplifiedChinese
        #expect(loc.localized("app.name") == "普尔亚平板 (Purah Pad)")
        #expect(loc.localized("menu.autoLayout") == "一键人体工学排布")
        #expect(loc.localized("preset.balanced.title") == "均衡工学模式 (Balanced)")
    }

    @Test("Fallbacks to key when missing")
    func testFallback() {
        let loc = LocalizationManager()
        #expect(loc.localized("unknown.key") == "unknown.key")
    }
}
