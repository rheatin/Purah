// Sources/PurahCore/Plugins/PurahPodCapabilityProvider.swift
import Foundation

@MainActor
public protocol PurahPodCapabilityProvider: Sendable {
    var podId: String { get }
    var isDecomposed: Bool { get }
    var subItemCount: Int { get }
    var subItemTitles: [String] { get }

    func minimumDrawerHeight(store: PurahWorkspaceStore) -> CGFloat
    func hasPinnedChild(store: PurahWorkspaceStore) -> Bool
    func ownsSubItemId(_ itemId: String, store: PurahWorkspaceStore) -> Bool
}

public extension PurahPodCapabilityProvider {
    var isDecomposed: Bool { false }
    var subItemCount: Int { 0 }
    var subItemTitles: [String] { [] }
    func hasPinnedChild(store: PurahWorkspaceStore) -> Bool { false }
    func ownsSubItemId(_ itemId: String, store: PurahWorkspaceStore) -> Bool { false }
}
