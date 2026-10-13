// Sources/PurahUI/Common/PurahSegmentGaugeBarView.swift
import SwiftUI

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

/// Generic multi-segment or discrete metric gauge rail bar view.
public struct PurahSegmentGaugeBarView: View {
    public var segments: [PurahGaugeSegment]
    public var spacing: CGFloat
    public var barWidth: CGFloat
    public var height: CGFloat

    public init(
        segments: [PurahGaugeSegment],
        spacing: CGFloat = 2.0,
        barWidth: CGFloat = 8.0,
        height: CGFloat = 80.0
    ) {
        self.segments = segments
        self.spacing = spacing
        self.barWidth = max(barWidth, 4.0)
        self.height = max(height, 20.0)
    }

    public var body: some View {
        VStack(spacing: spacing) {
            ForEach(segments) { segment in
                RoundedRectangle(cornerRadius: min(barWidth / 2, 4))
                    .fill(segment.color)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .modifier(OptionalGlow(color: segment.color, enabled: segment.isAlerting))
            }
        }
        .frame(width: barWidth, height: height)
        .clipShape(Capsule())
    }
}
