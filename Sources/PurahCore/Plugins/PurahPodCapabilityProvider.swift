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

    /// Autonomously declared preferred drawer width when operating in Adaptive mode.
    /// Return nil to fall back to the base layout engine's text-length estimation.
    func adaptiveDrawerWidth(store: PurahWorkspaceStore) -> CGFloat?

    /// Autonomously declared preferred drawer height when operating in Expanded drawer mode.
    func preferredDrawerHeight(store: PurahWorkspaceStore) -> CGFloat

    /// Ergonomic policy defining chip height bounds, maximum visible items, and overflow behavior.
    var decomposedPolicy: PurahDecomposedPolicy { get }
    func decomposedPolicy(store: PurahWorkspaceStore) -> PurahDecomposedPolicy
}

public extension PurahPodCapabilityProvider {
    var isDecomposed: Bool { false }
    var subItemCount: Int { 0 }
    var subItemTitles: [String] { [] }
    var decomposedPolicy: PurahDecomposedPolicy { .standardComposite }

    func isDecomposed(store: PurahWorkspaceStore) -> Bool {
        isDecomposed
    }

    func decomposedPolicy(store: PurahWorkspaceStore) -> PurahDecomposedPolicy {
        decomposedPolicy
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
    func adaptiveDrawerWidth(store: PurahWorkspaceStore) -> CGFloat? { nil }

    func preferredDrawerHeight(store: PurahWorkspaceStore) -> CGFloat {
        max(minimumDrawerHeight(store: store) * 1.5, 240.0)
    }
}
