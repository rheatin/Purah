// Tests/PurahCoreTests/LocalizationTests.swift
import Testing
@testable import PurahCore

@Suite("Localization Engine Tests")
@MainActor
struct LocalizationTests {
    @Test("Translates keys to English correctly")
    @MainActor
    func testTranslation() {
        let loc = LocalizationManager()

        loc.currentLanguage = .english
        #expect(loc.localized("app.name") == "Purah Pad")
        #expect(loc.localized("menu.autoLayout") == "Magic Ergonomics Auto-Layout")
        #expect(loc.localized("preset.balanced.title") == "Balanced Ergonomics")
    }

    @Test("Fallbacks to key when missing")
    @MainActor
    func testFallback() {
        let loc = LocalizationManager()
        #expect(loc.localized("unknown.key") == "unknown.key")
    }

    @Test("Translates notes.tips.table across all supported languages")
    @MainActor
    func testTableTipsLocalization() {
        let loc = LocalizationManager()

        loc.currentLanguage = .english
        #expect(loc.localized("notes.tips.table") == "Table")

        loc.currentLanguage = .chinese
        #expect(loc.localized("notes.tips.table") == "表格")

        loc.currentLanguage = .traditionalChinese
        #expect(loc.localized("notes.tips.table") == "表格")

        loc.currentLanguage = .japanese
        #expect(loc.localized("notes.tips.table") == "テーブル")

        loc.currentLanguage = .korean
        #expect(loc.localized("notes.tips.table") == "표")

        loc.currentLanguage = .french
        #expect(loc.localized("notes.tips.table") == "Tableau")

        loc.currentLanguage = .german
        #expect(loc.localized("notes.tips.table") == "Tabelle")

        loc.currentLanguage = .spanish
        #expect(loc.localized("notes.tips.table") == "Tabla")
    }
}
