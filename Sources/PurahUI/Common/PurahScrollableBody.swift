// Sources/PurahUI/Common/PurahScrollableBody.swift
import SwiftUI

/// Scroll container for drawer bodies whose content has a natural minimum size.
///
/// This is **opt-in by design**. The host never wraps a plugin body in a scroll
/// view on its own: a body that relies on `maxHeight: .infinity` (a vinyl disc,
/// an equal-height card grid) would stop filling its card the moment it is
/// placed inside one, because a scroll view proposes unbounded height to its
/// content. Plugins that want overflow to scroll say so; plugins that want to
/// compress or clip keep their own layout.
///
/// Two behaviours make it feel native rather than bolted on:
/// - Indicators are the system's overlay scrollers, so nothing is drawn at rest
///   and they fade in only while scrolling.
/// - Bounce is based on size: content that already fits does not rubber-band
///   inside a drawer that is only 120pt tall.
///
/// ```swift
/// VStack { header; PurahScrollableBody { longList } }
/// ```
public struct PurahScrollableBody<Content: View>: View {
    public enum Indicators: Sendable {
        /// System overlay scrollers — hidden at rest, visible while scrolling.
        case automatic
        case hidden
    }

    public var axis: Axis.Set
    public var indicators: Indicators
    public var contentInsets: EdgeInsets
    @ViewBuilder public var content: () -> Content

    /// Indicators default to hidden: a rail drawer is a glanceable surface, and
    /// the built-in drawers all chose that. Use `.automatic` for long-form
    /// content (a transcript, a document preview) where the reader needs to
    /// know there is more.
    public init(
        _ axis: Axis.Set = .vertical,
        indicators: Indicators = .hidden,
        contentInsets: EdgeInsets = EdgeInsets(),
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.axis = axis
        self.indicators = indicators
        self.contentInsets = contentInsets
        self.content = content
    }

    public var body: some View {
        ScrollView(axis) {
            content()
                .padding(contentInsets)
        }
        .scrollIndicators(indicators == .automatic ? .automatic : .hidden)
        .scrollBounceBehavior(.basedOnSize, axes: axis)
        // A drawer is a hover surface, not a document: keep the scroll view out
        // of the focus chain so hovering never pulls key focus from the app
        // underneath (AGENTS.md §2.3).
        .focusable(false)
    }
}
