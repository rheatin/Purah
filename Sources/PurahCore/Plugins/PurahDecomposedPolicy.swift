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
