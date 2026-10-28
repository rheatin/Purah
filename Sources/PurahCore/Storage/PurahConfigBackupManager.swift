// Sources/PurahCore/Storage/PurahConfigBackupManager.swift
import Foundation
import CoreGraphics

public enum PurahConfigValue: Codable, Equatable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case stringArray([String])
    case dataBase64(String)

    private enum CodingKeys: String, CodingKey {
        case type
        case value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "string":
            self = .string(try container.decode(String.self, forKey: .value))
        case "int":
            self = .int(try container.decode(Int.self, forKey: .value))
        case "double":
            self = .double(try container.decode(Double.self, forKey: .value))
        case "bool":
            self = .bool(try container.decode(Bool.self, forKey: .value))
        case "stringArray":
            self = .stringArray(try container.decode([String].self, forKey: .value))
        case "dataBase64":
            self = .dataBase64(try container.decode(String.self, forKey: .value))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown config value type: \(type)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .string(let val):
            try container.encode("string", forKey: .type)
            try container.encode(val, forKey: .value)
        case .int(let val):
            try container.encode("int", forKey: .type)
            try container.encode(val, forKey: .value)
        case .double(let val):
            try container.encode("double", forKey: .type)
            try container.encode(val, forKey: .value)
        case .bool(let val):
            try container.encode("bool", forKey: .type)
            try container.encode(val, forKey: .value)
        case .stringArray(let val):
            try container.encode("stringArray", forKey: .type)
            try container.encode(val, forKey: .value)
        case .dataBase64(let val):
            try container.encode("dataBase64", forKey: .type)
            try container.encode(val, forKey: .value)
        }
    }
}

public struct PurahConfigurationBackup: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var appVersion: String
    public var exportedAt: Date
    public var settings: [String: PurahConfigValue]

    public init(
        schemaVersion: Int = 1,
        appVersion: String = "0.2.0",
        exportedAt: Date = Date(),
        settings: [String: PurahConfigValue] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.appVersion = appVersion
        self.exportedAt = exportedAt
        self.settings = settings
    }
}

@MainActor
public enum PurahConfigBackupManager {
    /// Current backup schema. Older files remain importable; newer ones are
    /// rejected rather than partially applied.
    public static let currentSchemaVersion = 2
    /// Bound on how many settings an import may carry, so a hostile file cannot
    /// flood `UserDefaults` or stall the main thread.
    public static let maximumImportedSettings = 5_000

    public static func exportBackupData(
        from store: PurahWorkspaceStore,
        defaults: UserDefaults = .standard,
        includeSecrets: Bool = false
    ) throws -> Data {
        store.savePersistentState()

        var settings: [String: PurahConfigValue] = [:]
        let dict = defaults.dictionaryRepresentation()

        for (key, rawValue) in dict where key.hasPrefix("purah.") {
            if key.hasSuffix(".transient") || key.hasSuffix(".lock") {
                continue
            }
            // Credentials live in the keychain and must never travel in a plain
            // JSON file the user may drop into git, a ticket or a shared disk.
            if !includeSecrets && PurahSecretKeys.isSecret(key) {
                continue
            }
            if let configVal = convertToConfigValue(rawValue) {
                settings[key] = configVal
            }
        }

        let backup = PurahConfigurationBackup(
            schemaVersion: currentSchemaVersion,
            appVersion: PurahCore.version,
            exportedAt: Date(),
            settings: settings
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(backup)
    }

    public enum ImportError: LocalizedError {
        case unsupportedSchema(Int)
        case tooManySettings(Int)
        case rejectedKeys([String])

        public var errorDescription: String? {
            switch self {
            case .unsupportedSchema(let version):
                return "This backup was written by a newer version of Purah (schema \(version)). Update Purah and try again."
            case .tooManySettings(let count):
                return "This backup contains \(count) settings, which exceeds the supported limit."
            case .rejectedKeys(let keys):
                return "This backup contains unsupported settings: \(keys.prefix(5).joined(separator: ", "))"
            }
        }
    }

    public static func importBackupData(
        _ data: Data,
        into store: PurahWorkspaceStore,
        defaults: UserDefaults = .standard,
        allowSecrets: Bool = false
    ) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(PurahConfigurationBackup.self, from: data)

        guard backup.schemaVersion <= currentSchemaVersion else {
            throw ImportError.unsupportedSchema(backup.schemaVersion)
        }
        guard backup.settings.count <= maximumImportedSettings else {
            throw ImportError.tooManySettings(backup.settings.count)
        }

        // Only Purah's own namespaced keys, and never credentials: without this
        // an attacker-supplied file could rewrite `openAIBaseURL` / API keys or
        // inject arbitrary defaults domains.
        let accepted = backup.settings.keys.filter { key in
            key.hasPrefix("purah.")
                && !key.hasSuffix(".transient")
                && !key.hasSuffix(".lock")
                && (allowSecrets || !PurahSecretKeys.isSecret(key))
        }
        let rejected = backup.settings.keys.filter { !accepted.contains($0) }

        for key in accepted {
            guard let configValue = backup.settings[key] else { continue }
            switch configValue {
            case .string(let str):
                defaults.set(str, forKey: key)
            case .int(let intVal):
                defaults.set(intVal, forKey: key)
            case .double(let dbl):
                defaults.set(dbl, forKey: key)
            case .bool(let boolVal):
                defaults.set(boolVal, forKey: key)
            case .stringArray(let arr):
                defaults.set(arr, forKey: key)
            case .dataBase64(let base64Str):
                if let rawData = Data(base64Encoded: base64Str) {
                    if let plist = try? PropertyListSerialization.propertyList(from: rawData, options: [], format: nil),
                       plist is [String: Any] || plist is [Any] {
                        defaults.set(plist, forKey: key)
                    } else {
                        defaults.set(rawData, forKey: key)
                    }
                }
            }
        }

        store.loadPersistentState()

        if let langStr = defaults.string(forKey: "purah.appLanguage"),
           let lang = AppLanguage(rawValue: langStr) {
            LocalizationManager.shared.currentLanguage = lang
        }

        store.invalidateLayoutCache()
        store.onWindowsRebuildNeeded?()

        if !rejected.isEmpty {
            DiagnosticLogger.shared.warn(
                "Backup",
                "Ignored \(rejected.count) unsupported setting(s) while importing: \(rejected.sorted().prefix(10).joined(separator: ", "))"
            )
        }
    }

    public static func resetToFactoryDefaults(store: PurahWorkspaceStore, defaults: UserDefaults = .standard, triggerOnboarding: Bool = false) {
        let dict = defaults.dictionaryRepresentation()
        for key in dict.keys where key.hasPrefix("purah.") {
            defaults.removeObject(forKey: key)
        }

        defaults.set(true, forKey: "purah.didAutoInstallAIPlugin")
        store.pods = PurahWorkspaceStore.defaultPods()
        store.railBarWidth = 8.0
        store.fixedDrawerWidth = 290.0
        store.drawerWidthMode = .adaptive
        store.isDynamicBreathingEnabled = true
        store.hotKeyShortcut = .defaultShortcut
        store.sculptorHotKeyShortcut = .defaultSculptorShortcut
        store.edgeTriggerMode = .hoverDwell
        store.edgeTriggerSensitivity = .balanced
        store.customPodColors = [:]
        store.leftRailPage = 0
        store.rightRailPage = 0
        store.pinnedDrawerItemIds.removeAll()
        store.dismissActiveDrawer()

        store.savePersistentState()
        store.invalidateLayoutCache()
        store.onWindowsRebuildNeeded?()

        if triggerOnboarding {
            store.startInteractiveOnboarding(clearAllPods: true)
        }
    }

    private static func convertToConfigValue(_ value: Any) -> PurahConfigValue? {
        if let num = value as? NSNumber {
            if CFGetTypeID(num) == CFBooleanGetTypeID() {
                return .bool(num.boolValue)
            } else if CFNumberIsFloatType(num as CFNumber) {
                return .double(num.doubleValue)
            } else {
                return .int(num.intValue)
            }
        } else if let str = value as? String {
            return .string(str)
        } else if let arr = value as? [String] {
            return .stringArray(arr)
        } else if let data = value as? Data {
            return .dataBase64(data.base64EncodedString())
        } else if let dict = value as? [String: Any] {
            if let data = try? PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0) {
                return .dataBase64(data.base64EncodedString())
            }
        } else if let arr = value as? [Any] {
            if let data = try? PropertyListSerialization.data(fromPropertyList: arr, format: .binary, options: 0) {
                return .dataBase64(data.base64EncodedString())
            }
        }
        return nil
    }
}
