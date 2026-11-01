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
        case .breathingBeacon: return "Beacon Bar"
        case .sonarWave: return "Sonar Ripple"
        case .subtleGlow: return "Subtle Glow"
        case .off: return "Off"
        }
    }

    public var subtitle: String {
        switch self {
        case .breathingBeacon: return "A tinted pill shorter than the pod, double-flashing continuously"
        case .sonarWave: return "Three staggered pill ripples expanding from the rail"
        case .subtleGlow: return "A slow, soft bloom around the rail bar"
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
