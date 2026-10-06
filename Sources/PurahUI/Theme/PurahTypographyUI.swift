// Sources/PurahUI/Theme/PurahTypographyUI.swift
import SwiftUI
import PurahCore

public struct OpticalTrackingModifier: ViewModifier {
    public let size: CGFloat

    public func body(content: Content) -> some View {
        content.tracking(CGFloat(PurahTypography.opticalTracking(for: Double(size))))
    }
}

public extension View {
    func opticalTracking(size: CGFloat) -> some View {
        self.modifier(OpticalTrackingModifier(size: size))
    }
}

public extension Text {
    func purahTitle(size: CGFloat = 15, weight: Font.Weight = .bold, design: Font.Design = .rounded) -> Text {
        self.font(.system(size: size, weight: weight, design: design))
            .tracking(CGFloat(PurahTypography.opticalTracking(for: Double(size))))
    }

    func purahBody(size: CGFloat = 11, weight: Font.Weight = .medium, design: Font.Design = .default) -> Text {
        self.font(.system(size: size, weight: weight, design: design))
            .tracking(CGFloat(PurahTypography.opticalTracking(for: Double(size))))
    }

    func purahCaption(size: CGFloat = 9, weight: Font.Weight = .regular, design: Font.Design = .default) -> Text {
        self.font(.system(size: size, weight: weight, design: design))
            .tracking(CGFloat(PurahTypography.opticalTracking(for: Double(size))))
    }

    func purahBadge(size: CGFloat = 7.5, weight: Font.Weight = .bold, design: Font.Design = .monospaced) -> Text {
        self.font(.system(size: size, weight: weight, design: design))
            .tracking(CGFloat(PurahTypography.opticalTracking(for: Double(size))))
    }
}
