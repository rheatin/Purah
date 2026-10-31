// Sources/PurahCore/Plugins/PurahDecomposedPolicy.swift
import Foundation

/// Strategy for handling items when active decomposed sub-items exceed maxRailItems.
public enum DecomposedOverflowStrategy: String, Codable, Sendable, CaseIterable {
    /// Folds excess items into a "+N More" interactive capsule sub-item.
    case smartFold = "smartFold"
    /// Truncates items strictly at maxRailItems.
    case truncate = "truncate"
    /// Dynamically scales chip height down towards minChipHeight to fit more items before truncating.
    case compactScale = "compactScale"

    public var displayName: String {
        switch self {
        case .smartFold: return "Smart Fold (+N More)"
        case .truncate: return "Strict Truncate"
        case .compactScale: return "Compact Scale"
        }
    }
}

/// Geometry of the host-owned stepped drawer card.
///
/// A chip is one row — it has no header. The card is exactly the chip's height,
/// so the row (icon, title/badge, subtitle, settings/pin) is the card, and any
/// extra height a tall chip has goes to the plugin body underneath. The row
/// scales with the card instead of leaving a fixed strip at the top: a 40pt
/// chip gets 13pt type, a 120pt chip gets ~18pt, so the same row reads as the
/// same row at every height. The same numbers decide both the view and the
/// click-through hit box; they must not be derived in two places.
public enum PurahSteppedCardMetrics {
    /// Space above the row and below the body. Small on purpose: a spare 4pt
    /// here is 4pt of body a 40pt calendar chip does not have.
    public static let verticalPadding: CGFloat = 2.0
    /// Gap between the row and the body.
    public static let rowGap: CGFloat = 2.0
    /// The row's height at scale 1.0 (a 40pt chip): a 26pt icon block beside a
    /// 13pt title over an 11pt subtitle.
    public static let baseRowHeight: CGFloat = 30.0

    /// The card keeps the chip's height. `minChipHeight` only applies when the
    /// rail has squeezed the chip below its own ergonomic floor.
    public static func cardHeight(slotHeight: CGFloat, minChipHeight: CGFloat) -> CGFloat {
        max(slotHeight, minChipHeight)
    }

    /// One factor for every dimension in the row (type, icon block, spacing),
    /// so the row can never stretch unevenly. Capped low (1.15) on purpose: the
    /// card's width does not grow with its height, so every extra point of type
    /// is a character the title no longer fits. Past the cap the extra height
    /// goes to the body instead.
    public static func rowScale(cardHeight: CGFloat) -> CGFloat {
        min(max(1.0 + (cardHeight - 40.0) / 160.0, 0.92), 1.15)
    }

    /// The row the host draws. Never taller than the card it sits in.
    public static func rowHeight(cardHeight: CGFloat) -> CGFloat {
        min(baseRowHeight * rowScale(cardHeight: cardHeight),
            max(cardHeight - verticalPadding * 2, 0))
    }

    /// Content height the plugin body is given. Zero is allowed: a
    /// minimum-size chip is its row and nothing else.
    public static func bodyHeight(cardHeight: CGFloat) -> CGFloat {
        let inner = max(cardHeight - verticalPadding * 2, 0)
        let row = rowHeight(cardHeight: cardHeight)
        // No gap when there is no body: a squeezed chip is all row.
        return max(inner - row - (inner > row ? rowGap : 0), 0)
    }

    /// Keeps an expanded card on screen: never past the bottom inset, never
    /// above the top safe band.
    public static func verticalShift(itemTop: CGFloat, cardHeight: CGFloat, screenHeight: CGFloat) -> CGFloat {
        let bottomOverflow = max(itemTop + cardHeight - (screenHeight - 12.0), 0.0)
        let roomAbove = max(itemTop - 16.0, 0.0)
        return min(bottomOverflow, roomAbove)
    }
}

/// Unified ergonomic and capacity policy for decomposed (stepped) pods and rail chips.
public struct PurahDecomposedPolicy: Sendable, Codable, Equatable {
    /// Maximum number of active chips displayed on the bezel rail.
    public var maxRailItems: Int
    /// Strict ergonomic minimum height for an individual sub-item chip (pt).
    public var minChipHeight: CGFloat
    /// Maximum height threshold for an individual sub-item chip (pt).
    public var maxChipHeight: CGFloat
    /// Vertical physical spacing between sub-item chips (pt).
    public var spacing: CGFloat
    /// Strategy applied when active items exceed maxRailItems.
    public var overflowStrategy: DecomposedOverflowStrategy

    public init(
        maxRailItems: Int = 4,
        minChipHeight: CGFloat = 36.0,
        maxChipHeight: CGFloat = 185.0,
        spacing: CGFloat = 2.5,
        overflowStrategy: DecomposedOverflowStrategy = .smartFold
    ) {
        self.maxRailItems = max(maxRailItems, 1)
        self.minChipHeight = max(minChipHeight, 20.0)
        self.maxChipHeight = max(maxChipHeight, minChipHeight)
        self.spacing = spacing
        self.overflowStrategy = overflowStrategy
    }

    /// Canonical ergonomic minimum height formula for decomposed pods on the rail.
    /// Guarantees that sub-items are never compressed below minChipHeight.
    public func calculateMinimumHeight(activeCount: Int) -> CGFloat {
        let count = max(min(activeCount, maxRailItems), 1)
        let totalSpacing = CGFloat(count - 1) * spacing
        return CGFloat(count) * minChipHeight + totalSpacing
    }

    /// Default ergonomic policies for standard built-in modes
    public static let calendarDefault = PurahDecomposedPolicy(
        maxRailItems: 4,
        minChipHeight: 40.0,
        maxChipHeight: 185.0,
        spacing: 2.5,
        overflowStrategy: .smartFold
    )

    public static let todoDefault = PurahDecomposedPolicy(
        maxRailItems: 6,
        minChipHeight: 32.0,
        maxChipHeight: 185.0,
        spacing: 2.5,
        overflowStrategy: .smartFold
    )

    public static let vitalsDefault = PurahDecomposedPolicy(
        maxRailItems: 6,
        minChipHeight: 56.0,
        maxChipHeight: 185.0,
        spacing: 2.5,
        overflowStrategy: .truncate
    )

    public static let scriptsDefault = PurahDecomposedPolicy(
        maxRailItems: 6,
        minChipHeight: 56.0,
        maxChipHeight: 185.0,
        spacing: 2.5,
        overflowStrategy: .truncate
    )

    public static let standardComposite = PurahDecomposedPolicy(
        maxRailItems: 1,
        minChipHeight: 120.0,
        maxChipHeight: 800.0,
        spacing: 0.0,
        overflowStrategy: .truncate
    )
}
