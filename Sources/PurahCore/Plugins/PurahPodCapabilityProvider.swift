// Sources/PurahCore/Plugins/PurahPodCapabilityProvider.swift
import Foundation

@MainActor
public protocol PurahPodCapabilityProvider: Sendable {
    var podId: String { get }
    var isDecomposed: Bool { get }

    func minimumDrawerHeight(store: PurahWorkspaceStore) -> CGFloat
    func hasPinnedChild(store: PurahWorkspaceStore) -> Bool
    func ownsSubItemId(_ itemId: String, store: PurahWorkspaceStore) -> Bool

    func activeSubItemFrames(
        item: ResolvedPodLayoutItem,
        store: PurahWorkspaceStore,
        totalHeight: Double,
        windowWidth: Double,
        corridor: Double
    ) -> [CGRect]?
}

public extension PurahPodCapabilityProvider {
    var isDecomposed: Bool { false }
    func hasPinnedChild(store: PurahWorkspaceStore) -> Bool { false }
    func ownsSubItemId(_ itemId: String, store: PurahWorkspaceStore) -> Bool { false }
    func activeSubItemFrames(
        item: ResolvedPodLayoutItem,
        store: PurahWorkspaceStore,
        totalHeight: Double,
        windowWidth: Double,
        corridor: Double
    ) -> [CGRect]? { nil }
}
