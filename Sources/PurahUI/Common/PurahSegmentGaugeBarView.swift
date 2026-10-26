// Sources/PurahUI/Common/PurahSegmentGaugeBarView.swift
import SwiftUI

/// One filled channel of a `PurahSegmentGaugeBarView`.
///
/// `ratio` is the fraction of the bar height that the channel fills; it is
/// clamped on init so callers can pass raw telemetry without sanitising.
public struct PurahGaugeSegment: Identifiable, Sendable {
    public let id: String
    public var ratio: Double
    public var color: Color
    public var isAlerting: Bool

    public init(id: String = UUID().uuidString, ratio: Double, color: Color, isAlerting: Bool = false) {
        self.id = id
        self.ratio = min(max(ratio, 0.0), 1.0)
        self.color = color
        self.isAlerting = isAlerting
    }
}

/// Vertical rail-bar gauge: a rounded track with one or more filled channels
/// growing from the bottom edge.
///
/// One segment reproduces the classic single-metric rail bar (Vitals' composite
/// bar, a decomposed chip's gauged indicator). Several segments split the bar
/// into equal-width channels so a single pod can show multiple metrics at a
/// glance without widening the rail.
///
/// An empty `segments` array draws the track alone — useful for chips that keep
/// a tinted rail without a metric behind it.
public struct PurahSegmentGaugeBarView: View {
    public var segments: [PurahGaugeSegment]
    /// Gap between channels. Ignored when there is a single segment.
    public var spacing: CGFloat
    public var barWidth: CGFloat
    public var height: CGFloat
    /// Unfilled portion of the bar. Pass `tint.opacity(0.25)` for the classic
    /// look, or a state colour for decomposed chips.
    public var trackColor: Color
    /// Smallest visible fill so a near-zero metric still reads as "present".
    /// Pass `0` to draw nothing at all when the ratio is zero.
    public var minimumVisibleFill: CGFloat

    public init(
        segments: [PurahGaugeSegment],
        spacing: CGFloat = 2.0,
        barWidth: CGFloat = 8.0,
        height: CGFloat = 80.0,
        trackColor: Color = Color.primary.opacity(0.1),
        minimumVisibleFill: CGFloat = 4.0
    ) {
        self.segments = segments
        self.spacing = max(spacing, 0)
        self.barWidth = max(barWidth, 1.0)
        self.height = max(height, 1.0)
        self.trackColor = trackColor
        self.minimumVisibleFill = max(minimumVisibleFill, 0)
    }

    public var body: some View {
        let trackRadius = min(barWidth / 2, 4)
        let channelCount = max(segments.count, 1)
        let channelWidth = max((barWidth - spacing * CGFloat(channelCount - 1)) / CGFloat(channelCount), 1.0)
        let channelRadius = min(channelWidth / 2, 4)

        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: trackRadius)
                .fill(trackColor)

            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(segments) { segment in
                    RoundedRectangle(cornerRadius: channelRadius)
                        .fill(segment.color)
                        .frame(height: fillHeight(for: segment.ratio))
                        .modifier(OptionalGlow(color: segment.color, enabled: segment.isAlerting))
                }
            }
        }
        .frame(width: barWidth, height: height, alignment: .bottom)
    }

    private func fillHeight(for ratio: Double) -> CGFloat {
        max(height * CGFloat(ratio), minimumVisibleFill)
    }
}
