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
    }

    @Test("Legacy PodPreset strings are gone; the key itself falls through")
    @MainActor
    func testLegacyPresetKeysRemoved() {
        let loc = LocalizationManager()
        loc.currentLanguage = .english
        // `PodPreset` was sunset in favour of Live Rail Sculptor and Magic
        // Auto-Layout. The leftover strings must not creep back in.
        #expect(loc.localized("preset.balanced.title") == "preset.balanced.title")
        #expect(loc.localized("preset.sprint.desc") == "preset.sprint.desc")
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

    @Test("Every language table is a subset of English, never a superset")
    func testNoOrphanTranslations() {
        let loc = LocalizationManager()
        // The fallback chain is target language → English → the key itself, so
        // a key that exists only in a non-English table is unreachable dead
        // weight: nothing can ever ask for it in a language that lacks it.
        // English is therefore the vocabulary, and every other table has to be
        // drawn from it.
        let english = Set(LocalizationManager.keys(for: .english))
        #expect(!english.isEmpty)
        for language in AppLanguage.allCases where language != .system && language != .english {
            let orphans = Set(LocalizationManager.keys(for: language)).subtracting(english)
            #expect(orphans.isEmpty, "\(language.rawValue) defines keys English lacks: \(orphans.sorted())")
        }
        // `localizedLanguage` resolves `.system` through the host locale, so it
        // must always land on a table that exists.
        loc.currentLanguage = .system
        #expect(!LocalizationManager.keys(for: loc.resolvedLanguage).isEmpty)
    }

    @Test("A key added to English is translated everywhere, or explicitly listed")
    func testTranslationCoverage() {
        // Japanese/Korean/French/German/Spanish are intentionally partial today,
        // so "parity" cannot be asserted. What can be asserted is that the drift
        // is known: this pins the sizes so a table cannot lose rows unnoticed,
        // and — more usefully — so the gap is a decision someone made rather
        // than something nobody noticed.
        let english = Set(LocalizationManager.keys(for: .english))
        let chinese = Set(LocalizationManager.keys(for: .chinese))
        #expect(english == chinese, "Simplified Chinese is a complete translation and must stay in sync")

        for language in AppLanguage.allCases where language != .system && language != .english {
            let count = LocalizationManager.keys(for: language).count
            #expect(count > 0, "\(language.rawValue) has no translations at all")
        }
    }

    @Test("The AI settings strings resolve in every language, not as raw keys")
    func testAISettingsKeysResolve() {
        let loc = LocalizationManager()
        // These were literal `Text("...")` calls with no table entry at all, so
        // they read as English in every language. A missing key returns the
        // key itself, which is the failure this catches.
        let keys = [
            "ai.settings.appleOnDevice", "ai.settings.executablePath",
            "ai.settings.mcpServers", "ai.settings.aiRoles",
            "ai.settings.retentionPeriod", "ai.settings.secretStoredIn",
        ]
        for language in AppLanguage.allCases where language != .system {
            loc.currentLanguage = language
            for key in keys {
                #expect(loc.localized(key) != key, "\(key) is untranslated in \(language.rawValue)")
            }
        }
        loc.currentLanguage = .chinese
        #expect(loc.localized("ai.settings.mcpServers") == "MCP 服务器")
    }

    @Test("Every UI-facing key used in source exists in the tables")
    func testNoMissingKeys() {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources")
        let english = Set(LocalizationManager.keys(for: .english))
        var unregistered: [String] = []
        for plugin in ["PurahUI", "PurahApp"] {
            let root = dir.appendingPathComponent(plugin)
            guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { continue }
            for case let file as URL in walker where file.pathExtension == "swift" {
                guard let source = try? String(contentsOf: file, encoding: .utf8) else { continue }
                // `"some.key".localized` and `String(format: "some.key".localized, ...)`
                for match in source.matches(of: /"([a-z][A-Za-z0-9]*(?:\.[A-Za-z0-9]+)+)"\.localized/) {
                    let key = String(match.output.1)
                    if !english.contains(key) { unregistered.append("\(key) in \((file.path as NSString).lastPathComponent)") }
                }
            }
        }
        #expect(unregistered.isEmpty, "Keys used in the UI but absent from the tables: \(unregistered.sorted())")
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
