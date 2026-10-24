// Sources/PurahCore/Plugins/PurahPluginStorage.swift
import Foundation

public protocol PurahPluginStorage: Sendable {
    func string(forKey key: String) -> String?
    func set(_ value: String?, forKey key: String)
    func double(forKey key: String) -> Double
    func set(_ value: Double, forKey key: String)
    func bool(forKey key: String) -> Bool
    func set(_ value: Bool, forKey key: String)
    func int(forKey key: String) -> Int
    func set(_ value: Int, forKey key: String)
    func codable<T: Codable>(forKey key: String, as: T.Type) -> T?
    func setCodable<T: Codable>(_ value: T?, forKey key: String)
    func removeObject(forKey key: String)
}

public struct ScopedPluginStorage: PurahPluginStorage {
    public let pluginId: String
    nonisolated(unsafe) private let defaults: UserDefaults

    public init(pluginId: String, defaults: UserDefaults = .standard) {
        self.pluginId = pluginId
        self.defaults = defaults
    }

    private func fullKey(_ key: String) -> String {
        "purah.plugin.\(pluginId).\(key)"
    }

    public func string(forKey key: String) -> String? {
        defaults.string(forKey: fullKey(key))
    }

    public func set(_ value: String?, forKey key: String) {
        if let value {
            defaults.set(value, forKey: fullKey(key))
        } else {
            defaults.removeObject(forKey: fullKey(key))
        }
    }

    public func double(forKey key: String) -> Double {
        defaults.double(forKey: fullKey(key))
    }

    public func set(_ value: Double, forKey key: String) {
        defaults.set(value, forKey: fullKey(key))
    }

    public func bool(forKey key: String) -> Bool {
        defaults.bool(forKey: fullKey(key))
    }

    public func set(_ value: Bool, forKey key: String) {
        defaults.set(value, forKey: fullKey(key))
    }

    public func int(forKey key: String) -> Int {
        defaults.integer(forKey: fullKey(key))
    }

    public func set(_ value: Int, forKey key: String) {
        defaults.set(value, forKey: fullKey(key))
    }

    public func codable<T: Codable>(forKey key: String, as: T.Type) -> T? {
        guard let data = defaults.data(forKey: fullKey(key)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    public func setCodable<T: Codable>(_ value: T?, forKey key: String) {
        guard let value else {
            defaults.removeObject(forKey: fullKey(key))
            return
        }
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: fullKey(key))
        }
    }

    public func removeObject(forKey key: String) {
        defaults.removeObject(forKey: fullKey(key))
    }
}
