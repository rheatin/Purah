// Sources/PurahUI/Plugins/States/ScriptsPluginState.swift
import SwiftUI
import AppKit
import Foundation
import Observation
import PurahCore

@Observable
@MainActor
public final class ScriptsPluginState: Sendable {
    public var isDecomposed: Bool
    public var maxRailActions: Int
    public var enabledActionIds: [String]
    public var actions: [ScriptActionItem]
    public var lastOutput: String?
    public var liveStreamingOutput: String = ""
    public var isRunning: Bool
    public var lastExecutedActionId: String?
    public let storage: any PurahPluginStorage

    @ObservationIgnored private weak var boundStore: PurahWorkspaceStore?

    public var enabledActions: [ScriptActionItem] {
        if enabledActionIds.isEmpty {
            return actions
        }
        return actions.filter { enabledActionIds.contains($0.id) }
    }

    public var scriptsEnabledActionIds: [String] {
        get { enabledActionIds }
        set { enabledActionIds = newValue }
    }

    public var scriptsEnabledActions: [ScriptActionItem] {
        enabledActions
    }

    public init(storage: any PurahPluginStorage = ScopedPluginStorage(pluginId: "scripts")) {
        self.storage = storage
        if storage.string(forKey: "isDecomposed") != nil {
            self.isDecomposed = storage.bool(forKey: "isDecomposed")
        } else {
            self.isDecomposed = true
        }
        self.enabledActionIds = storage.codable(forKey: "enabledActionIds", as: [String].self) ?? []
        let savedSlotLimit = storage.int(forKey: "maxRailActions")
        self.maxRailActions = (savedSlotLimit > 0) ? savedSlotLimit : 12
        self.actions = storage.codable(forKey: "actions", as: [ScriptActionItem].self) ?? ScriptRunwayService.shared.actions
        self.lastOutput = nil
        self.isRunning = false
        self.lastExecutedActionId = nil
    }

    public func setMaxRailActions(_ count: Int) {
        maxRailActions = count
        storage.set(count, forKey: "maxRailActions")
    }

    public func load() {
        if storage.string(forKey: "isDecomposed") != nil {
            self.isDecomposed = storage.bool(forKey: "isDecomposed")
        } else {
            self.isDecomposed = true
        }
        if let ids = storage.codable(forKey: "enabledActionIds", as: [String].self) {
            self.enabledActionIds = ids
        }
        if let savedActions = storage.codable(forKey: "actions", as: [ScriptActionItem].self) {
            self.actions = savedActions
        }
    }

    public func save() {
        storage.set(isDecomposed, forKey: "isDecomposed")
        storage.setCodable(enabledActionIds, forKey: "enabledActionIds")
        storage.setCodable(actions, forKey: "actions")
    }

    public func action(for id: String) -> ScriptActionItem? {
        actions.first(where: { $0.id == id })
    }

    public func addAction(_ action: ScriptActionItem) {
        actions.append(action)
        if !enabledActionIds.isEmpty {
            enabledActionIds.append(action.id)
        }
        save()
        ScriptRunwayService.shared.addAction(action)
        boundStore?._scriptsEnabledActionIds = enabledActionIds
    }

    public func removeAction(id: String) {
        actions.removeAll { $0.id == id }
        enabledActionIds.removeAll { $0 == id }
        save()
        ScriptRunwayService.shared.removeAction(id: id)
        boundStore?._scriptsEnabledActionIds = enabledActionIds
    }

    public func updateAction(_ action: ScriptActionItem) {
        if let idx = actions.firstIndex(where: { $0.id == action.id }) {
            actions[idx] = action
            save()
        }
        ScriptRunwayService.shared.updateAction(action)
    }

    public func resetToDefaults() {
        ScriptRunwayService.shared.resetToDefaults()
        actions = ScriptRunwayService.shared.actions
        enabledActionIds = actions.map(\.id)
        save()
        boundStore?._scriptsEnabledActionIds = enabledActionIds
    }

    public func stopRunningScript() {
        ScriptRunwayService.shared.stopRunningScript()
        isRunning = false
        lastOutput = "⏹ Stopped by user"
        liveStreamingOutput = "⏹ Stopped by user"
        SensoryFeedbackService.shared.performControlHapticIfEnabled(.levelChange)
    }

    public func executeAction(_ action: ScriptActionItem, store: PurahWorkspaceStore? = nil) async -> (success: Bool, message: String) {
        isRunning = true
        lastExecutedActionId = action.id
        liveStreamingOutput = ""
        defer {
            isRunning = false
        }
        let result = await ScriptRunwayService.shared.executeAction(action) { [weak self] chunkTail in
            guard let self = self else { return }
            self.liveStreamingOutput = chunkTail
            self.lastOutput = chunkTail
        }
        lastOutput = result.message
        liveStreamingOutput = result.message
        return result
    }

    public func mount(store: PurahWorkspaceStore) {
        self.boundStore = store
        self.isDecomposed = store._isScriptsDecomposed
        if !store._scriptsEnabledActionIds.isEmpty {
            self.enabledActionIds = store._scriptsEnabledActionIds
        }
        if actions.isEmpty {
            actions = ScriptRunwayService.shared.actions
        }
    }

    public func unmount(store: PurahWorkspaceStore) {
        save()
        if boundStore === store {
            boundStore = nil
        }
    }
}
