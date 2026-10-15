// Tests/PurahCoreTests/LocalizationTests.swift
import Testing
import Foundation
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

    @Test("LocalizationManager persists currentLanguage to UserDefaults")
    @MainActor
    func testLanguagePersistence() {
        let previous = LocalizationManager.shared.currentLanguage
        defer {
            LocalizationManager.shared.currentLanguage = previous
        }

        LocalizationManager.shared.currentLanguage = .french
        #expect(UserDefaults.standard.string(forKey: "purah.appLanguage") == "fr")

        let freshManager = LocalizationManager()
        #expect(freshManager.currentLanguage == .french)
        #expect(freshManager.localized("tab.interaction") == "Mouvement et Général")

        LocalizationManager.shared.currentLanguage = .german
        #expect(UserDefaults.standard.string(forKey: "purah.appLanguage") == "de")
        let germanManager = LocalizationManager()
        #expect(germanManager.currentLanguage == .german)
        #expect(germanManager.localized("tab.interaction") == "Bewegung & Allgemein")
    }
}
