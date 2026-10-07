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
}
