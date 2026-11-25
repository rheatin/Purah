// Sources/PurahCore/Models/AppThemeStyle.swift
import Foundation

public enum AppThemeStyle: String, Codable, Sendable, CaseIterable, Identifiable {
    case native = "native"

    public var id: String { rawValue }

    public var displayName: String {
        "macOS Liquid Native"
    }
}

public enum AppAppearanceMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case system = "system"
    case dark = "dark"
    case light = "light"

    public var id: String { rawValue }

    public var localizationKey: String {
        switch self {
        case .system: return "general.appearance.system"
        case .dark: return "general.appearance.dark"
        case .light: return "general.appearance.light"
        }
    }

    public var systemIcon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .dark: return "moon.fill"
        case .light: return "sun.max.fill"
        }
    }
}
