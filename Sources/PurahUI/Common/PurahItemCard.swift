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

    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { colorScheme == .dark }
    private var effectiveAccent: Color { accent.adaptiveInk(for: colorScheme) }

    public func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            // Dark mode keeps the luminous blurred ring behind hovered/active rows;
            // Light mode trades neon bleed for a clean tactile white tile elevation.
            .background(
                Group {
                    if isDark {
                        shape
                            .stroke(accent.opacity(isActive ? 0.45 : 0.32), lineWidth: 3)
                            .blur(radius: 3)
                            .opacity(isHovered || isActive ? 1 : 0)
                    }
                }
            )
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(border, lineWidth: isSelected ? 1.4 : 0.85))
            .shadow(
                color: isDark ? .clear : Color.black.opacity(isHovered || isActive ? 0.07 : 0.025),
                radius: isHovered || isActive ? 4 : 1.5,
                x: 0,
                y: isHovered || isActive ? 1.5 : 0.5
            )
            .animation(PurahMotionPolicy.hover, value: isHovered)
            .animation(PurahMotionPolicy.hover, value: isActive)
    }

    private var fill: Color {
        if isDark {
            if isSelected { return accent.opacity(0.18) }
            if isActive { return accent.opacity(0.12) }
            if isHovered { return accent.opacity(0.07) }
            return Color.primary.opacity(0.03)
        } else {
            if isSelected { return effectiveAccent.opacity(0.13) }
            if isActive { return effectiveAccent.opacity(0.09) }
            if isHovered { return Color.white.opacity(0.92) }
            return Color.white.opacity(0.60)
        }
    }

    private var border: Color {
        if isDark {
            if isSelected { return accent }
            if isActive { return accent.opacity(0.40) }
            if isHovered { return accent.opacity(0.55) }
            return ThemeManager.shared.palette.borderColor.opacity(0.32)
        } else {
            if isSelected { return effectiveAccent.opacity(0.75) }
            if isActive { return effectiveAccent.opacity(0.42) }
            if isHovered { return effectiveAccent.opacity(0.48) }
            return Color.black.opacity(0.085)
        }
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
