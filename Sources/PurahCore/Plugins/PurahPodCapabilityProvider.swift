// Sources/PurahCore/Plugins/PurahPodCapabilityProvider.swift
import Foundation

/// What a pod is doing right now.
///
/// This is a *state* a plugin reports, not a view it draws: the host owns the
/// rendering (one full-span sweep over the rail bar), so every plugin that
/// gains a long-running task gets the same visual without copying it, and the
/// host can keep the alert beacon quiet while the work is still in progress.
public enum PurahPodActivity: Sendable, Equatable {
    case idle
    /// The plugin is mid-task (streaming an answer, running a command).
    case working
}

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

    /// Width of one stepped chip's card, when it is not the composite width.
    ///
    /// The click-through hit box is built from this, so a chip that draws
    /// narrower than `adaptiveDrawerWidth` cannot claim desktop it does not
    /// cover. Return nil when the chip uses the composite width.
    func steppedDrawerWidth(store: PurahWorkspaceStore) -> CGFloat?

    /// Autonomously declared preferred drawer height when operating in Expanded drawer mode.
    func preferredDrawerHeight(store: PurahWorkspaceStore) -> CGFloat

    /// What the pod is doing right now. The host renders `.working` as a sweep
    /// over the rail bar and suppresses the alert beacon meanwhile, so a
    /// plugin reports state instead of drawing its own progress view.
    func activity(store: PurahWorkspaceStore) -> PurahPodActivity

    /// Ergonomic policy defining chip height bounds, maximum visible items, and overflow behavior.
    var decomposedPolicy: PurahDecomposedPolicy { get }
    func decomposedPolicy(store: PurahWorkspaceStore) -> PurahDecomposedPolicy

    func setDecomposed(_ decomposed: Bool, store: PurahWorkspaceStore)
}

public extension PurahPodCapabilityProvider {
    var isDecomposed: Bool { false }
    var subItemCount: Int { 0 }
    var subItemTitles: [String] { [] }
    var decomposedPolicy: PurahDecomposedPolicy { .standardComposite }

    func setDecomposed(_ decomposed: Bool, store: PurahWorkspaceStore) {}

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
    func steppedDrawerWidth(store: PurahWorkspaceStore) -> CGFloat? { nil }
    func activity(store: PurahWorkspaceStore) -> PurahPodActivity { .idle }

    func preferredDrawerHeight(store: PurahWorkspaceStore) -> CGFloat {
        max(minimumDrawerHeight(store: store) * 1.5, 240.0)
    }
}
