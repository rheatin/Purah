// Sources/PurahCore/Plugins/DefaultPodCapabilityProviders.swift
import Foundation
import AppKit

@MainActor
struct DefaultCalendarCapabilityProvider: PurahPodCapabilityProvider {
    let podId: String = "calendar"
    var isDecomposed: Bool { true }

    func isDecomposed(store: PurahWorkspaceStore) -> Bool { true }
    func minimumDrawerHeight(store: PurahWorkspaceStore) -> CGFloat {
        let count = max(store._calendarEvents.count, 1)
        let minH = CGFloat(count) * 56.0 + CGFloat(count - 1) * 2.5
        return min(max(minH, 80.0), 320.0)
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

    func isDecomposed(store: PurahWorkspaceStore) -> Bool { true }
    func minimumDrawerHeight(store: PurahWorkspaceStore) -> CGFloat {
        let count = max(store._todos.count, 1)
        let minH = CGFloat(count) * 44.0 + CGFloat(count - 1) * 2.5
        return min(max(minH, 70.0), 320.0)
    }

    func hasPinnedChild(store: PurahWorkspaceStore) -> Bool {
        store._todos.contains { store.isItemPinned(id: $0.id) }
    }

    func ownsSubItemId(_ itemId: String, store: PurahWorkspaceStore) -> Bool {
        store._todos.contains { $0.id == itemId }
    }

    func subItemCount(store: PurahWorkspaceStore) -> Int {
        store._todos.count
    }

    func subItemId(at index: Int, store: PurahWorkspaceStore) -> String? {
        guard store._todos.indices.contains(index) else { return nil }
        return store._todos[index].id
    }

    func subItemTitle(at index: Int, store: PurahWorkspaceStore) -> String? {
        guard store._todos.indices.contains(index) else { return nil }
        return store._todos[index].title
    }
}

@MainActor
struct DefaultVitalsCapabilityProvider: PurahPodCapabilityProvider {
    let podId: String = "vitals"
    var isDecomposed: Bool { false }

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
    var isDecomposed: Bool { false }

    func isDecomposed(store: PurahWorkspaceStore) -> Bool {
        store._isScriptsDecomposed
    }

    func minimumDrawerHeight(store: PurahWorkspaceStore) -> CGFloat {
        if store._isScriptsDecomposed {
            let count = max(store.scriptsEnabledActions.count, 1)
            return CGFloat(count) * 56.0 + CGFloat(count - 1) * 2.5
        }
        return 160.0
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
struct DefaultCompositeCapabilityProvider: PurahPodCapabilityProvider {
    let podId: String
    let minHeight: CGFloat

    init(podId: String, minHeight: CGFloat) {
        self.podId = podId
        self.minHeight = minHeight
    }

    func minimumDrawerHeight(store: PurahWorkspaceStore) -> CGFloat {
        minHeight
    }
}
