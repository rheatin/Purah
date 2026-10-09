// Sources/PurahCore/Plugins/PurahPodCapabilityProvider.swift
import Foundation

@MainActor
public protocol PurahPodCapabilityProvider: Sendable {
    var podId: String { get }
    var isDecomposed: Bool { get }
    var subItemCount: Int { get }
    var subItemTitles: [String] { get }

    func isDecomposed(store: PurahWorkspaceStore) -> Bool
    func subItemCount(store: PurahWorkspaceStore) -> Int
    func subItemId(at index: Int, store: PurahWorkspaceStore) -> String?
    func subItemTitle(at index: Int, store: PurahWorkspaceStore) -> String?

    func minimumDrawerHeight(store: PurahWorkspaceStore) -> CGFloat
    func hasPinnedChild(store: PurahWorkspaceStore) -> Bool
    func ownsSubItemId(_ itemId: String, store: PurahWorkspaceStore) -> Bool
}

public extension PurahPodCapabilityProvider {
    var isDecomposed: Bool { false }
    var subItemCount: Int { 0 }
    var subItemTitles: [String] { [] }

    func isDecomposed(store: PurahWorkspaceStore) -> Bool {
        isDecomposed
    }

    func subItemCount(store: PurahWorkspaceStore) -> Int {
        subItemCount
    }

    func subItemId(at index: Int, store: PurahWorkspaceStore) -> String? {
        nil
    }

    func subItemTitle(at index: Int, store: PurahWorkspaceStore) -> String? {
        guard index >= 0, index < subItemTitles.count else { return nil }
        return subItemTitles[index]
    }

    func minimumDrawerHeight(store: PurahWorkspaceStore) -> CGFloat { 120.0 }
    func hasPinnedChild(store: PurahWorkspaceStore) -> Bool { false }
    func ownsSubItemId(_ itemId: String, store: PurahWorkspaceStore) -> Bool { false }
}
