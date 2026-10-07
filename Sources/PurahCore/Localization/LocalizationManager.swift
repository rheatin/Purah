// Sources/PurahCore/Localization/LocalizationManager.swift
import Foundation
import Observation

public enum AppLanguage: String, Codable, Sendable, CaseIterable, Identifiable {
    case system
    case english = "en"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system: return "System Default"
        case .english: return "English"
        }
    }
}

@Observable
@MainActor
public final class LocalizationManager {
    public static let shared = LocalizationManager()

    public var currentLanguage: AppLanguage = .system

    public init() {}

    public var resolvedLanguage: AppLanguage {
        if currentLanguage != .system {
            return currentLanguage
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

    private let tables: [AppLanguage: [String: String]] = [
        .english: [
            "app.name": "Purah Pad",
            "app.tagline": "macOS Magnetic Edge Rails & Ergonomic Assembly Kernel",
            "menu.openSimulator": "Open Layout Simulator...",
            "menu.autoLayout": "Magic Ergonomics Auto-Layout",
            "menu.checkUpdates": "Check for Updates...",
            "menu.quit": "Quit Purah",

            // Zones
            "zone.glance": "Glance Zone (0% ~ 20%)",
            "zone.goldenAction": "Golden Action Zone (20% ~ 75%)",
            "zone.quickFlick": "Quick Flick Zone (75% ~ 100%)",

            // Pods
            "pod.calendar": "Calendar Timeline",
            "pod.todo": "Quick Todos",
            "pod.music": "Music Waves",
            "pod.shelf": "Drop Shelf",
            "pod.notes": "Quick Scratchpad",

            // Presets
            "preset.balanced.title": "Balanced Ergonomics",
            "preset.balanced.desc": "Evenly split between left & right rails. Timeline on right, shelf & notes on left, music on bottom.",
            "preset.sprint.title": "Sprint Productivity",
            "preset.sprint.desc": "Left rail dedicated to drop shelf & notes. Right rail focused on timeline & todo lists.",
            "preset.media.title": "Immersive Multimedia",
            "preset.media.desc": "Audio wave meter on left, minimal glance calendar on right.",

            // Actions & UI
            "simulator.title": "Purah Edge Rail Layout Simulator",
            "simulator.subtitle": "Bilateral Magnetic Rails · Ergonomic Auto-Fitting & Spring Collision Avoidance",
            "simulator.magicButton": "Magic Ergonomics",
            "simulator.presets": "Ergonomic Presets",
            "updater.title": "Software Update",
            "updater.upToDate": "You are up to date! Purah Pad is currently on the latest version.",
            "updater.newVersion": "A new version of Purah Pad is available!",
            "updater.button.update": "Update Now",
            "updater.button.later": "Later",
            "updater.button.check": "Check for Updates"
        ]
    ]
}

public extension String {
    @MainActor
    var localized: String {
        LocalizationManager.shared.localized(self)
    }
}
