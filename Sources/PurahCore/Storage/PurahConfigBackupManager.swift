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
    public static func exportBackupData(from store: PurahWorkspaceStore, defaults: UserDefaults = .standard) throws -> Data {
        store.savePersistentState()
        defaults.synchronize()

        var settings: [String: PurahConfigValue] = [:]
        let dict = defaults.dictionaryRepresentation()

        for (key, rawValue) in dict where key.hasPrefix("purah.") {
            if key.hasSuffix(".transient") || key.hasSuffix(".lock") {
                continue
            }
            if let configVal = convertToConfigValue(rawValue) {
                settings[key] = configVal
            }
        }

        let backup = PurahConfigurationBackup(
            schemaVersion: 1,
            appVersion: "0.2.0",
            exportedAt: Date(),
            settings: settings
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(backup)
    }

    public static func importBackupData(_ data: Data, into store: PurahWorkspaceStore, defaults: UserDefaults = .standard) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(PurahConfigurationBackup.self, from: data)

        for (key, configValue) in backup.settings {
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

        defaults.synchronize()
        store.loadPersistentState()

        if let langStr = defaults.string(forKey: "purah.appLanguage"),
           let lang = AppLanguage(rawValue: langStr) {
            LocalizationManager.shared.currentLanguage = lang
        }

        store.invalidateLayoutCache()
        store.onWindowsRebuildNeeded?()
    }

    public static func resetToFactoryDefaults(store: PurahWorkspaceStore, defaults: UserDefaults = .standard) {
        let dict = defaults.dictionaryRepresentation()
        for key in dict.keys where key.hasPrefix("purah.") {
            defaults.removeObject(forKey: key)
        }

        defaults.set(true, forKey: "purah.didAutoInstallAIPlugin")
        store.pods = PurahWorkspaceStore.defaultPods()
        store.railBarWidth = 8.0
        store.fixedDrawerWidth = 290.0
        store.drawerWidthMode = .fixed
        store.isDynamicBreathingEnabled = true
        store.isAlwaysCompactBreathing = false
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
        defaults.synchronize()
        store.invalidateLayoutCache()
        store.onWindowsRebuildNeeded?()
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
