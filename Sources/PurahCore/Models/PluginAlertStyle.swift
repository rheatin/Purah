// Sources/PurahCore/Models/PluginAlertStyle.swift
import Foundation

public enum PluginAlertStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case breathingBeacon = "breathingBeacon"
    case sonarWave = "sonarWave"
    case subtleGlow = "subtleGlow"
    case off = "off"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .breathingBeacon: return "Breathing Beacon"
        case .sonarWave: return "Sonar Ripple"
        case .subtleGlow: return "Subtle Glow"
        case .off: return "Off"
        }
    }

    public var subtitle: String {
        switch self {
        case .breathingBeacon: return "Physical 18pt breathing extrusion with beacon dot"
        case .sonarWave: return "Outward expanding luminous sonar wave"
        case .subtleGlow: return "Classic optical shadow glow"
        case .off: return "Disable attention animations"
        }
    }

    @MainActor
    public var localizedDisplayName: String {
        switch self {
        case .breathingBeacon: return "alert.style.breathingBeacon".localized
        case .sonarWave: return "alert.style.sonarWave".localized
        case .subtleGlow: return "alert.style.subtleGlow".localized
        case .off: return "alert.style.off".localized
        }
    }

    @MainActor
    public var localizedSubtitle: String {
        switch self {
        case .breathingBeacon: return "alert.style.breathingBeacon.subtitle".localized
        case .sonarWave: return "alert.style.sonarWave.subtitle".localized
        case .subtleGlow: return "alert.style.subtleGlow.subtitle".localized
        case .off: return "alert.style.off.subtitle".localized
        }
    }
}
