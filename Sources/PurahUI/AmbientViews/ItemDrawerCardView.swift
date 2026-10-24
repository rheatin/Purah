// Sources/PurahUI/AmbientViews/ItemDrawerCardView.swift
import SwiftUI
import AppKit
import PurahCore

// MARK: - Shared Drawer Primitives & Modifiers

public struct OptionalGlow: ViewModifier {
    public let color: Color
    public let enabled: Bool

    public init(color: Color, enabled: Bool) {
        self.color = color
        self.enabled = enabled
    }

    public func body(content: Content) -> some View {
        if enabled {
            content
                .shadow(color: color.opacity(0.8), radius: 3)
                .shadow(color: color.opacity(0.4), radius: 6)
        } else {
            content
        }
    }
}
