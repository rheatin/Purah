// Sources/PurahUI/Plugins/PurahABISubItem.swift
import Foundation
import PurahCore

/// Wire representation of a stepped sub-item for C-ABI plugins.
///
/// `PurahPluginSubItem` lives in `PurahCore` and carries Swift enums; a plugin
/// compiled against its own copy of the SDK cannot see those types. This
/// mirrors the payload pattern the context already uses: the host owns the
/// schema, the plugin sends JSON, and every field except `id` and `title` has a
/// documented default so an older plugin keeps working as the schema grows.
public struct PurahABISubItem: Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var subtitle: String?
    public var systemIcon: String
    public var badge: String?
    public var state: String?
    public var gaugeRatio: Double?
    public var gaugeStyle: String?
    public var gaugeValue: String?
    public var showsRowFill: Bool
    public var tintColorHex: String?
    public var isPinned: Bool

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        systemIcon: String = "circle.fill",
        badge: String? = nil,
        state: String? = nil,
        gaugeRatio: Double? = nil,
        gaugeStyle: String? = nil,
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

    enum CodingKeys: String, CodingKey {
        case id, title, subtitle, systemIcon, badge, state
        case gaugeRatio, gaugeStyle, gaugeValue, showsRowFill, tintColorHex, isPinned
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
        systemIcon = try container.decodeIfPresent(String.self, forKey: .systemIcon) ?? "circle.fill"
        badge = try container.decodeIfPresent(String.self, forKey: .badge)
        state = try container.decodeIfPresent(String.self, forKey: .state)
        gaugeRatio = try container.decodeIfPresent(Double.self, forKey: .gaugeRatio)
        gaugeStyle = try container.decodeIfPresent(String.self, forKey: .gaugeStyle)
        gaugeValue = try container.decodeIfPresent(String.self, forKey: .gaugeValue)
        showsRowFill = try container.decodeIfPresent(Bool.self, forKey: .showsRowFill) ?? false
        tintColorHex = try container.decodeIfPresent(String.self, forKey: .tintColorHex)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
    }

    /// Converts to the host's model, tolerating unknown enum spellings by
    /// falling back to the neutral value. A plugin built against a newer SDK
    /// that adds a state must not make the whole rail fail to render.
    public func toSubItem() -> PurahPluginSubItem {
        PurahPluginSubItem(
            id: id,
            title: title,
            subtitle: subtitle,
            systemIcon: systemIcon,
            badge: badge,
            state: RailItemActivityState(rawValue: state ?? "") ?? .normal,
            gaugeRatio: gaugeRatio.map { min(max($0, 0.0), 1.0) },
            gaugeStyle: RailGaugeStyle(rawValue: gaugeStyle ?? "") ?? .none,
            gaugeValue: gaugeValue,
            showsRowFill: showsRowFill,
            tintColorHex: tintColorHex,
            isPinned: isPinned
        )
    }

    /// Decodes the JSON array a plugin returns from its stepped-items symbol.
    ///
    /// A malformed payload yields an empty list rather than throwing: the
    /// caller is a view body, and a broken plugin should degrade to "no chips"
    /// instead of taking the rail down.
    public static func decodeList(_ json: String) -> [PurahPluginSubItem] {
        guard let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([PurahABISubItem].self, from: data) else {
            DiagnosticLogger.shared.warn("Plugin", "Stepped items payload could not be decoded")
            return []
        }
        return decoded.map { $0.toSubItem() }
    }
}

/// Wire representation of a single segment in a composite gauge rail bar.
public struct PurahABIGaugeSegment: Codable, Sendable, Equatable {
    public var id: String
    public var ratio: Double
    public var colorHex: String?
    public var isAlerting: Bool?

    public init(
        id: String,
        ratio: Double,
        colorHex: String? = nil,
        isAlerting: Bool? = nil
    ) {
        self.id = id
        self.ratio = ratio
        self.colorHex = colorHex
        self.isAlerting = isAlerting
    }
}

/// Wire representation of a composite pod's rail bar state (`purahRailBarStateJSON`).
///
/// External plugins never draw arbitrary views on the 8pt edge rail. Instead,
/// they return this data descriptor and the host renders the physical rail pod.
public struct PurahABIRailBarState: Codable, Sendable, Equatable {
    /// `"solid"` (default) or `"gauge"` / `"segmented"`.
    public var style: String?
    public var colorHex: String?
    public var hasContent: Bool?
    public var isGradient: Bool?
    /// Single-segment fill ratio (`0.0 ... 1.0`) when `style == "gauge"`.
    public var ratio: Double?
    public var isAlerting: Bool?
    /// Multi-segment gauge fills when `style == "gauge"` or `"segmented"`.
    public var segments: [PurahABIGaugeSegment]?
    public var minimumVisibleFill: Double?
    public var accessibilityValueLabel: String?

    public init(
        style: String? = "solid",
        colorHex: String? = nil,
        hasContent: Bool? = true,
        isGradient: Bool? = false,
        ratio: Double? = nil,
        isAlerting: Bool? = nil,
        segments: [PurahABIGaugeSegment]? = nil,
        minimumVisibleFill: Double? = nil,
        accessibilityValueLabel: String? = nil
    ) {
        self.style = style
        self.colorHex = colorHex
        self.hasContent = hasContent
        self.isGradient = isGradient
        self.ratio = ratio
        self.isAlerting = isAlerting
        self.segments = segments
        self.minimumVisibleFill = minimumVisibleFill
        self.accessibilityValueLabel = accessibilityValueLabel
    }

    public static func decode(_ json: String) -> PurahABIRailBarState? {
        guard let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(PurahABIRailBarState.self, from: data) else {
            return nil
        }
        return decoded
    }
}

/// Wire representation of the stepped ergonomic policy.
public struct PurahABIDecomposedPolicy: Codable, Sendable, Equatable {
    public var maxRailItems: Int
    public var minChipHeight: Double
    public var maxChipHeight: Double
    public var spacing: Double
    public var overflowStrategy: String?

    public init(
        maxRailItems: Int = 4,
        minChipHeight: Double = 36,
        maxChipHeight: Double = 185,
        spacing: Double = 2.5,
        overflowStrategy: String? = nil
    ) {
        self.maxRailItems = maxRailItems
        self.minChipHeight = minChipHeight
        self.maxChipHeight = maxChipHeight
        self.spacing = spacing
        self.overflowStrategy = overflowStrategy
    }

    public func toPolicy() -> PurahDecomposedPolicy {
        PurahDecomposedPolicy(
            maxRailItems: maxRailItems,
            minChipHeight: CGFloat(minChipHeight),
            maxChipHeight: CGFloat(maxChipHeight),
            spacing: CGFloat(spacing),
            overflowStrategy: DecomposedOverflowStrategy(rawValue: overflowStrategy ?? "") ?? .smartFold
        )
    }

    public static func decode(_ json: String) -> PurahDecomposedPolicy? {
        guard let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(PurahABIDecomposedPolicy.self, from: data) else {
            return nil
        }
        return decoded.toPolicy()
    }
}
