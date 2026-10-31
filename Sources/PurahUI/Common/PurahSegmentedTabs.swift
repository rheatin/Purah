// Sources/PurahUI/Common/PurahSegmentedTabs.swift
import SwiftUI

/// Two or more mutually exclusive views of the same content.
///
/// The drawer header (Todo: Open / Completed) and the Vitals dashboard both
/// grew their own version of this, with different fonts, radii and selected
/// fills. One component, sized off `PurahHeaderMetrics`, so a tab looks the
/// same wherever it appears.
public struct PurahSegmentedTabs<Value: Hashable>: View {
    public struct Segment: Identifiable {
        public let id: Value
        public let title: String

        public init(_ id: Value, title: String) {
            self.id = id
            self.title = title
        }
    }

    private let segments: [Segment]
    private let selection: Value
    private let tint: Color
    private let height: CGFloat
    private let minSegmentWidth: CGFloat
    private let onSelect: (Value) -> Void

    /// `height` defaults to the header's 20pt hit box; a tab row that lives in
    /// the drawer body (Vitals) passes its own row height so it lines up with
    /// the controls beside it.
    public init(
        segments: [Segment],
        selection: Value,
        tint: Color = .accentColor,
        height: CGFloat = PurahHeaderMetrics.hitSize,
        minSegmentWidth: CGFloat = 46,
        onSelect: @escaping (Value) -> Void
    ) {
        self.segments = segments
        self.selection = selection
        self.tint = tint
        self.height = height
        self.minSegmentWidth = minSegmentWidth
        self.onSelect = onSelect
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(segments) { segment in
                let isOn = segment.id == selection
                Button {
                    withAnimation(PurahMotionPolicy.surfaceSoft) { onSelect(segment.id) }
                } label: {
                    Text(segment.title)
                        .font(.system(
                            size: PurahHeaderMetrics.pillFontSize + 0.5,
                            weight: isOn ? .bold : .medium,
                            design: .rounded
                        ))
                        .lineLimit(1)
                        // The whole segment is the button, not the glyphs:
                        // clicking the empty half of the pill used to do
                        // nothing because only the text carried the hit area.
                        .frame(minWidth: minSegmentWidth, maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .foregroundColor(isOn ? tint : Color.primary.opacity(0.55))
                        .background(
                            RoundedRectangle(cornerRadius: PurahHeaderMetrics.pillCorner, style: .continuous)
                                .fill(isOn ? tint.opacity(PurahHeaderMetrics.selectedFill) : .clear)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? [.isSelected] : [])
            }
        }
        .padding(2)
        .frame(height: height)
        .background(
            RoundedRectangle(cornerRadius: PurahHeaderMetrics.buttonCorner + 2, style: .continuous)
                .fill(Color.primary.opacity(PurahHeaderMetrics.menuFill))
        )
    }
}
