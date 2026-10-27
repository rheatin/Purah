// Sources/PurahUI/Common/PurahAccessibility.swift
import SwiftUI
import PurahCore

/// Helpers for labelling controls whose visible text lives somewhere else.
///
/// Almost every settings row in Purah is laid out by hand: a `VStack` holds the
/// title and subtitle, a `Spacer()` pushes the control to the trailing edge, and
/// the control itself is created with an empty label (`Toggle("")`) so it does
/// not render its own text. Sighted users read the row as one unit. VoiceOver
/// does not: it announces the control alone, so an unlabelled switch in a row
/// becomes "switch, off" with no indication of what it controls.
///
/// The fix cannot be "put the text in the Toggle's label" — that would either
/// duplicate the visible text or reflow the row. Instead the row owns the text
/// and the control borrows it.
public extension View {
    /// Labels the view with a title and optional detail, as one announcement.
    func purahRowAccessibility(_ title: String, detail: String? = nil) -> some View {
        accessibilityLabel(PurahA11y.rowLabel(title, detail: detail))
    }

    /// Marks a view as a single VoiceOver element with a button trait.
    ///
    /// Use on a tap target that draws itself (an `HStack` of icon and text)
    /// rather than a `Button`, so the glyph and the word are not announced as
    /// two separate elements.
    func purahButtonAccessibility(_ label: String, hint: String? = nil, isSelected: Bool = false) -> some View {
        accessibilityElement(children: .ignore)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityLabel(label)
            .accessibilityHint(hint ?? "")
    }
}
