// Sources/PurahCore/Localization/LocalizationManager.swift
import Foundation
import Observation

public enum AppLanguage: String, Codable, Sendable, CaseIterable, Identifiable {
    case system
    case english = "en"
    case chinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system: return "System Default"
        case .english: return "English"
        case .chinese: return "简体中文"
        case .traditionalChinese: return "繁體中文"
        }
    }
}

/// Namespace populated by per-locale table files (`LocalizationTable+*.swift`)
/// so translation edits stay scoped to one locale file instead of colliding
/// inside a single 3,400-line monolith.
enum LocalizationTables {
    static var all: [AppLanguage: [String: String]] {
        [
            .english: english,
            .chinese: chinese,
            .traditionalChinese: traditionalChinese,
        ]
    }
}

@Observable
@MainActor
public final class LocalizationManager {
    public static let shared = LocalizationManager()

    private static let languageDefaultsKey = "purah.appLanguage"
    private let userDefaults: UserDefaults

    public var currentLanguage: AppLanguage = .system {
        didSet {
            userDefaults.set(currentLanguage.rawValue, forKey: Self.languageDefaultsKey)
        }
    }

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if let saved = userDefaults.string(forKey: Self.languageDefaultsKey),
           let lang = AppLanguage(rawValue: saved) {
            self.currentLanguage = lang
        } else {
            // A removed language ("ja", "fr"…) or garbage must not survive as
            // a stored raw value the enum can no longer represent. Resolve it
            // to the system language and write that back so the picker has
            // nothing stale to show on the next launch.
            self.currentLanguage = .system
            userDefaults.set(AppLanguage.system.rawValue, forKey: Self.languageDefaultsKey)
        }
    }

    public var resolvedLanguage: AppLanguage {
        if currentLanguage != .system {
            return currentLanguage
        }
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? ""
        if preferred.hasPrefix("zh-hant") || preferred.hasPrefix("zh-tw") || preferred.hasPrefix("zh-hk") {
            return .traditionalChinese
        }
        if preferred.hasPrefix("zh") {
            return .chinese
        }
        return .english
    }

    public func localized(_ key: String) -> String {
        let lang = resolvedLanguage
        if let dict = tables[lang], let val = dict[key] {
            return val
        }
        if let enDict = tables[.english], let val = enDict[key] {
            return val
        }
        return key
    }

    /// Type-safe format helper for single-integer templates (`%d` / `%lld`),
    /// preventing `%@` vs integer format-specifier mismatches at call sites.
    public func formatted(_ key: String, int value: Int) -> String {
        String(format: localized(key), value)
    }

    /// Type-safe format helper for single-string templates (`%@`).
    public func formatted(_ key: String, string value: String) -> String {
        String(format: localized(key), value)
    }

    /// The keys defined in one table.
    ///
    /// Every table is allowed to be smaller than English — the fallback chain
    /// fills the gaps — but a key that exists *only* in a non-English table can
    /// never be reached. Exposing the key sets lets a test state that as a fact
    /// instead of hoping someone diffs 1,100 rows by eye.
    @MainActor
    public static func keys(for language: AppLanguage) -> [String] {
        Array((shared.tables[language] ?? [:]).keys)
    }

    private let tables: [AppLanguage: [String: String]] = LocalizationTables.all
}

public extension String {
    @MainActor
    var localized: String {
        LocalizationManager.shared.localized(self)
    }
}
