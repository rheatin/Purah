import Testing
@testable import PurahUI

@Suite("Process Bar Split")
struct ProcessBarSplitTests {
    @Test("A zero value has zero width")
    func zeroStaysZero() {
        let single = ProcessBarSplitter.width(value: 0, scale: 10, trackWidth: 100)
        let split = ProcessBarSplitter.widths(
            first: 0,
            second: 0,
            scale: 10,
            trackWidth: 100
        )

        #expect(single == 0)
        #expect(split == .zero)
    }

    @Test("A tiny single value still gets a visible 2pt bar")
    func tinySingleGetsMinimumWidth() {
        let width = ProcessBarSplitter.width(
            value: 0.001,
            scale: 1_000,
            trackWidth: 100
        )

        #expect(width == 2)
    }

    @Test("Each tiny non-zero split segment gets a visible width")
    func tinySplitGetsTwoVisibleSegments() {
        let widths = ProcessBarSplitter.widths(
            first: 0.001,
            second: 0.002,
            scale: 1_000,
            trackWidth: 100
        )

        #expect(widths.total >= 2)
        #expect(widths.first >= 2)
        #expect(widths.second >= 2)
    }

    @Test("A zero component stays zero while the other keeps its minimum")
    func zeroComponentStaysZero() {
        let widths = ProcessBarSplitter.widths(
            first: 5,
            second: 0,
            scale: 100,
            trackWidth: 100
        )

        #expect(widths.first >= 2)
        #expect(widths.second == 0)
    }

    @Test("Segments never exceed a degenerate track")
    func widthsNeverExceedTrack() {
        let widths = ProcessBarSplitter.widths(
            first: 1,
            second: 1,
            scale: 1,
            trackWidth: 3
        )

        #expect(widths.first <= 3)
        #expect(widths.second <= 3)
        #expect(widths.total <= 3)
    }
}
