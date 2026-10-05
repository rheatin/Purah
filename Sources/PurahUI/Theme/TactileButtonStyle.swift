// Sources/PurahUI/Theme/TactileButtonStyle.swift
import SwiftUI

public struct TactileButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1.0)
            .animation(.spring(response: 0.16, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

public extension ButtonStyle where Self == TactileButtonStyle {
    static var tactile: TactileButtonStyle { TactileButtonStyle() }
}
