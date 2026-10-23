// Sources/PurahUI/Plugins/States/ClipboardPluginState.swift
import SwiftUI
import AppKit
import Foundation
import Observation
import PurahCore

@Observable
@MainActor
public final class ClipboardPluginState: Sendable {
    public var isDecomposed: Bool
    public var maxRailItems: Int
    public var retentionPeriod: ClipboardRetentionPeriod
    public var diskQuota: ClipboardDiskQuota
    public var autoPruneOnQuota: Bool
    public var items: [ClipboardItem]
    public let storage: any PurahPluginStorage
    @ObservationIgnored private weak var boundStore: PurahWorkspaceStore?

    public init(storage: any PurahPluginStorage = ScopedPluginStorage(pluginId: "clipboard")) {
        self.storage = storage
        if storage.string(forKey: "isDecomposed") != nil {
            self.isDecomposed = storage.bool(forKey: "isDecomposed")
        } else {
            self.isDecomposed = true // Default decomposed principle
        }
        let savedMax = storage.int(forKey: "maxRailItems")
        self.maxRailItems = (savedMax > 0) ? savedMax : 4

        let retention = storage.codable(forKey: "retentionPeriod", as: ClipboardRetentionPeriod.self) ?? .sevenDays
        let quota = storage.codable(forKey: "diskQuota", as: ClipboardDiskQuota.self) ?? .mb500
        let autoPrune = storage.string(forKey: "autoPruneOnQuota") != nil ? storage.bool(forKey: "autoPruneOnQuota") : true

        self.retentionPeriod = retention
        self.diskQuota = quota
        self.autoPruneOnQuota = autoPrune
        self.items = SystemClipboardSyncService.shared.history

        // Configure underlying service with user preferences
        SystemClipboardSyncService.shared.retentionPeriod = retention
        SystemClipboardSyncService.shared.diskQuota = quota
        SystemClipboardSyncService.shared.autoPruneOnQuota = autoPrune

        // Purge legacy bloated JSON history from UserDefaults to release resident process memory
        storage.removeObject(forKey: "history")
    }

    public func mount(store: PurahWorkspaceStore) {
        self.boundStore = store
        store.clipboardMaxRailItems = self.maxRailItems

        SystemClipboardSyncService.shared.retentionPeriod = self.retentionPeriod
        SystemClipboardSyncService.shared.diskQuota = self.diskQuota
        SystemClipboardSyncService.shared.autoPruneOnQuota = self.autoPruneOnQuota
        SystemClipboardSyncService.shared.onQuotaWarning = { [weak store] msg in
            store?.onCapacityWarningToast?(msg)
        }

        // Lazy lifecycle: Only initiate pasteboard polling when the clipboard pod is active/enabled
        if store.pods.first(where: { $0.id == "clipboard" })?.isEnabled == true {
            SystemClipboardSyncService.shared.startListening()
        }
        SystemClipboardSyncService.shared.onItemAdded = { [weak self] _ in
            self?.items = SystemClipboardSyncService.shared.history
        }
        self.items = SystemClipboardSyncService.shared.history
    }

    public func unmount(store: PurahWorkspaceStore) {
        SystemClipboardSyncService.shared.stopListening()
        SystemClipboardSyncService.shared.onItemAdded = nil
        SystemClipboardSyncService.shared.onQuotaWarning = nil
        save()
        if boundStore === store {
            boundStore = nil
        }
    }

    public func save() {
        storage.set(isDecomposed, forKey: "isDecomposed")
        storage.set(maxRailItems, forKey: "maxRailItems")
        storage.setCodable(retentionPeriod, forKey: "retentionPeriod")
        storage.setCodable(diskQuota, forKey: "diskQuota")
        storage.set(autoPruneOnQuota, forKey: "autoPruneOnQuota")

        SystemClipboardSyncService.shared.retentionPeriod = self.retentionPeriod
        SystemClipboardSyncService.shared.diskQuota = self.diskQuota
        SystemClipboardSyncService.shared.autoPruneOnQuota = self.autoPruneOnQuota
    }

    public func toggleFavorite(id: String) {
        SystemClipboardSyncService.shared.toggleFavorite(id: id)
        self.items = SystemClipboardSyncService.shared.history
    }

    public func togglePin(id: String) {
        toggleFavorite(id: id)
    }

    public func moveItem(from sourceIndex: Int, to destinationIndex: Int) {
        SystemClipboardSyncService.shared.moveItem(from: sourceIndex, to: destinationIndex)
        self.items = SystemClipboardSyncService.shared.history
    }

    public func copyItem(_ item: ClipboardItem) {
        SystemClipboardSyncService.shared.copyToPasteboard(item)
    }

    public func deleteItem(id: String) {
        SystemClipboardSyncService.shared.deleteItem(id: id)
        self.items = SystemClipboardSyncService.shared.history
    }

    public func clearAll(keepFavorites: Bool = true) {
        SystemClipboardSyncService.shared.clearAll(keepFavorites: keepFavorites)
        self.items = SystemClipboardSyncService.shared.history
    }

    public func clearHistory(keepFavorites: Bool = true) {
        clearAll(keepFavorites: keepFavorites)
    }

    public func clearAll(keepPinned: Bool) {
        clearAll(keepFavorites: keepPinned)
    }
}
