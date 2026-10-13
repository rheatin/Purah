// Sources/PurahUI/Common/PurahDropIngestionModifier.swift
import SwiftUI
import UniformTypeIdentifiers

public struct PurahDropIngestionModifier: ViewModifier {
    public let types: [UTType]
    public let onDrop: ([NSItemProvider]) -> Bool

    public init(types: [UTType], onDrop: @escaping ([NSItemProvider]) -> Bool) {
        self.types = types
        self.onDrop = onDrop
    }

    @ViewBuilder
    public func body(content: Content) -> some View {
        if !types.isEmpty {
            content.onDrop(of: types, isTargeted: nil) { providers in
                onDrop(providers)
            }
        } else {
            content
        }
    }
}
