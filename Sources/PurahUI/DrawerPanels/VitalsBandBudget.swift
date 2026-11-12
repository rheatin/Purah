// Sources/PurahUI/DrawerPanels/VitalsBandBudget.swift
import CoreGraphics

/// Splits a tab into the part that draws its instruments and the part that
/// lists processes.
///
/// Every band on a Vitals tab is drawn at its natural height. A taller drawer
/// therefore cannot stretch a chart, a bar or a ribbon: the instruments keep
/// the size they were designed at, and every point above that zone belongs to
/// the process list, which is the one band that can use any height. A drawer
/// shorter than its instruments keeps them at natural height and the host
/// scrolls the tab instead of squashing the content.
public enum VitalsTabLayout {
    public struct Split: Equatable, Sendable {
        public let content: CGFloat
        public let list: CGFloat

        public init(content: CGFloat, list: CGFloat) {
            self.content = content
            self.list = list
        }
    }

    public static func split(
        available: CGFloat,
        naturalContent: CGFloat
    ) -> Split {
        let natural = max(naturalContent, 0)
        return Split(content: natural, list: max(max(available, 0) - natural, 0))
    }
}

/// How many process rows fit in the Process Inspector at its real row height.
public enum VitalsProcessListBudget {
    /// One row is a name line (11.5), a 2.5pt bar, 2pt of spacing and 7pt of
    /// vertical padding, plus the 5pt gap to the next row.
    public static let rowPitch: CGFloat = 28
    /// The tab's title row and its spacing above the first row.
    public static let headerHeight: CGFloat = 24

    /// Rows the height holds, never fewer than `minimum` and never more than
    /// the processes that exist.
    public static func rowsThatFit(available: CGFloat) -> Int {
        let room = max(available - headerHeight, 0)
        return max(Int((room / rowPitch).rounded(.down)), 1)
    }

    public static func visibleRowCount(
        available: CGFloat,
        total: Int,
        minimum: Int = 12
    ) -> Int {
        guard total > 0 else { return 0 }
        let fit = max(rowsThatFit(available: available), minimum)
        return min(fit, total)
    }
}
