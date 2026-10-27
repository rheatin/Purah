// Sources/PurahUI/Common/PurahDecomposedCapacitySettingRow.swift
import SwiftUI
import PurahCore

/// Standardized settings UI row for configuring maximum on-rail items and overflow folding behavior.
public struct PurahDecomposedCapacitySettingRow: View {
    public var title: String
    public var subtitle: String
    @Binding public var maxItems: Int
    @Binding public var overflowStrategy: DecomposedOverflowStrategy
    public var range: ClosedRange<Double>
    public var step: Double
    public var itemUnitName: String

    public init(
        title: String = "Max Rail Items",
        subtitle: String = "Primary items shown on the bezel rail before folding",
        maxItems: Binding<Int>,
        overflowStrategy: Binding<DecomposedOverflowStrategy>,
        range: ClosedRange<Double> = 2...10,
        step: Double = 1.0,
        itemUnitName: String = "items"
    ) {
        self.title = title
        self.subtitle = subtitle
        self._maxItems = maxItems
        self._overflowStrategy = overflowStrategy
        self.range = range
        self.step = step
        self.itemUnitName = itemUnitName
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PurahThemedSliderRow(
                title: title,
                subtitle: subtitle,
                value: Binding(
                    get: { Double(maxItems) },
                    set: { maxItems = Int($0) }
                ),
                range: range,
                step: step,
                valueBadgeText: "\(maxItems) \(itemUnitName)"
            )

            VStack(alignment: .leading, spacing: 4) {
                Text("overflow.strategy".localized)
                    .font(.caption)
                    .foregroundColor(.secondary)

                PurahThemedSegmentedPicker(
                    options: DecomposedOverflowStrategy.allCases,
                    selection: $overflowStrategy,
                    titleForOption: { $0.displayName }
                )
            }
        }
    }
}
