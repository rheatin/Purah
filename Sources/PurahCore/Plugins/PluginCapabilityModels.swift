// Sources/PurahCore/Plugins/PluginCapabilityModels.swift
import Foundation
import UniformTypeIdentifiers

public enum PurahDrawerMode: String, Codable, Sendable, CaseIterable {
    case composite // Single full-height composite drawer (Music, Shelf, Notes)
    case stepped   // Decomposed stepped sub-item chips (Todo, Calendar, Vitals, Scripts)
}

public enum RailItemActivityState: String, Codable, Sendable {
    case normal    // Standard active state (100% opacity)
    case ongoing   // Currently in progress / active session (glowing pulse)
    case alerting  // Thermal pressure, overdue, low battery (alert pulse)
    case inactive  // Completed, expired, past (dimmed 0.35 opacity)
    case running   // Actively executing background task / animation
}

public enum RailGaugeStyle: String, Codable, Sendable {
    case solid      // Solid vertical fill level
    case segmented  // Segmented steps
    case wave       // Dynamic wave level meter
    case none       // Plain bar with no level gauge
}

public enum PurahHapticType: Sendable {
    case alignment
    case levelChange
    case generic
}

public struct PurahMenuAction: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let systemImage: String?
    public let action: @MainActor @Sendable () -> Void

    public init(
        id: String = UUID().uuidString,
        title: String,
        systemImage: String? = nil,
        action: @escaping @MainActor @Sendable () -> Void
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }
}

public struct PurahPluginSubItem: Identifiable, Sendable {
    public let id: String
    public var title: String
    public var subtitle: String?
    public var systemIcon: String
    public var badge: String?
    public var state: RailItemActivityState
    public var gaugeRatio: Double?
    public var gaugeStyle: RailGaugeStyle
    public var tintColorHex: String?
    public var isPinned: Bool

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        systemIcon: String,
        badge: String? = nil,
        state: RailItemActivityState = .normal,
        gaugeRatio: Double? = nil,
        gaugeStyle: RailGaugeStyle = .none,
        tintColorHex: String? = nil,
        isPinned: Bool = false
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.systemIcon = systemIcon
        self.badge = badge
        self.state = state
        self.gaugeRatio = gaugeRatio
        self.gaugeStyle = gaugeStyle
        self.tintColorHex = tintColorHex
        self.isPinned = isPinned
    }
}
