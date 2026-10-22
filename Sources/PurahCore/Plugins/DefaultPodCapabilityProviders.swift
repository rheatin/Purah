// Sources/PurahCore/Plugins/DefaultPodCapabilityProviders.swift
import Foundation
import AppKit

@MainActor
struct DefaultCalendarCapabilityProvider: PurahPodCapabilityProvider {
    let podId: String = "calendar"
    var isDecomposed: Bool { true }
    var decomposedPolicy: PurahDecomposedPolicy { .calendarDefault }

    func isDecomposed(store: PurahWorkspaceStore) -> Bool {
        store.calendarOverflowStrategy != .continuousStream
    }

    func adaptiveDrawerWidth(store: PurahWorkspaceStore) -> CGFloat? {
        if !isDecomposed(store: store) || store.isInSharedMajorPod(podId: "calendar") {
            return 360.0
        }
        return 310.0
    }

    func preferredDrawerHeight(store: PurahWorkspaceStore) -> CGFloat {
        max(minimumDrawerHeight(store: store), 260.0)
    }

    func minimumDrawerHeight(store: PurahWorkspaceStore) -> CGFloat {
        if store.calendarOverflowStrategy == .continuousStream || store._calendarEvents.isEmpty {
            return 140.0
        }
        let maxEvents = max(store.calendarMaxRailEvents, 1)
        let minChipH: CGFloat = 40.0
        let spacing: CGFloat = 2.5
        let totalSpacing = CGFloat(maxEvents - 1) * spacing
        return CGFloat(maxEvents) * minChipH + totalSpacing
    }

    func hasPinnedChild(store: PurahWorkspaceStore) -> Bool {
        store._calendarEvents.contains { store.isItemPinned(id: $0.id) }
    }

    func ownsSubItemId(_ itemId: String, store: PurahWorkspaceStore) -> Bool {
        store._calendarEvents.contains { $0.id == itemId }
    }

    func subItemCount(store: PurahWorkspaceStore) -> Int {
        store._calendarEvents.count
    }

    func subItemId(at index: Int, store: PurahWorkspaceStore) -> String? {
        guard store._calendarEvents.indices.contains(index) else { return nil }
        return store._calendarEvents[index].id
    }

    func subItemTitle(at index: Int, store: PurahWorkspaceStore) -> String? {
        guard store._calendarEvents.indices.contains(index) else { return nil }
        return store._calendarEvents[index].title
    }
}

@MainActor
struct DefaultTodoCapabilityProvider: PurahPodCapabilityProvider {
    let podId: String = "todo"
    var isDecomposed: Bool { true }
    var decomposedPolicy: PurahDecomposedPolicy { .todoDefault }

    func adaptiveDrawerWidth(store: PurahWorkspaceStore) -> CGFloat? { 340.0 }
    func isDecomposed(store: PurahWorkspaceStore) -> Bool { true }
    func preferredDrawerHeight(store: PurahWorkspaceStore) -> CGFloat {
        max(minimumDrawerHeight(store: store), 250.0)
    }
    func minimumDrawerHeight(store: PurahWorkspaceStore) -> CGFloat {
        if store._todos.filter({ !$0.isCompleted }).isEmpty {
            return 130.0
        }
        let maxTasks = max(store.todoMaxRailTasks, 1)
        let minChipH: CGFloat = 32.0
        let spacing: CGFloat = 2.5
        let totalSpacing = CGFloat(maxTasks - 1) * spacing
        return CGFloat(maxTasks) * minChipH + totalSpacing
    }

    func hasPinnedChild(store: PurahWorkspaceStore) -> Bool {
        store._todos.contains { store.isItemPinned(id: $0.id) }
    }

    func ownsSubItemId(_ itemId: String, store: PurahWorkspaceStore) -> Bool {
        store._todos.contains { $0.id == itemId }
    }

    func subItemCount(store: PurahWorkspaceStore) -> Int {
        min(store._todos.count, store.todoMaxRailTasks)
    }

    func subItemId(at index: Int, store: PurahWorkspaceStore) -> String? {
        guard index < store.todoMaxRailTasks, store._todos.indices.contains(index) else { return nil }
        return store._todos[index].id
    }

    func subItemTitle(at index: Int, store: PurahWorkspaceStore) -> String? {
        guard index < store.todoMaxRailTasks, store._todos.indices.contains(index) else { return nil }
        return store._todos[index].title
    }
}

@MainActor
struct DefaultVitalsCapabilityProvider: PurahPodCapabilityProvider {
    let podId: String = "vitals"
    var isDecomposed: Bool { true }
    var decomposedPolicy: PurahDecomposedPolicy { .vitalsDefault }

    func decomposedPolicy(store: PurahWorkspaceStore) -> PurahDecomposedPolicy {
        PurahDecomposedPolicy(
            maxRailItems: max(store._vitalsEnabledMetrics.count, 1),
            minChipHeight: 56.0,
            maxChipHeight: 185.0,
            spacing: 2.5,
            overflowStrategy: .truncate
        )
    }

    func isDecomposed(store: PurahWorkspaceStore) -> Bool {
        store._isVitalsDecomposed
    }

    func minimumDrawerHeight(store: PurahWorkspaceStore) -> CGFloat {
        if store._isVitalsDecomposed {
            let count = max(store._vitalsEnabledMetrics.count, 1)
            return CGFloat(count) * 56.0 + CGFloat(count - 1) * 2.5
        }
        return 300.0
    }

    func preferredDrawerHeight(store: PurahWorkspaceStore) -> CGFloat {
        max(minimumDrawerHeight(store: store), 260.0)
    }

    func adaptiveDrawerWidth(store: PurahWorkspaceStore) -> CGFloat? {
        360.0
    }

    func hasPinnedChild(store: PurahWorkspaceStore) -> Bool {
        store._vitalsEnabledMetrics.contains { store.isItemPinned(id: "vitals-\($0.rawValue)") }
    }

    func ownsSubItemId(_ itemId: String, store: PurahWorkspaceStore) -> Bool {
        itemId.hasPrefix("vitals-")
    }

    func subItemCount(store: PurahWorkspaceStore) -> Int {
        store._isVitalsDecomposed ? store._vitalsEnabledMetrics.count : 0
    }

    func subItemId(at index: Int, store: PurahWorkspaceStore) -> String? {
        guard store._isVitalsDecomposed, store._vitalsEnabledMetrics.indices.contains(index) else { return nil }
        return "vitals-\(store._vitalsEnabledMetrics[index].rawValue)"
    }

    func subItemTitle(at index: Int, store: PurahWorkspaceStore) -> String? {
        guard store._isVitalsDecomposed, store._vitalsEnabledMetrics.indices.contains(index) else { return nil }
        return store._vitalsEnabledMetrics[index].displayName
    }
}

@MainActor
struct DefaultScriptsCapabilityProvider: PurahPodCapabilityProvider {
    let podId: String = "scripts"
    var isDecomposed: Bool { true }
    var decomposedPolicy: PurahDecomposedPolicy { .scriptsDefault }

    func isDecomposed(store: PurahWorkspaceStore) -> Bool {
        store._isScriptsDecomposed
    }

    func adaptiveDrawerWidth(store: PurahWorkspaceStore) -> CGFloat? {
        if !isDecomposed(store: store) || store.isInSharedMajorPod(podId: "scripts") {
            return 360.0
        }
        return 300.0
    }

    func minimumDrawerHeight(store: PurahWorkspaceStore) -> CGFloat {
        if store._isScriptsDecomposed {
            let count = max(store.scriptsEnabledActions.count, 1)
            return CGFloat(count) * 56.0 + CGFloat(count - 1) * 2.5
        }
        return 160.0
    }

    func preferredDrawerHeight(store: PurahWorkspaceStore) -> CGFloat {
        max(minimumDrawerHeight(store: store), 240.0)
    }

    func hasPinnedChild(store: PurahWorkspaceStore) -> Bool {
        store.scriptsEnabledActions.contains { store.isItemPinned(id: "scripts-\($0.id)") }
    }

    func ownsSubItemId(_ itemId: String, store: PurahWorkspaceStore) -> Bool {
        itemId.hasPrefix("scripts-")
    }

    func subItemCount(store: PurahWorkspaceStore) -> Int {
        store._isScriptsDecomposed ? store.scriptsEnabledActions.count : 0
    }

    func subItemId(at index: Int, store: PurahWorkspaceStore) -> String? {
        guard store._isScriptsDecomposed, store.scriptsEnabledActions.indices.contains(index) else { return nil }
        return "scripts-\(store.scriptsEnabledActions[index].id)"
    }

    func subItemTitle(at index: Int, store: PurahWorkspaceStore) -> String? {
        guard store._isScriptsDecomposed, store.scriptsEnabledActions.indices.contains(index) else { return nil }
        return store.scriptsEnabledActions[index].name
    }
}

@MainActor
struct DefaultAICapabilityProvider: PurahPodCapabilityProvider {
    let podId: String = "ai"
    var isDecomposed: Bool { true }
    var decomposedPolicy: PurahDecomposedPolicy {
        PurahDecomposedPolicy(
            maxRailItems: 4,
            minChipHeight: 52.0,
            maxChipHeight: 210.0,
            spacing: 2.5,
            overflowStrategy: .truncate
        )
    }

    func decomposedPolicy(store: PurahWorkspaceStore) -> PurahDecomposedPolicy {
        let enabledCount = store._aiRolePresets.filter(\.isEnabled).count
        let count = min(enabledCount, max(store.aiMaxRailRoles, 1))
        return PurahDecomposedPolicy(
            maxRailItems: max(count, 1),
            minChipHeight: 52.0,
            maxChipHeight: 210.0,
            spacing: 2.5,
            overflowStrategy: .truncate
        )
    }

    func isDecomposed(store: PurahWorkspaceStore) -> Bool {
        store._isAIDecomposed
    }

    func adaptiveDrawerWidth(store: PurahWorkspaceStore) -> CGFloat? {
        store._isAIDecomposed ? 390.0 : 420.0
    }

    func minimumDrawerHeight(store: PurahWorkspaceStore) -> CGFloat {
        if store._isAIDecomposed {
            let enabledRoles = store._aiRolePresets.filter(\.isEnabled)
            let count = min(enabledRoles.count, max(store.aiMaxRailRoles, 1))
            let effectiveCount = max(count, 1)
            return CGFloat(effectiveCount) * 52.0 + CGFloat(effectiveCount - 1) * 2.5
        }
        return 260.0
    }

    func preferredDrawerHeight(store: PurahWorkspaceStore) -> CGFloat {
        320.0
    }

    func hasPinnedChild(store: PurahWorkspaceStore) -> Bool {
        let enabledRoles = store._aiRolePresets.filter(\.isEnabled)
        return enabledRoles.contains { store.isItemPinned(id: "ai-\($0.id)") }
    }

    func ownsSubItemId(_ itemId: String, store: PurahWorkspaceStore) -> Bool {
        itemId.hasPrefix("ai-")
    }

    func subItemCount(store: PurahWorkspaceStore) -> Int {
        let enabledRoles = store._aiRolePresets.filter(\.isEnabled)
        let count = min(enabledRoles.count, max(store.aiMaxRailRoles, 1))
        return store._isAIDecomposed ? count : 0
    }

    func subItemId(at index: Int, store: PurahWorkspaceStore) -> String? {
        let enabledRoles = store._aiRolePresets.filter(\.isEnabled)
        let maxCount = min(enabledRoles.count, max(store.aiMaxRailRoles, 1))
        guard store._isAIDecomposed, index >= 0, index < maxCount else { return nil }
        return "ai-\(enabledRoles[index].id)"
    }

    func subItemTitle(at index: Int, store: PurahWorkspaceStore) -> String? {
        let enabledRoles = store._aiRolePresets.filter(\.isEnabled)
        let maxCount = min(enabledRoles.count, max(store.aiMaxRailRoles, 1))
        guard store._isAIDecomposed, index >= 0, index < maxCount else { return nil }
        return enabledRoles[index].title
    }
}

@MainActor
struct DefaultCompositeCapabilityProvider: PurahPodCapabilityProvider {
    let podId: String
    let minHeight: CGFloat
    let adaptiveWidth: CGFloat?
    let preferredHeight: CGFloat?

    var decomposedPolicy: PurahDecomposedPolicy {
        PurahDecomposedPolicy(maxRailItems: 1, minChipHeight: minHeight, maxChipHeight: 800.0, spacing: 0.0, overflowStrategy: .truncate)
    }

    init(podId: String, minHeight: CGFloat, adaptiveWidth: CGFloat? = nil, preferredHeight: CGFloat? = nil) {
        self.podId = podId
        self.minHeight = minHeight
        self.adaptiveWidth = adaptiveWidth
        self.preferredHeight = preferredHeight
    }

    func minimumDrawerHeight(store: PurahWorkspaceStore) -> CGFloat {
        minHeight
    }

    func adaptiveDrawerWidth(store: PurahWorkspaceStore) -> CGFloat? {
        adaptiveWidth
    }

    func preferredDrawerHeight(store: PurahWorkspaceStore) -> CGFloat {
        if let preferredHeight {
            return preferredHeight
        }
        return max(minHeight * 1.5, 240.0)
    }
}
