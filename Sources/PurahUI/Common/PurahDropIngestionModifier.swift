// Sources/PurahUI/Common/PurahDropIngestionModifier.swift
import SwiftUI
import AppKit
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
            content.onDrop(of: types, delegate: IngestionDropDelegate(types: types, onDrop: onDrop))
        } else {
            content
        }
    }
}

private struct IngestionDropDelegate: DropDelegate {
    let types: [UTType]
    let onDrop: ([NSItemProvider]) -> Bool

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .copy)
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: types) ||
        (types.contains(.fileURL) && NSPasteboard(name: .drag).canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]))
    }

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: types)
        return onDrop(providers)
    }
}
