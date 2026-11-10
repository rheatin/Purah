// Sources/PurahUI/DrawerPanels/VitalsBandBudget.swift
import CoreGraphics

/// Splits a drawer tab's height between its bands.
///
/// One rule, applied to every tab: a chart grows up to twice its natural
/// height, and every remaining point goes to a list-like band. A tab that is
/// shorter than its content shrinks every band by the same share instead of
/// keeping a hardcoded floor, and the returned heights always add up to the
/// available height, so no band can leave a void at the bottom of the drawer.
public enum VitalsBandBudget {
    public struct Band: Equatable, Sendable {
        /// The height the band needs to draw its content once.
        public var natural: CGFloat
        /// Share of the surplus. Zero pins the band at its natural height
        /// (a hairline, a footer that must not move).
        public var weight: CGFloat
        /// A chart stops at 2× its natural height. `nil` marks a list-like
        /// band, which absorbs the rest.
        public var maxHeight: CGFloat?

        public init(natural: CGFloat, weight: CGFloat = 1, maxHeight: CGFloat? = nil) {
            self.natural = natural
            self.weight = weight
            self.maxHeight = maxHeight
        }

        /// A plot: it earns the zoom, but only up to twice its natural size.
        public static func chart(natural: CGFloat, weight: CGFloat = 1) -> Band {
            Band(natural: natural, weight: weight, maxHeight: max(natural, 0) * 2)
        }

        /// A list or a text band: uncapped, because the extra points have to go
        /// somewhere and this is the band that can use them.
        public static func list(natural: CGFloat, weight: CGFloat = 1) -> Band {
            Band(natural: natural, weight: weight, maxHeight: nil)
        }

        /// A separator or a band pinned to its natural height.
        public static func fixed(_ height: CGFloat) -> Band {
            Band(natural: height, weight: 0, maxHeight: height)
        }
    }

    /// Returns one height per band. The heights sum to `available` (up to
    /// floating-point error) for any non-empty input.
    public static func allocate(available: CGFloat, bands: [Band]) -> [CGFloat] {
        guard !bands.isEmpty else { return [] }
        let total = max(available, 0)
        let naturals = bands.map { max($0.natural, 0) }
        let naturalSum = naturals.reduce(0, +)

        guard naturalSum > 0 else {
            return bands.map { _ in total / CGFloat(bands.count) }
        }

        // Short drawer: every band gives up the same share of itself. No band
        // keeps a floor, so the content scrolls as one piece instead of one
        // band staying fat while another collapses.
        if total <= naturalSum {
            return naturals.map { total * $0 / naturalSum }
        }

        var heights = naturals
        var surplus = total - naturalSum
        var open = bands.indices.filter { bands[$0].weight > 0 }

        func limit(_ index: Int) -> CGFloat {
            bands[index].maxHeight ?? .infinity
        }

        // Grow by weight, redistributing whatever a capped chart could not
        // take. A list band (uncapped) ends the loop with nothing left over.
        while surplus > 0.0001, !open.isEmpty {
            let weightSum = open.reduce(CGFloat.zero) { $0 + bands[$1].weight }
            guard weightSum > 0 else { break }

            var spent: CGFloat = 0
            var additions: [(Int, CGFloat)] = []
            for index in open {
                let share = surplus * bands[index].weight / weightSum
                let room = max(limit(index) - heights[index], 0)
                let addition = min(share, room)
                additions.append((index, addition))
                spent += addition
            }
            for (index, addition) in additions {
                heights[index] += addition
            }
            surplus -= spent
            open = open.filter { heights[$0] < limit($0) - 0.0001 }
            if spent <= 0.0001 { break }
        }

        // Every flexible band hit its cap (a tab of nothing but charts, taller
        // than 2× their sum). Spreading the rest by natural size is the only
        // way to honour "no void" without inventing a new band.
        if surplus > 0.0001 {
            for index in heights.indices {
                heights[index] += surplus * naturals[index] / naturalSum
            }
        }

        return heights
    }

    /// The height a tab draws: the drawer body when it is tall enough, or the
    /// bands' natural content when it is not.
    ///
    /// A band's views have an intrinsic minimum (a plot, a value line, a row of
    /// text); squashing them below it makes the content paint over itself
    /// instead of shrinking. So a body shorter than its content keeps the
    /// natural height and the host's scroll view scrolls the tab, rather than
    /// pretending a 60pt card can hold a 250pt sheet.
    public static func drawingHeight(available: CGFloat, bands: [Band]) -> CGFloat {
        max(max(available, 0), bands.reduce(0) { $0 + max($1.natural, 0) })
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
