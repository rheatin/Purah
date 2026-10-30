// Sources/PurahUI/Plugins/States/ClipboardPluginState.swift
import SwiftUI
import AppKit
import Foundation
import Observation
import PurahCore

public enum ClipboardCategoryFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case favorite = "Starred"
    case text = "Text"
    case color = "Color"
    case image = "Image"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .favorite: return "star.fill"
        case .text: return "doc.text"
        case .color: return "paintpalette"
        case .image: return "photo"
        }
    }
}

@Observable
@MainActor
public final class ClipboardPluginState: Sendable {
    public var isDecomposed: Bool
    public var maxRailItems: Int
    public var retentionPeriod: ClipboardRetentionPeriod
    public var diskQuota: ClipboardDiskQuota
    public var autoPruneOnQuota: Bool
    public var items: [ClipboardItem]
    /// Search and filter live here, not in the drawer: the header's magnifier
    /// opens them in a popover and the list below is the same list.
    public var searchText: String = ""
    public var selectedFilter: ClipboardCategoryFilter = .all
    public let storage: any PurahPluginStorage
    @ObservationIgnored private weak var boundStore: PurahWorkspaceStore?

    /// Whether a query or a category is narrowing the list, so the header can
    /// show that the drawer is not showing everything.
    public var isFiltering: Bool {
        selectedFilter != .all || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var filteredItems: [ClipboardItem] {
        var baseItems = items
        switch selectedFilter {
        case .all:
            break
        case .favorite:
            baseItems = baseItems.filter(\.isFavorite)
        case .text:
            baseItems = baseItems.filter { if case .text = $0.type { return true }; return false }
        case .color:
            baseItems = baseItems.filter { if case .color = $0.type { return true }; return false }
        case .image:
            baseItems = baseItems.filter { if case .image = $0.type { return true }; return false }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return baseItems }

        return baseItems.compactMap { item -> (item: ClipboardItem, score: Int)? in
            let match = FuzzySearchEngine.match(query: query, in: item.searchableContent)
            guard match.matched else { return nil }
            return (item, match.score)
        }
        .sorted { $0.score > $1.score }
        .map(\.item)
    }

    public func clearFilters() {
        searchText = ""
        selectedFilter = .all
    }

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
        // The history read below starts an asynchronous load and returns empty
        // the first time; without this the drawer stayed blank after a fresh
        // launch until the next copy happened to refresh it.
        SystemClipboardSyncService.shared.onHistoryLoaded = { [weak self] in
            self?.items = SystemClipboardSyncService.shared.history
        }
        self.items = SystemClipboardSyncService.shared.history
    }

    public func unmount(store: PurahWorkspaceStore) {
        SystemClipboardSyncService.shared.stopListening()
        SystemClipboardSyncService.shared.onItemAdded = nil
        SystemClipboardSyncService.shared.onHistoryLoaded = nil
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
