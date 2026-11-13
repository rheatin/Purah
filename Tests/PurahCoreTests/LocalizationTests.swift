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
        let savedLanguage = LocalizationManager.shared.currentLanguage
        defer { LocalizationManager.shared.currentLanguage = savedLanguage }

        loc.currentLanguage = .english
        #expect(loc.localized("notes.tips.table") == "Table")

        loc.currentLanguage = .chinese
        #expect(loc.localized("notes.tips.table") == "表格")

        loc.currentLanguage = .traditionalChinese
        #expect(loc.localized("notes.tips.table") == "表格")
    }

    @Test("Every language table is a subset of English, never a superset")
    func testNoOrphanTranslations() {
        let loc = LocalizationManager()
        let savedLanguage = LocalizationManager.shared.currentLanguage
        defer { LocalizationManager.shared.currentLanguage = savedLanguage }
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
        // Simplified Chinese is a complete translation and must stay at parity.
        let english = Set(LocalizationManager.keys(for: .english))
        let chinese = Set(LocalizationManager.keys(for: .chinese))
        #expect(english == chinese, "Simplified Chinese is a complete translation and must stay in sync")

        // The remaining languages are intentionally partial, so parity cannot
        // be asserted — but the *size* of each gap is a decision, not an
        // accident. Pin it: a table that silently loses rows (a bad merge, a
        // truncated edit) fails here instead of quietly falling back to English
        // for the missing strings. Raise a number when you add translations;
        // never lower one to make this pass.
        let pinnedCoverage: [AppLanguage: Int] = [
            // 556 - 11: the miniature screen simulator was deleted, taking its
            // seven strings (zone labels, menu-bar mock, sample clock, and the
            // four drag hints its capsules carried) with it; the "always
            // compact idle strips" toggle went with the breathing rewrite; and
            // the two "left/right rail page" labels moved into the module
            // assembly card's page tabs, which need no prose.
            //
            // -46: 108 keys no code, test or run-time interpolation asks for
            // were removed from every table (`layout.presets.*`,
            // `overflow.mode.*`, `notes.folder.*`, `ai.welcome.*`,
            // `clipboard.quota.*`, and the rest of the dead families). The
            // English vocabulary shrank, so a partial translation loses rows in
            // proportion to how much of it it covered.
            // -2: the finished-command strings went with the terminal's rail
            // dot. The notification is the host's pod glow, which names no
            // command, so nothing asks for `terminal.done.*` any more.
            // +2: the onboarding guide now asks before it replaces the layout.
            // +1: the vitals sparkline names its click-to-cycle hint.
            // +8: Traditional Chinese now covers the alert style titles and subtitles.
            // +8: the calendar's Up-Next countdown and Open in Calendar strings.
            // +11: the compact alert card, its channel names, captions and pod suffixes.
            // The partial table below gains those 11 keys plus the three alert style titles.
            // +6: Drop Shelf's Link, Move, undo banner, and failure copy.
            // +1: the shelf's refused-delete warning.
            // +3: the shelf's zone hints; the partial tables also gained the
            // AirDrop title they had been falling back to English for.
            // +4: the Alerts card's per-pod edge style and the calendar's
            // Advance Notice card; -2: the calendar's own toast style and HUD
            // copy, which the Alerts card replaced.
            // +19: the storage inspector now names its three buckets, the
            // clipboard and vitals stores, leftover folders, every destructive
            // consequence, the assets caption, and their actions.
            // +3: the settings rail labels its pod and Purah groups and names
            // the System page.
            // +6: the pod settings page points to Alerts and Storage.
            // +9: Notifications gain their default and per-pod sound controls,
            // and the sound menu now covers all 14 system sounds.
            // +6: the System page gains its subtitle, runtime, disk and store-count copy.
            // +2: the settings rail renames Plugins to Market and adds its subtitle;
            // -1: the deleted plugin sidebar's registered-count line.
            // +3: Quick Notes names its untagged folder and per-tag actions.
            // +3: the System page states what each rail percentage means next.
            // -1: the orphaned plugin-selection hint left with the old sidebar.
            // +23: the Compute, Net/Disk and Power tabs share one sheet
            // grammar, adding their headers, footer sentences and core
            // accessibility labels.
            // +6: the Compute RAM footer drops its "/ total" half when the
            // machine has no swap, and the CPU legend names the thermal state.
            // +3: memory pressure reads in the reader's language too.
            // +9: the Power tab gains its flow and capacity band titles,
            // adapter/system/battery labels, INPUT and DESIGN formats.
            // +1: the CAPACITY legend word for DESIGN, distinct from its
            // format string.
            // +3: the POWER FLOW strip captions under adapter, system and
            // battery.
            // +2: the column footer's "now" and "available %@" span labels.
            // +3: the sampling-interval title, honest caption and seconds label.
            // +285: the table is finished. Every English key now has a
            // Traditional Chinese row, so the pin equals the English table and
            // the only way to fail it is to delete translations.
            // +1: the step-7 caption for a thin build.
            // +4: the spotlight coach bubbles; -1: the retired dock drag hint.
            // +2: the Music drawer's empty-transport state and its button.
            // -6: the page-demo step retired; +1: the mount step's recommended
            // layout shortcut.
            // +2: the onboarding focus frame's Click here / Drag it here.
            // +1: "Hover here" for the two hover targets.
            // -11: the six-step taxonomy (breathing, gate drill, old mount and
            // permission titles) retired with the five task steps.
            // +10: Vitals gains its fan, Wi-Fi and overview machine-facts
            // labels; +1 for the channel label.
            // +1: the DISK band's size-free "boot disk" label.
            // +13: the rail callouts the sculptor strip draws during the guide
            // (decompose prompt and toggle, stack source/target/success badges,
            // page hints, empty-rail hint and dock drag hint). They had been
            // referenced by the strip under new key names while only the retired
            // legacy spellings existed, so the rail showed the raw key.
            // +1: music.activatePlayer
            .traditionalChinese: 1029
        ]

        for (language, expected) in pinnedCoverage {
            let actual = LocalizationManager.keys(for: language).count
            #expect(
                actual == expected,
                """
                \(language.rawValue) has \(actual) keys, expected \(expected). \
                If you added translations, update the pin. If they went missing, \
                that is the regression this test exists to catch.
                """
            )
            #expect(
                actual <= english.count,
                "\(language.rawValue) defines keys English lacks — see testNoOrphanTranslations"
            )
        }
    }

    @Test("The AI settings strings resolve in every language, not as raw keys")
    func testAISettingsKeysResolve() {
        let loc = LocalizationManager()
        let savedLanguage = LocalizationManager.shared.currentLanguage
        defer { LocalizationManager.shared.currentLanguage = savedLanguage }
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

    @Test("Every alert-card string is translated in every supported language")
    func testAlertCardLocalization() {
        let keys = [
            "interaction.alerts.card",
            "interaction.alerts.master.title",
            "interaction.alerts.ways.title",
            "interaction.alerts.followEachPod",
            "interaction.alerts.channel.railEffect",
            "interaction.alerts.channel.toast",
            "interaction.alerts.channel.sound",
            "interaction.alerts.sound.title",
            "interaction.alerts.pods.sound.follow",
            "interaction.alerts.channels.none.caption",
            "interaction.alerts.pods.caption",
            "interaction.alerts.pods.detail.edgeOnly",
            "interaction.alerts.pods.detail.silent",
            "alert.style.breathingBeacon",
            "alert.style.sonarWave",
            "alert.style.subtleGlow",
        ]

        for language in AppLanguage.allCases where language != .system {
            let table = Set(LocalizationManager.keys(for: language))
            let missing = Set(keys).subtracting(table)
            #expect(missing.isEmpty, "\(language.rawValue) is missing alert strings: \(missing.sorted())")
        }

        let loc = LocalizationManager()
        let savedLanguage = LocalizationManager.shared.currentLanguage
        defer { LocalizationManager.shared.currentLanguage = savedLanguage }
        for language in AppLanguage.allCases where language != .system {
            loc.currentLanguage = language
            for key in keys {
                #expect(!loc.localized(key).contains("!"), "\(key) uses an exclamation mark in \(language.rawValue)")
            }
        }
    }

    @Test("The Freeze Rails menu item and HUD read Chinese in Chinese")
    func testFreezeStringsLocalized() {
        // Both were hardcoded English in AppDelegate and TransientHUDController,
        // so clicking the menu bar item answered in English under every
        // language. Pinning the Chinese values catches the other failure too: a
        // mistyped key falls back to English and looks identical to the bug.
        let loc = LocalizationManager()
        let saved = loc.currentLanguage
        defer { loc.currentLanguage = saved }

        let keys = ["menu.freezeRails", "menu.unfreezeRails", "hud.railsFrozen", "hud.railsActive"]
        for key in keys {
            #expect(loc.localized(key) != key, "\(key) is missing from the English table")
        }

        loc.currentLanguage = .chinese
        #expect(loc.localized("menu.freezeRails") == "冻结边缘轨")
        #expect(loc.localized("menu.unfreezeRails") == "解冻边缘轨")
        for key in keys {
            #expect(loc.localized(key) != EnglishFor(key), "\(key) still reads as English in zh-Hans")
        }
    }

    /// The English text for a key, for comparing across languages.
    private func EnglishFor(_ key: String) -> String {
        let loc = LocalizationManager()
        loc.currentLanguage = .english
        return loc.localized(key)
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

    @Test("`String(format:)` never doubles an integer with %@")
    func testNoObjectSpecifierForInteger() {
        // `String(format:)` hands `%@` to `objc_opt_respondsToSelector`, so a
        // Swift `Int` arrives as a raw pointer. `clipboard.imageMeta` read
        // "... %@ KB" while the caller passed `bytes / 1024`; rendering an
        // image item in the Clipboard drawer then dereferenced address 0x23
        // and killed the process (SIGSEGV, EXC_BAD_ACCESS).
        //
        // The specifier count matched the argument count, which is why the
        // other checks were happy — only the *type* was wrong. `%d` for
        // integers, `%@` for anything that would bridge to NSString.
        //
        // Arguments are located by walking bracket depth rather than with a
        // regex: `max(bytes / 1024, 1)` nests commas, and a `[^)]*` capture
        // stops at the inner paren and shifts every later argument by one.
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources")
        let manager = LocalizationManager.shared
        var offenders: [String] = []
        var scanned = 0

        for plugin in ["PurahUI", "PurahApp"] {
            let root = dir.appendingPathComponent(plugin)
            guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { continue }
            for case let file as URL in walker where file.pathExtension == "swift" {
                guard let source = try? String(contentsOf: file, encoding: .utf8) else { continue }
                for call in source.matches(of: /String\(format:\s*"([A-Za-z][\w.]+)"\.localized\s*,/) {
                    let key = String(call.output.1)
                    let format = manager.localized(key)
                    // Note: `#/%(?:%@|%d)/#` silently matches nothing in Swift's Regex,
                    // while the same alternation written as `#/%(?:d|@)/#` works.
                    // Matching the specifier letter as a character class sidesteps
                    // that without needing to explain it at the call site.
                    let specs = format.matches(of: #/%(?:@|[dfsluiu])/#).map { String($0.output) }
                    guard specs.contains("%@") else { continue }
                    scanned += 1

                    let rest = source[call.range.upperBound...]
                    for (index, arg) in Self.splitTopLevelArguments(rest).enumerated() {
                        guard index < specs.count, specs[index] == "%@" else { continue }
                        let a = arg.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard Self.looksNumeric(a) else { continue }
                        offenders.append("\(key) ← \(a)  [\(file.lastPathComponent)]")
                    }
                }
            }
        }
        #expect(scanned > 0, "Scanner found no %@ call sites — the pattern has drifted")
        #expect(offenders.isEmpty, "Integer fed to %@: \(offenders.sorted())")
    }


    /// True only for expressions that obviously yield a number.
    ///
    /// Deliberately conservative: `pod.name`, `snippet`, `error` and the rest of
    /// the sixty-odd identifiers passed to `%@` are all Strings and all correct.
    /// Flagging bare identifiers would produce a wall of false positives that
    /// trains everyone to ignore the test. The crash came from arithmetic and
    /// integer narrowing, so that is what is matched.
    static func looksNumeric(_ arg: String) -> Bool {
        if arg.hasPrefix("\\(") || arg.contains("\"") || arg.hasPrefix("String(") { return false }
        let numericCalls = ["max(", "min(", "abs(", "Int(", "UInt(", "Double(", "Float(", "CGFloat("]
        if numericCalls.contains(where: { arg.hasPrefix($0) }) { return true }
        if arg.contains(".count") || arg.contains(".rawValue") || arg.contains(".pageIndex") { return true }
        // Bare arithmetic: `bytes / 1024`, `a + b`, `x * 2`.
        if arg.range(of: #"[A-Za-z0-9_.)]\s*[-+*/]\s*[A-Za-z0-9_(]"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    /// Splits `a, b, f(x, y))` into `["a", "b", "f(x, y)"]`, stopping at the
    /// paren that closes the enclosing call.
    static func splitTopLevelArguments(_ text: Substring) -> [String] {
        var args: [String] = []
        var depth = 0
        var current = ""
        for ch in text {
            switch ch {
            case "(", "[", "{":
                depth += 1
                current.append(ch)
            case ")", "]", "}":
                if depth == 0 { args.append(current); return args.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }
                depth -= 1
                current.append(ch)
            case "," where depth == 0:
                args.append(current)
                current = ""
            case "\n" where depth == 0:
                args.append(current)
                return args.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            default:
                current.append(ch)
            }
        }
        args.append(current)
        return args.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    @Test("LocalizationManager persists currentLanguage to UserDefaults")
    @MainActor
    func testLanguagePersistence() {
        let previous = LocalizationManager.shared.currentLanguage
        defer {
            LocalizationManager.shared.currentLanguage = previous
        }

        LocalizationManager.shared.currentLanguage = .traditionalChinese
        #expect(UserDefaults.standard.string(forKey: "purah.appLanguage") == "zh-Hant")

        let freshManager = LocalizationManager()
        #expect(freshManager.currentLanguage == .traditionalChinese)

        // A value from a removed language (or garbage) resolves to `.system`
        // and is written back, so the picker shows "System Default" rather
        // than a value the enum can no longer represent.
        for removed in ["ja", "fr", "not-a-language"] {
            UserDefaults.standard.set(removed, forKey: "purah.appLanguage")
            let manager = LocalizationManager()
            #expect(manager.currentLanguage == .system)
            #expect(UserDefaults.standard.string(forKey: "purah.appLanguage") == "system")
            #expect(LocalizationManager().currentLanguage == .system)
        }
    }

    @Test("Every offered language meets the picker's coverage contract")
    @MainActor
    func testOfferedLanguageCoverage() {
        let english = Set(LocalizationManager.keys(for: .english))
        #expect(!english.isEmpty)

        for language in AppLanguage.allCases where language != .system {
            let keys = Set(LocalizationManager.keys(for: language))
            #expect(!keys.isEmpty, "\(language.rawValue) is offered with no table")
            let orphans = keys.subtracting(english)
            #expect(
                orphans.isEmpty,
                "\(language.rawValue) defines keys English lacks: \(orphans.sorted())"
            )
        }

        for complete in [AppLanguage.english, .chinese] {
            let missing = english.subtracting(Set(LocalizationManager.keys(for: complete)))
            #expect(
                missing.isEmpty,
                """
                \(complete.rawValue) is missing \(missing.count) keys; \
                first ten: \(missing.sorted().prefix(10))
                """
            )
        }

        // Traditional Chinese is finished, so the contract it has to meet is
        // the same one English and Simplified Chinese meet: nothing missing.
        let traditional = Set(LocalizationManager.keys(for: .traditionalChinese))
        let missing = english.subtracting(traditional)
        #expect(
            missing.isEmpty,
            """
            zh-Hant covers \(traditional.count)/\(english.count), \
            missing \(missing.count) keys; \
            first ten: \(missing.sorted().prefix(10))
            """
        )
    }
}
