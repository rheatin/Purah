// Sources/PurahUI/Common/PurahItemCard.swift
import SwiftUI

/// One framed row, shared by the Shelf, the Script Runway and the per-script
/// drawer card.
///
/// The three used to be three different styles: a Shelf row carried a liquid
/// card at rest, a Runway row was transparent until the pointer arrived, and
/// the hover glow was whatever each view had picked. The frame is now always
/// present — a row that only exists under the pointer is a row you cannot aim
/// at — and `isHovered` changes only its fill, border and glow.
///
/// Nothing scales or offsets. That is the whole point: the Shelf row used to
/// grow 1.5% on hover and the extra width pushed its frame past the card's
/// left edge.
public struct PurahItemCardModifier: ViewModifier {
    public var accent: Color
    public var isHovered: Bool
    /// Running, or otherwise occupied (a run in flight, a drop target).
    public var isActive: Bool
    public var isSelected: Bool
    public var cornerRadius: CGFloat

    public func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            // The glow is a blurred ring behind the row rather than a shadow on
            // it: `.shadow` would also halo the labels inside.
            .background(
                shape
                    .stroke(accent.opacity(isActive ? 0.45 : 0.32), lineWidth: 3)
                    .blur(radius: 3)
                    .opacity(isHovered || isActive ? 1 : 0)
            )
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(border, lineWidth: isSelected ? 1.5 : 0.9))
            .animation(PurahMotionPolicy.hover, value: isHovered)
            .animation(PurahMotionPolicy.hover, value: isActive)
    }

    private var fill: Color {
        if isSelected { return accent.opacity(0.18) }
        if isActive { return accent.opacity(0.12) }
        if isHovered { return accent.opacity(0.07) }
        return Color.primary.opacity(0.03)
    }

    private var border: Color {
        if isSelected { return accent }
        if isActive { return accent.opacity(0.40) }
        if isHovered { return accent.opacity(0.55) }
        return ThemeManager.shared.palette.borderColor.opacity(0.32)
    }
}

public extension View {
    func purahItemCard(
        accent: Color,
        isHovered: Bool,
        isActive: Bool = false,
        isSelected: Bool = false,
        cornerRadius: CGFloat = PurahItemRhythm.rowCornerRadius
    ) -> some View {
        modifier(PurahItemCardModifier(
            accent: accent,
            isHovered: isHovered,
            isActive: isActive,
            isSelected: isSelected,
            cornerRadius: cornerRadius
        ))
    }
}
