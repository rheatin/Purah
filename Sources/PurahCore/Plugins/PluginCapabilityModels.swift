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
    public let isDestructive: Bool
    public let action: @MainActor @Sendable () -> Void

    public init(
        id: String = UUID().uuidString,
        title: String,
        systemImage: String? = nil,
        isDestructive: Bool = false,
        action: @escaping @MainActor @Sendable () -> Void
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.isDestructive = isDestructive
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
    /// The number a gauge chip prints at its trailing edge. A ratio alone is
    /// not a reading: 55% of a disk and 2 KB/s of network are both "the
    /// metric", but only one of them can be computed from the ratio. Optional
    /// so a plugin that has nothing better to say still gets the percentage.
    public var gaugeValue: String?
    /// Opt in to the row-fill presentation: hairline rows inside the pod's
    /// card, with the ratio drawn as the row's background. A gauge chip that
    /// does not ask for it keeps its icon-block row.
    public var showsRowFill: Bool
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
        gaugeValue: String? = nil,
        showsRowFill: Bool = false,
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
        self.gaugeValue = gaugeValue
        self.showsRowFill = showsRowFill
        self.tintColorHex = tintColorHex
        self.isPinned = isPinned
    }
}

public extension PurahPluginSubItem {
    /// Canonical id for a pod's smart-fold "+N more" chip ("calendar_more_events",
    /// "todo_more_items", ...). Legacy spellings all contain "_more_".
    static func moreItemsID(forPod podId: String) -> String { "\(podId)_more_items" }

    static func isMoreItemsID(_ id: String) -> Bool { id.contains("_more_") }

    /// The smart-fold "+N" chip whose activation merges its pod: while this chip
    /// is hovered-open or pinned, the pod collapses its other chips into one
    /// full-span overview slot so the drawer can be exactly pod-height.
    /// Returns nil when no more-chip exists or it is not currently active.
    static func mergedOverviewChip(
        in items: [PurahPluginSubItem],
        activeDrawerItemId: String?,
        isItemPinned: (String) -> Bool
    ) -> PurahPluginSubItem? {
        guard let chip = items.first(where: { isMoreItemsID($0.id) }) else { return nil }
        let isActive = (activeDrawerItemId == chip.id) || isItemPinned(chip.id)
        return isActive ? chip : nil
    }
}
